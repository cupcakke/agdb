#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifdef __linux__
#include <tss2/tss2_esys.h>
#include <tss2/tss2_rc.h>
#include <tss2/tss2_tctildr.h>
#include <tss2/tss2_mu.h>
#else
#error "This implementation requires Linux with the tpm2-tss libraries and a real TPM 2.0 device"
#endif

typedef struct {
    void *esys_ctx;
    void *tcti_ctx;
    uint32_t nv_index;
    uint64_t monotonic_counter;
    int initialized;
    char last_error[256];
} tpm2_context_t;

typedef struct {
    uint8_t digest[32];
    uint16_t size;
} tpm2_digest_t;

#define TPM2_BUFFER_CAPACITY 2048

typedef struct {
    uint8_t data[TPM2_BUFFER_CAPACITY];
    uint16_t size;
} tpm2_buffer_t;

#define PCR_SELECT_MAX 24
#define TPM2_PCR_SELECT_BYTES 3
#define TPM2_NV_COUNTER_SIZE 8
#define TPM2_SEAL_DATA_MAX (sizeof(((TPM2B_SENSITIVE_CREATE *)NULL)->sensitive.data.buffer))

static int tpm2_error(tpm2_context_t *ctx, const char *msg) {
    if (ctx && msg) {
        snprintf(ctx->last_error, sizeof(ctx->last_error), "%s", msg);
    }
    return -1;
}

static int tpm2_error_rc(tpm2_context_t *ctx, const char *msg, TSS2_RC rc) {
    if (ctx && msg) {
        const char *decoded = Tss2_RC_Decode(rc);
        snprintf(ctx->last_error,
                 sizeof(ctx->last_error),
                 "%s: %s (0x%08X)",
                 msg,
                 decoded ? decoded : "unknown error",
                 (unsigned int)rc);
    }
    return -1;
}

static void tpm2_clear_error(tpm2_context_t *ctx) {
    if (ctx) {
        ctx->last_error[0] = '\0';
    }
}

static void tpm2_secure_zero(void *ptr, size_t len) {
    volatile uint8_t *p = (volatile uint8_t *)ptr;
    while (len-- > 0) {
        *p++ = 0;
    }
}

static int tpm2_build_pcr_selection(uint32_t pcr_mask, TPML_PCR_SELECTION *selection) {
    if (!selection) {
        return -1;
    }
    if ((pcr_mask >> PCR_SELECT_MAX) != 0) {
        return -1;
    }

    memset(selection, 0, sizeof(*selection));
    selection->count = 1;
    selection->pcrSelections[0].hash = TPM2_ALG_SHA256;
    selection->pcrSelections[0].sizeofSelect = TPM2_PCR_SELECT_BYTES;

    for (uint32_t i = 0; i < PCR_SELECT_MAX; i++) {
        if (pcr_mask & (1U << i)) {
            selection->pcrSelections[0].pcrSelect[i / 8] |= (uint8_t)(1U << (i % 8));
        }
    }

    return 0;
}

static TSS2_RC tpm2_create_primary(ESYS_CONTEXT *esys, ESYS_TR *primary_handle) {
    TPM2B_SENSITIVE_CREATE in_sensitive;
    TPM2B_PUBLIC in_public;
    TPM2B_DATA outside_info;
    TPML_PCR_SELECTION creation_pcr;
    TPM2B_PUBLIC *out_public = NULL;
    TPM2B_CREATION_DATA *creation_data = NULL;
    TPM2B_DIGEST *creation_hash = NULL;
    TPMT_TK_CREATION *creation_ticket = NULL;
    ESYS_TR handle = ESYS_TR_NONE;
    TSS2_RC rc;

    memset(&in_sensitive, 0, sizeof(in_sensitive));
    memset(&in_public, 0, sizeof(in_public));
    memset(&outside_info, 0, sizeof(outside_info));
    memset(&creation_pcr, 0, sizeof(creation_pcr));

    in_public.publicArea.type = TPM2_ALG_ECC;
    in_public.publicArea.nameAlg = TPM2_ALG_SHA256;
    in_public.publicArea.objectAttributes = TPMA_OBJECT_FIXEDTPM |
                                            TPMA_OBJECT_FIXEDPARENT |
                                            TPMA_OBJECT_SENSITIVEDATAORIGIN |
                                            TPMA_OBJECT_USERWITHAUTH |
                                            TPMA_OBJECT_NODA |
                                            TPMA_OBJECT_RESTRICTED |
                                            TPMA_OBJECT_DECRYPT;
    in_public.publicArea.parameters.eccDetail.symmetric.algorithm = TPM2_ALG_AES;
    in_public.publicArea.parameters.eccDetail.symmetric.keyBits.aes = 128;
    in_public.publicArea.parameters.eccDetail.symmetric.mode.aes = TPM2_ALG_CFB;
    in_public.publicArea.parameters.eccDetail.scheme.scheme = TPM2_ALG_NULL;
    in_public.publicArea.parameters.eccDetail.curveID = TPM2_ECC_NIST_P256;
    in_public.publicArea.parameters.eccDetail.kdf.scheme = TPM2_ALG_NULL;

    rc = Esys_CreatePrimary(esys,
                            ESYS_TR_RH_OWNER,
                            ESYS_TR_PASSWORD,
                            ESYS_TR_NONE,
                            ESYS_TR_NONE,
                            &in_sensitive,
                            &in_public,
                            &outside_info,
                            &creation_pcr,
                            &handle,
                            &out_public,
                            &creation_data,
                            &creation_hash,
                            &creation_ticket);

    Esys_Free(out_public);
    Esys_Free(creation_data);
    Esys_Free(creation_hash);
    Esys_Free(creation_ticket);

    if (rc != TSS2_RC_SUCCESS) {
        return rc;
    }

    *primary_handle = handle;
    return TSS2_RC_SUCCESS;
}

static TSS2_RC tpm2_start_session(ESYS_CONTEXT *esys, TPM2_SE session_type, ESYS_TR *session) {
    TPMT_SYM_DEF symmetric;

    memset(&symmetric, 0, sizeof(symmetric));
    symmetric.algorithm = TPM2_ALG_NULL;

    return Esys_StartAuthSession(esys,
                                 ESYS_TR_NONE,
                                 ESYS_TR_NONE,
                                 ESYS_TR_NONE,
                                 ESYS_TR_NONE,
                                 ESYS_TR_NONE,
                                 NULL,
                                 session_type,
                                 &symmetric,
                                 TPM2_ALG_SHA256,
                                 session);
}

static TSS2_RC tpm2_apply_pcr_policy(ESYS_CONTEXT *esys,
                                     ESYS_TR session,
                                     const TPML_PCR_SELECTION *selection) {
    TPM2B_DIGEST pcr_digest;

    memset(&pcr_digest, 0, sizeof(pcr_digest));

    return Esys_PolicyPCR(esys,
                          session,
                          ESYS_TR_NONE,
                          ESYS_TR_NONE,
                          ESYS_TR_NONE,
                          &pcr_digest,
                          selection);
}

static TSS2_RC tpm2_compute_pcr_policy(ESYS_CONTEXT *esys,
                                       const TPML_PCR_SELECTION *selection,
                                       TPM2B_DIGEST *policy) {
    ESYS_TR session = ESYS_TR_NONE;
    TPM2B_DIGEST *digest = NULL;
    TSS2_RC rc;

    rc = tpm2_start_session(esys, TPM2_SE_TRIAL, &session);
    if (rc != TSS2_RC_SUCCESS) {
        return rc;
    }

    rc = tpm2_apply_pcr_policy(esys, session, selection);

    if (rc == TSS2_RC_SUCCESS) {
        rc = Esys_PolicyGetDigest(esys,
                                  session,
                                  ESYS_TR_NONE,
                                  ESYS_TR_NONE,
                                  ESYS_TR_NONE,
                                  &digest);
    }

    if (rc == TSS2_RC_SUCCESS) {
        if (digest == NULL) {
            rc = TSS2_ESYS_RC_GENERAL_FAILURE;
        } else {
            *policy = *digest;
        }
    }

    Esys_Free(digest);
    Esys_FlushContext(esys, session);

    return rc;
}

static TSS2_RC tpm2_start_policy_session(ESYS_CONTEXT *esys,
                                         const TPML_PCR_SELECTION *selection,
                                         ESYS_TR *session) {
    ESYS_TR handle = ESYS_TR_NONE;
    TSS2_RC rc;

    rc = tpm2_start_session(esys, TPM2_SE_POLICY, &handle);
    if (rc != TSS2_RC_SUCCESS) {
        return rc;
    }

    rc = Esys_TRSess_SetAttributes(esys, handle, TPMA_SESSION_CONTINUESESSION, 0xFF);
    if (rc == TSS2_RC_SUCCESS) {
        rc = tpm2_apply_pcr_policy(esys, handle, selection);
    }

    if (rc != TSS2_RC_SUCCESS) {
        Esys_FlushContext(esys, handle);
        return rc;
    }

    *session = handle;
    return TSS2_RC_SUCCESS;
}

int tpm2_init(tpm2_context_t *ctx, const char *tcti_conf) {
    TSS2_RC rc;
    ESYS_CONTEXT *esys_ctx = NULL;
    TSS2_TCTI_CONTEXT *tcti_ctx = NULL;

    if (!ctx) return -1;

    if (ctx->initialized) {
        return tpm2_error(ctx, "Context is already initialized");
    }

    memset(ctx, 0, sizeof(*ctx));

    if (tcti_conf == NULL) {
        tcti_conf = getenv("TPM2TOOLS_TCTI");
        if (tcti_conf == NULL || tcti_conf[0] == '\0') {
            tcti_conf = "device:/dev/tpmrm0";
        }
    }

    rc = Tss2_TctiLdr_Initialize(tcti_conf, &tcti_ctx);
    if (rc != TSS2_RC_SUCCESS) {
        return tpm2_error_rc(ctx, "Failed to initialize TCTI", rc);
    }

    rc = Esys_Initialize(&esys_ctx, tcti_ctx, NULL);
    if (rc != TSS2_RC_SUCCESS) {
        Tss2_TctiLdr_Finalize(&tcti_ctx);
        return tpm2_error_rc(ctx, "Failed to initialize ESYS", rc);
    }

    ctx->esys_ctx = esys_ctx;
    ctx->tcti_ctx = tcti_ctx;
    ctx->initialized = 1;

    return 0;
}

void tpm2_deinit(tpm2_context_t *ctx) {
    ESYS_CONTEXT *esys_ctx;
    TSS2_TCTI_CONTEXT *tcti_ctx;

    if (!ctx || !ctx->initialized) return;

    esys_ctx = (ESYS_CONTEXT *)ctx->esys_ctx;
    tcti_ctx = (TSS2_TCTI_CONTEXT *)ctx->tcti_ctx;

    if (esys_ctx) {
        Esys_Finalize(&esys_ctx);
    }
    if (tcti_ctx) {
        Tss2_TctiLdr_Finalize(&tcti_ctx);
    }

    memset(ctx, 0, sizeof(*ctx));
}

int tpm2_read_pcr(tpm2_context_t *ctx, uint32_t pcr_index, tpm2_digest_t *digest) {
    ESYS_CONTEXT *esys;
    TPML_PCR_SELECTION pcr_selection;
    TPML_DIGEST *pcr_values = NULL;
    TSS2_RC rc;
    int result = -1;

    tpm2_clear_error(ctx);

    if (!ctx || !ctx->initialized || !digest) {
        return tpm2_error(ctx, "Invalid parameters");
    }

    if (pcr_index >= PCR_SELECT_MAX) {
        return tpm2_error(ctx, "PCR index out of range");
    }

    memset(digest, 0, sizeof(*digest));
    memset(&pcr_selection, 0, sizeof(pcr_selection));

    esys = (ESYS_CONTEXT *)ctx->esys_ctx;

    pcr_selection.count = 1;
    pcr_selection.pcrSelections[0].hash = TPM2_ALG_SHA256;
    pcr_selection.pcrSelections[0].sizeofSelect = TPM2_PCR_SELECT_BYTES;
    pcr_selection.pcrSelections[0].pcrSelect[pcr_index / 8] = (uint8_t)(1U << (pcr_index % 8));

    rc = Esys_PCR_Read(esys,
                       ESYS_TR_NONE,
                       ESYS_TR_NONE,
                       ESYS_TR_NONE,
                       &pcr_selection,
                       NULL,
                       NULL,
                       &pcr_values);

    if (rc != TSS2_RC_SUCCESS) {
        return tpm2_error_rc(ctx, "Failed to read PCR", rc);
    }

    if (pcr_values == NULL || pcr_values->count == 0) {
        tpm2_error(ctx, "TPM returned no PCR value");
        goto cleanup;
    }

    if (pcr_values->digests[0].size > sizeof(digest->digest)) {
        tpm2_error(ctx, "PCR digest is larger than the output buffer");
        goto cleanup;
    }

    digest->size = pcr_values->digests[0].size;
    memcpy(digest->digest, pcr_values->digests[0].buffer, digest->size);
    result = 0;

cleanup:
    Esys_Free(pcr_values);
    return result;
}

int tpm2_seal(tpm2_context_t *ctx,
              const uint8_t *data,
              size_t data_len,
              uint32_t pcr_mask,
              tpm2_buffer_t *sealed) {
    ESYS_CONTEXT *esys;
    ESYS_TR primary_handle = ESYS_TR_NONE;
    TSS2_RC rc;
    int result = -1;
    size_t offset = 0;

    TPM2B_SENSITIVE_CREATE in_sensitive;
    TPM2B_PUBLIC in_public;
    TPM2B_DATA outside_info;
    TPML_PCR_SELECTION creation_pcr;
    TPM2B_PUBLIC *out_public = NULL;
    TPM2B_PRIVATE *out_private = NULL;
    TPM2B_CREATION_DATA *creation_data = NULL;
    TPM2B_DIGEST *creation_hash = NULL;
    TPMT_TK_CREATION *creation_ticket = NULL;

    tpm2_clear_error(ctx);

    if (!ctx || !ctx->initialized || !data || !sealed || data_len == 0) {
        return tpm2_error(ctx, "Invalid parameters");
    }

    if ((pcr_mask >> PCR_SELECT_MAX) != 0) {
        return tpm2_error(ctx, "pcr_mask selects PCRs beyond PCR 23");
    }

    if (data_len > TPM2_SEAL_DATA_MAX) {
        return tpm2_error(ctx, "Data is too large to seal");
    }

    memset(sealed, 0, sizeof(*sealed));
    memset(&in_sensitive, 0, sizeof(in_sensitive));
    memset(&in_public, 0, sizeof(in_public));
    memset(&outside_info, 0, sizeof(outside_info));
    memset(&creation_pcr, 0, sizeof(creation_pcr));

    esys = (ESYS_CONTEXT *)ctx->esys_ctx;

    rc = tpm2_create_primary(esys, &primary_handle);
    if (rc != TSS2_RC_SUCCESS) {
        tpm2_error_rc(ctx, "Failed to create primary key", rc);
        goto cleanup;
    }

    in_public.publicArea.type = TPM2_ALG_KEYEDHASH;
    in_public.publicArea.nameAlg = TPM2_ALG_SHA256;
    in_public.publicArea.objectAttributes = TPMA_OBJECT_FIXEDTPM | TPMA_OBJECT_FIXEDPARENT;
    in_public.publicArea.parameters.keyedHashDetail.scheme.scheme = TPM2_ALG_NULL;

    if (pcr_mask != 0) {
        if (tpm2_build_pcr_selection(pcr_mask, &creation_pcr) != 0) {
            tpm2_error(ctx, "Failed to build PCR selection");
            goto cleanup;
        }

        rc = tpm2_compute_pcr_policy(esys, &creation_pcr, &in_public.publicArea.authPolicy);
        if (rc != TSS2_RC_SUCCESS) {
            tpm2_error_rc(ctx, "Failed to compute PCR policy", rc);
            goto cleanup;
        }
    } else {
        in_public.publicArea.objectAttributes |= TPMA_OBJECT_USERWITHAUTH;
    }

    in_sensitive.sensitive.data.size = (uint16_t)data_len;
    memcpy(in_sensitive.sensitive.data.buffer, data, data_len);

    rc = Esys_Create(esys,
                     primary_handle,
                     ESYS_TR_PASSWORD,
                     ESYS_TR_NONE,
                     ESYS_TR_NONE,
                     &in_sensitive,
                     &in_public,
                     &outside_info,
                     &creation_pcr,
                     &out_private,
                     &out_public,
                     &creation_data,
                     &creation_hash,
                     &creation_ticket);

    if (rc != TSS2_RC_SUCCESS) {
        tpm2_error_rc(ctx, "Failed to seal data", rc);
        goto cleanup;
    }

    if (out_public == NULL || out_private == NULL) {
        tpm2_error(ctx, "TPM returned an incomplete sealed object");
        goto cleanup;
    }

    rc = Tss2_MU_TPM2B_PUBLIC_Marshal(out_public, sealed->data, sizeof(sealed->data), &offset);
    if (rc != TSS2_RC_SUCCESS) {
        tpm2_error_rc(ctx, "Failed to serialize public area", rc);
        goto cleanup;
    }

    rc = Tss2_MU_TPM2B_PRIVATE_Marshal(out_private, sealed->data, sizeof(sealed->data), &offset);
    if (rc != TSS2_RC_SUCCESS) {
        tpm2_error_rc(ctx, "Failed to serialize private area", rc);
        goto cleanup;
    }

    sealed->size = (uint16_t)offset;
    result = 0;

cleanup:
    if (result != 0) {
        memset(sealed, 0, sizeof(*sealed));
    }
    tpm2_secure_zero(&in_sensitive, sizeof(in_sensitive));
    Esys_Free(out_public);
    Esys_Free(out_private);
    Esys_Free(creation_data);
    Esys_Free(creation_hash);
    Esys_Free(creation_ticket);
    if (primary_handle != ESYS_TR_NONE) {
        Esys_FlushContext(esys, primary_handle);
    }

    return result;
}

int tpm2_unseal(tpm2_context_t *ctx,
                const tpm2_buffer_t *sealed,
                uint32_t pcr_mask,
                uint8_t *data,
                size_t *data_len) {
    ESYS_CONTEXT *esys;
    ESYS_TR primary_handle = ESYS_TR_NONE;
    ESYS_TR sealed_handle = ESYS_TR_NONE;
    ESYS_TR policy_session = ESYS_TR_NONE;
    ESYS_TR auth_session = ESYS_TR_PASSWORD;
    TPM2B_SENSITIVE_DATA *unsealed_data = NULL;
    TPM2B_PRIVATE sealed_private;
    TPM2B_PUBLIC sealed_public;
    TPML_PCR_SELECTION selection;
    size_t offset = 0;
    int bound;
    TSS2_RC rc;
    int result = -1;

    tpm2_clear_error(ctx);

    if (!ctx || !ctx->initialized || !sealed || !data || !data_len) {
        return tpm2_error(ctx, "Invalid parameters");
    }

    if (sealed->size == 0 || sealed->size > sizeof(sealed->data)) {
        return tpm2_error(ctx, "Sealed blob has an invalid size");
    }

    if ((pcr_mask >> PCR_SELECT_MAX) != 0) {
        return tpm2_error(ctx, "pcr_mask selects PCRs beyond PCR 23");
    }

    memset(&sealed_private, 0, sizeof(sealed_private));
    memset(&sealed_public, 0, sizeof(sealed_public));
    memset(&selection, 0, sizeof(selection));

    esys = (ESYS_CONTEXT *)ctx->esys_ctx;

    rc = Tss2_MU_TPM2B_PUBLIC_Unmarshal(sealed->data, sealed->size, &offset, &sealed_public);
    if (rc != TSS2_RC_SUCCESS) {
        return tpm2_error_rc(ctx, "Failed to parse sealed public area", rc);
    }

    rc = Tss2_MU_TPM2B_PRIVATE_Unmarshal(sealed->data, sealed->size, &offset, &sealed_private);
    if (rc != TSS2_RC_SUCCESS) {
        return tpm2_error_rc(ctx, "Failed to parse sealed private area", rc);
    }

    if (offset != sealed->size) {
        return tpm2_error(ctx, "Sealed blob contains trailing data");
    }

    bound = sealed_public.publicArea.authPolicy.size != 0;

    if (bound && pcr_mask == 0) {
        return tpm2_error(ctx, "Sealed object is bound to PCRs but pcr_mask is empty");
    }

    if (!bound && pcr_mask != 0) {
        return tpm2_error(ctx, "Sealed object is not bound to PCRs but pcr_mask is set");
    }

    rc = tpm2_create_primary(esys, &primary_handle);
    if (rc != TSS2_RC_SUCCESS) {
        tpm2_error_rc(ctx, "Failed to create primary key", rc);
        goto cleanup;
    }

    rc = Esys_Load(esys,
                   primary_handle,
                   ESYS_TR_PASSWORD,
                   ESYS_TR_NONE,
                   ESYS_TR_NONE,
                   &sealed_private,
                   &sealed_public,
                   &sealed_handle);

    if (rc != TSS2_RC_SUCCESS) {
        tpm2_error_rc(ctx, "Failed to load sealed object", rc);
        goto cleanup;
    }

    if (bound) {
        if (tpm2_build_pcr_selection(pcr_mask, &selection) != 0) {
            tpm2_error(ctx, "Failed to build PCR selection");
            goto cleanup;
        }

        rc = tpm2_start_policy_session(esys, &selection, &policy_session);
        if (rc != TSS2_RC_SUCCESS) {
            tpm2_error_rc(ctx, "Failed to start PCR policy session", rc);
            goto cleanup;
        }

        auth_session = policy_session;
    }

    rc = Esys_Unseal(esys,
                     sealed_handle,
                     auth_session,
                     ESYS_TR_NONE,
                     ESYS_TR_NONE,
                     &unsealed_data);

    if (rc != TSS2_RC_SUCCESS) {
        tpm2_error_rc(ctx, "Failed to unseal data", rc);
        goto cleanup;
    }

    if (unsealed_data == NULL) {
        tpm2_error(ctx, "TPM returned no unsealed data");
        goto cleanup;
    }

    if (unsealed_data->size > *data_len) {
        *data_len = unsealed_data->size;
        tpm2_error(ctx, "Output buffer is too small for the unsealed data");
        goto cleanup;
    }

    memcpy(data, unsealed_data->buffer, unsealed_data->size);
    *data_len = unsealed_data->size;
    result = 0;

cleanup:
    if (unsealed_data) {
        tpm2_secure_zero(unsealed_data, sizeof(*unsealed_data));
        Esys_Free(unsealed_data);
    }
    if (policy_session != ESYS_TR_NONE) {
        Esys_FlushContext(esys, policy_session);
    }
    if (sealed_handle != ESYS_TR_NONE) {
        Esys_FlushContext(esys, sealed_handle);
    }
    if (primary_handle != ESYS_TR_NONE) {
        Esys_FlushContext(esys, primary_handle);
    }

    return result;
}

int tpm2_increment_nv_counter(tpm2_context_t *ctx, uint32_t nv_index, uint64_t *counter) {
    ESYS_CONTEXT *esys;
    ESYS_TR nv_handle = ESYS_TR_NONE;
    TPM2B_MAX_NV_BUFFER *nv_data = NULL;
    uint64_t value = 0;
    TSS2_RC rc;
    int result = -1;

    tpm2_clear_error(ctx);

    if (!ctx || !ctx->initialized || !counter) {
        return tpm2_error(ctx, "Invalid parameters");
    }

    if ((nv_index & 0xFF000000U) != ((uint32_t)TPM2_HT_NV << 24)) {
        return tpm2_error(ctx, "NV index is outside the NV handle range");
    }

    esys = (ESYS_CONTEXT *)ctx->esys_ctx;

    rc = Esys_TR_FromTPMPublic(esys,
                               nv_index,
                               ESYS_TR_NONE,
                               ESYS_TR_NONE,
                               ESYS_TR_NONE,
                               &nv_handle);

    if (rc != TSS2_RC_SUCCESS) {
        if ((rc & ~((TSS2_RC)TPM2_RC_N_MASK)) == (TSS2_RC)TPM2_RC_HANDLE) {
            TPM2B_NV_PUBLIC public_info;

            memset(&public_info, 0, sizeof(public_info));
            public_info.nvPublic.nvIndex = nv_index;
            public_info.nvPublic.nameAlg = TPM2_ALG_SHA256;
            public_info.nvPublic.attributes = TPMA_NV_OWNERWRITE |
                                              TPMA_NV_OWNERREAD |
                                              ((TPMA_NV)TPM2_NT_COUNTER << TPMA_NV_TPM2_NT_SHIFT);
            public_info.nvPublic.dataSize = TPM2_NV_COUNTER_SIZE;

            nv_handle = ESYS_TR_NONE;
            rc = Esys_NV_DefineSpace(esys,
                                     ESYS_TR_RH_OWNER,
                                     ESYS_TR_PASSWORD,
                                     ESYS_TR_NONE,
                                     ESYS_TR_NONE,
                                     NULL,
                                     &public_info,
                                     &nv_handle);
            if (rc != TSS2_RC_SUCCESS) {
                tpm2_error_rc(ctx, "Failed to define NV space", rc);
                goto cleanup;
            }
        } else {
            tpm2_error_rc(ctx, "Failed to look up NV index", rc);
            goto cleanup;
        }
    }

    rc = Esys_NV_Increment(esys,
                           ESYS_TR_RH_OWNER,
                           nv_handle,
                           ESYS_TR_PASSWORD,
                           ESYS_TR_NONE,
                           ESYS_TR_NONE);
    if (rc != TSS2_RC_SUCCESS) {
        tpm2_error_rc(ctx, "Failed to increment NV counter", rc);
        goto cleanup;
    }

    rc = Esys_NV_Read(esys,
                      ESYS_TR_RH_OWNER,
                      nv_handle,
                      ESYS_TR_PASSWORD,
                      ESYS_TR_NONE,
                      ESYS_TR_NONE,
                      TPM2_NV_COUNTER_SIZE,
                      0,
                      &nv_data);
    if (rc != TSS2_RC_SUCCESS) {
        tpm2_error_rc(ctx, "Failed to read NV counter", rc);
        goto cleanup;
    }

    if (nv_data == NULL || nv_data->size != TPM2_NV_COUNTER_SIZE) {
        tpm2_error(ctx, "NV counter read returned an unexpected size");
        goto cleanup;
    }

    for (size_t i = 0; i < TPM2_NV_COUNTER_SIZE; i++) {
        value = (value << 8) | (uint64_t)nv_data->buffer[i];
    }

    *counter = value;
    ctx->monotonic_counter = value;
    ctx->nv_index = nv_index;
    result = 0;

cleanup:
    Esys_Free(nv_data);
    if (nv_handle != ESYS_TR_NONE) {
        Esys_TR_Close(esys, &nv_handle);
    }

    return result;
}

int tpm2_verify_pcr_policy(tpm2_context_t *ctx,
                          const tpm2_digest_t *expected_pcrs,
                          uint32_t pcr_mask,
                          uint32_t num_pcrs) {
    uint32_t selected = 0;
    uint32_t index = 0;

    tpm2_clear_error(ctx);

    if (!ctx || !ctx->initialized || !expected_pcrs) {
        return tpm2_error(ctx, "Invalid parameters");
    }

    if (pcr_mask == 0) {
        return tpm2_error(ctx, "pcr_mask selects no PCRs");
    }

    if ((pcr_mask >> PCR_SELECT_MAX) != 0) {
        return tpm2_error(ctx, "pcr_mask selects PCRs beyond PCR 23");
    }

    for (uint32_t i = 0; i < PCR_SELECT_MAX; i++) {
        if (pcr_mask & (1U << i)) {
            selected++;
        }
    }

    if (num_pcrs != selected) {
        return tpm2_error(ctx, "num_pcrs must equal the number of PCRs selected by pcr_mask");
    }

    for (uint32_t i = 0; i < PCR_SELECT_MAX; i++) {
        if (pcr_mask & (1U << i)) {
            tpm2_digest_t current;

            memset(&current, 0, sizeof(current));
            if (tpm2_read_pcr(ctx, i, &current) != 0) {
                return -1;
            }

            if (current.size != expected_pcrs[index].size ||
                memcmp(current.digest, expected_pcrs[index].digest, current.size) != 0) {
                return tpm2_error(ctx, "PCR mismatch");
            }

            index++;
        }
    }

    return 0;
}

const char* tpm2_get_last_error(tpm2_context_t *ctx) {
    return ctx ? ctx->last_error : "NULL context";
}

int tpm2_is_initialized(tpm2_context_t *ctx) {
    return ctx ? ctx->initialized : 0;
}

uint64_t tpm2_get_counter(tpm2_context_t *ctx) {
    return ctx ? ctx->monotonic_counter : 0;
}

uint32_t tpm2_get_nv_index(tpm2_context_t *ctx) {
    return ctx ? ctx->nv_index : 0;
}
