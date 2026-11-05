#ifndef _GNU_SOURCE  
#define _GNU_SOURCE
#endif

#ifdef __clang__
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wunused-const-variable"
#pragma clang diagnostic ignored "-Wparentheses"
#pragma clang diagnostic ignored "-Wunused-label"
#pragma clang diagnostic ignored "-Wunused-but-set-variable"
#elif __GNUC__
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-variable"
#pragma GCC diagnostic ignored "-Wunused-const-variable"
#pragma GCC diagnostic ignored "-Wparentheses"
#pragma GCC diagnostic ignored "-Wunused-label"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#endif

 
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <float.h>

#ifdef __cplusplus
extern "C" {
#endif

 
struct futhark_context_config;
struct futhark_context_config *futhark_context_config_new(void);
void futhark_context_config_free(struct futhark_context_config *cfg);
int futhark_context_config_set_tuning_param(struct futhark_context_config *cfg, const char *param_name, size_t new_value);
struct futhark_context;
struct futhark_context *futhark_context_new(struct futhark_context_config *cfg);
void futhark_context_free(struct futhark_context *cfg);
void futhark_context_config_set_debugging(struct futhark_context_config *cfg, int flag);
void futhark_context_config_set_profiling(struct futhark_context_config *cfg, int flag);
void futhark_context_config_set_logging(struct futhark_context_config *cfg, int flag);
int futhark_get_tuning_param_count(void);
const char *futhark_get_tuning_param_name(int);
const char *futhark_get_tuning_param_class(int);

 
struct futhark_f64_1d;
struct futhark_f64_1d *futhark_new_f64_1d(struct futhark_context *ctx, const double *data, int64_t dim0);
struct futhark_f64_1d *futhark_new_raw_f64_1d(struct futhark_context *ctx, unsigned char *data, int64_t dim0);
int futhark_free_f64_1d(struct futhark_context *ctx, struct futhark_f64_1d *arr);
int futhark_values_f64_1d(struct futhark_context *ctx, struct futhark_f64_1d *arr, double *data);
int futhark_index_f64_1d(struct futhark_context *ctx, double *out, struct futhark_f64_1d *arr, int64_t i0);
unsigned char *futhark_values_raw_f64_1d(struct futhark_context *ctx, struct futhark_f64_1d *arr);
const int64_t *futhark_shape_f64_1d(struct futhark_context *ctx, struct futhark_f64_1d *arr);
struct futhark_f64_2d;
struct futhark_f64_2d *futhark_new_f64_2d(struct futhark_context *ctx, const double *data, int64_t dim0, int64_t dim1);
struct futhark_f64_2d *futhark_new_raw_f64_2d(struct futhark_context *ctx, unsigned char *data, int64_t dim0, int64_t dim1);
int futhark_free_f64_2d(struct futhark_context *ctx, struct futhark_f64_2d *arr);
int futhark_values_f64_2d(struct futhark_context *ctx, struct futhark_f64_2d *arr, double *data);
int futhark_index_f64_2d(struct futhark_context *ctx, double *out, struct futhark_f64_2d *arr, int64_t i0, int64_t i1);
unsigned char *futhark_values_raw_f64_2d(struct futhark_context *ctx, struct futhark_f64_2d *arr);
const int64_t *futhark_shape_f64_2d(struct futhark_context *ctx, struct futhark_f64_2d *arr);
struct futhark_i64_1d;
struct futhark_i64_1d *futhark_new_i64_1d(struct futhark_context *ctx, const int64_t *data, int64_t dim0);
struct futhark_i64_1d *futhark_new_raw_i64_1d(struct futhark_context *ctx, unsigned char *data, int64_t dim0);
int futhark_free_i64_1d(struct futhark_context *ctx, struct futhark_i64_1d *arr);
int futhark_values_i64_1d(struct futhark_context *ctx, struct futhark_i64_1d *arr, int64_t *data);
int futhark_index_i64_1d(struct futhark_context *ctx, int64_t *out, struct futhark_i64_1d *arr, int64_t i0);
unsigned char *futhark_values_raw_i64_1d(struct futhark_context *ctx, struct futhark_i64_1d *arr);
const int64_t *futhark_shape_i64_1d(struct futhark_context *ctx, struct futhark_i64_1d *arr);
struct futhark_i64_2d;
struct futhark_i64_2d *futhark_new_i64_2d(struct futhark_context *ctx, const int64_t *data, int64_t dim0, int64_t dim1);
struct futhark_i64_2d *futhark_new_raw_i64_2d(struct futhark_context *ctx, unsigned char *data, int64_t dim0, int64_t dim1);
int futhark_free_i64_2d(struct futhark_context *ctx, struct futhark_i64_2d *arr);
int futhark_values_i64_2d(struct futhark_context *ctx, struct futhark_i64_2d *arr, int64_t *data);
int futhark_index_i64_2d(struct futhark_context *ctx, int64_t *out, struct futhark_i64_2d *arr, int64_t i0, int64_t i1);
unsigned char *futhark_values_raw_i64_2d(struct futhark_context *ctx, struct futhark_i64_2d *arr);
const int64_t *futhark_shape_i64_2d(struct futhark_context *ctx, struct futhark_i64_2d *arr);
struct futhark_i64_3d;
struct futhark_i64_3d *futhark_new_i64_3d(struct futhark_context *ctx, const int64_t *data, int64_t dim0, int64_t dim1, int64_t dim2);
struct futhark_i64_3d *futhark_new_raw_i64_3d(struct futhark_context *ctx, unsigned char *data, int64_t dim0, int64_t dim1, int64_t dim2);
int futhark_free_i64_3d(struct futhark_context *ctx, struct futhark_i64_3d *arr);
int futhark_values_i64_3d(struct futhark_context *ctx, struct futhark_i64_3d *arr, int64_t *data);
int futhark_index_i64_3d(struct futhark_context *ctx, int64_t *out, struct futhark_i64_3d *arr, int64_t i0, int64_t i1, int64_t i2);
unsigned char *futhark_values_raw_i64_3d(struct futhark_context *ctx, struct futhark_i64_3d *arr);
const int64_t *futhark_shape_i64_3d(struct futhark_context *ctx, struct futhark_i64_3d *arr);

 
struct futhark_opaque_tup2_arr1d_i64_arr1d_i64;
int futhark_free_opaque_tup2_arr1d_i64_arr1d_i64(struct futhark_context *ctx, struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *obj);
int futhark_store_opaque_tup2_arr1d_i64_arr1d_i64(struct futhark_context *ctx, const struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *obj, void **p, size_t *n);
struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *futhark_restore_opaque_tup2_arr1d_i64_arr1d_i64(struct futhark_context *ctx, const void *p);
int futhark_project_opaque_tup2_arr1d_i64_arr1d_i64_0(struct futhark_context *ctx, struct futhark_i64_1d **out, const struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *obj);
int futhark_project_opaque_tup2_arr1d_i64_arr1d_i64_1(struct futhark_context *ctx, struct futhark_i64_1d **out, const struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *obj);
int futhark_new_opaque_tup2_arr1d_i64_arr1d_i64(struct futhark_context *ctx, struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 **out, const struct futhark_i64_1d *f_0, const struct futhark_i64_1d *f_1);

 
int futhark_entry_all_positive(struct futhark_context *ctx, bool *out0, const struct futhark_i64_1d *in0);
int futhark_entry_any_positive(struct futhark_context *ctx, bool *out0, const struct futhark_i64_1d *in0);
int futhark_entry_convolve_1d(struct futhark_context *ctx, struct futhark_f64_1d **out0, const struct futhark_f64_1d *in0, const struct futhark_f64_1d *in1);
int futhark_entry_cosine_similarity(struct futhark_context *ctx, double *out0, const struct futhark_f64_1d *in0, const struct futhark_f64_1d *in1);
int futhark_entry_exponential_moving_average(struct futhark_context *ctx, struct futhark_f64_1d **out0, const struct futhark_f64_1d *in0, const double in1);
int futhark_entry_find_max(struct futhark_context *ctx, bool *out0, int64_t *out1, const struct futhark_i64_1d *in0);
int futhark_entry_find_min(struct futhark_context *ctx, bool *out0, int64_t *out1, const struct futhark_i64_1d *in0);
int futhark_entry_flatten_3d_array(struct futhark_context *ctx, struct futhark_i64_1d **out0, const struct futhark_i64_3d *in0);
int futhark_entry_gather(struct futhark_context *ctx, struct futhark_i64_1d **out0, const struct futhark_i64_1d *in0, const struct futhark_i64_1d *in1, const int64_t in2);
int futhark_entry_histogram(struct futhark_context *ctx, struct futhark_i64_1d **out0, const struct futhark_i64_1d *in0, const int64_t in1);
int futhark_entry_min_max_normalize(struct futhark_context *ctx, struct futhark_f64_1d **out0, const struct futhark_f64_1d *in0);
int futhark_entry_moving_average(struct futhark_context *ctx, struct futhark_f64_1d **out0, const struct futhark_f64_1d *in0, const int64_t in1);
int futhark_entry_partition_array(struct futhark_context *ctx, struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 **out0, const struct futhark_i64_1d *in0, const int64_t in1);
int futhark_entry_population_variance_array(struct futhark_context *ctx, double *out0, const struct futhark_f64_1d *in0);
int futhark_entry_scatter_array(struct futhark_context *ctx, struct futhark_i64_1d **out0, const struct futhark_i64_1d *in0, const struct futhark_i64_1d *in1, const struct futhark_i64_1d *in2);
int futhark_entry_softmax(struct futhark_context *ctx, struct futhark_f64_1d **out0, const struct futhark_f64_1d *in0);
int futhark_entry_std_dev_array(struct futhark_context *ctx, double *out0, const struct futhark_f64_1d *in0);
int futhark_entry_sum_matrix(struct futhark_context *ctx, double *out0, const struct futhark_f64_2d *in0);
int futhark_entry_update_array(struct futhark_context *ctx, struct futhark_i64_1d **out0, const struct futhark_i64_1d *in0, const int64_t in1, const int64_t in2);
int futhark_entry_update_matrix(struct futhark_context *ctx, struct futhark_i64_2d **out0, const struct futhark_i64_2d *in0, const int64_t in1, const int64_t in2, const int64_t in3);
int futhark_entry_variance_array(struct futhark_context *ctx, double *out0, const struct futhark_f64_1d *in0);

 
int futhark_context_sync(struct futhark_context *ctx);
void futhark_context_config_set_cache_file(struct futhark_context_config *cfg, const char *f);
char *futhark_context_get_error(struct futhark_context *ctx);
void futhark_context_set_logging_file(struct futhark_context *ctx, FILE *f);
void futhark_context_pause_profiling(struct futhark_context *ctx);
void futhark_context_unpause_profiling(struct futhark_context *ctx);
char *futhark_context_report(struct futhark_context *ctx);
int futhark_context_clear_caches(struct futhark_context *ctx);
#define FUTHARK_BACKEND_c
#define FUTHARK_SUCCESS 0
#define FUTHARK_PROGRAM_ERROR 2
#define FUTHARK_OUT_OF_MEMORY 3

#ifdef __cplusplus
}
#endif

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <math.h>
#include <stdint.h>
 
 
 
#undef NDEBUG
#include <assert.h>
#include <stdarg.h>
#define SCALAR_FUN_ATTR static inline
 
 
 

#include <errno.h>
#include <string.h>

static const char *fut_progname = "(embedded Futhark)";

static void futhark_panic(int eval, const char *fmt, ...) __attribute__((noreturn));
static char* msgprintf(const char *s, ...);
static void* slurp_file(const char *filename, size_t *size);
static int dump_file(const char *file, const void *buf, size_t n);
struct str_builder;
static void str_builder_init(struct str_builder *b);
static void str_builder(struct str_builder *b, const char *s, ...);
static char *strclone(const char *str);

static void futhark_panic(int eval, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "%s: ", fut_progname);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  exit(eval);
}

 
 
static char* msgprintf(const char *s, ...) {
  va_list vl;
  va_start(vl, s);
  size_t needed = 1 + (size_t)vsnprintf(NULL, 0, s, vl);
  char *buffer = (char*) malloc(needed);
  va_start(vl, s);  
  vsnprintf(buffer, needed, s, vl);
  return buffer;
}

static inline void check_err(int errval, int sets_errno, const char *fun, int line,
                             const char *msg, ...) {
  if (errval) {
    char errnum[10];

    va_list vl;
    va_start(vl, msg);

    fprintf(stderr, "ERROR: ");
    vfprintf(stderr, msg, vl);
    fprintf(stderr, " in %s() at line %d with error code %s\n",
            fun, line,
            sets_errno ? strerror(errno) : errnum);
    exit(errval);
  }
}

#define CHECK_ERR(err, ...) check_err(err, 0, __func__, __LINE__, __VA_ARGS__)
#define CHECK_ERRNO(err, ...) check_err(err, 1, __func__, __LINE__, __VA_ARGS__)

 
 
static void* fslurp_file(FILE *f, size_t *size) {
  long start = ftell(f);
  fseek(f, 0, SEEK_END);
  long src_size = ftell(f)-start;
  fseek(f, start, SEEK_SET);
  unsigned char *s = (unsigned char*) malloc((size_t)src_size + 1);
  if (fread(s, 1, (size_t)src_size, f) != (size_t)src_size) {
    free(s);
    s = NULL;
  } else {
    s[src_size] = '\0';
  }

  if (size) {
    *size = (size_t)src_size;
  }

  return s;
}

 
static void* slurp_file(const char *filename, size_t *size) {
  FILE *f = fopen(filename, "rb");  
  if (f == NULL) return NULL;
  unsigned char *s = fslurp_file(f, size);
  fclose(f);
  return s;
}

 
 
static int dump_file(const char *file, const void *buf, size_t n) {
  FILE *f = fopen(file, "w");

  if (f == NULL) {
    return 1;
  }

  if (fwrite(buf, sizeof(char), n, f) != n) {
    return 1;
  }

  if (fclose(f) != 0) {
    return 1;
  }

  return 0;
}

struct str_builder {
  char *str;
  size_t capacity;  
  size_t used;  
};

static void str_builder_init(struct str_builder *b) {
  b->capacity = 10;
  b->used = 0;
  b->str = malloc(b->capacity);
  b->str[0] = 0;
}

static void str_builder(struct str_builder *b, const char *s, ...) {
  va_list vl;
  va_start(vl, s);
  size_t needed = (size_t)vsnprintf(NULL, 0, s, vl);

  while (b->capacity < b->used + needed + 1) {
    b->capacity *= 2;
    b->str = realloc(b->str, b->capacity);
  }

  va_start(vl, s);  
  vsnprintf(b->str+b->used, b->capacity-b->used, s, vl);
  b->used += needed;
}

static void str_builder_str(struct str_builder *b, const char *s) {
  size_t needed = strlen(s);
  if (b->capacity < b->used + needed + 1) {
    b->capacity *= 2;
    b->str = realloc(b->str, b->capacity);
  }
  strcpy(b->str+b->used, s);
  b->used += needed;
}

static void str_builder_char(struct str_builder *b, char c) {
  size_t needed = 1;
  if (b->capacity < b->used + needed + 1) {
    b->capacity *= 2;
    b->str = realloc(b->str, b->capacity);
  }
  b->str[b->used] = c;
  b->str[b->used+1] = 0;
  b->used += needed;
}

static void str_builder_json_str(struct str_builder* sb, const char* s) {
  str_builder_char(sb, '"');
  for (int j = 0; s[j]; j++) {
    char c = s[j];
    switch (c) {
    case '\n':
      str_builder_str(sb, "\\n");
      break;
    case '"':
      str_builder_str(sb, "\\\"");
      break;
    default:
      str_builder_char(sb, c);
    }
  }
  str_builder_char(sb, '"');
}

static char *strclone(const char *str) {
  size_t size = strlen(str) + 1;
  char *copy = (char*) malloc(size);
  if (copy == NULL) {
    return NULL;
  }

  memcpy(copy, str, size);
  return copy;
}

 
static char *strconcat(const char *src_fragments[]) {
  size_t src_len = 0;
  const char **p;

  for (p = src_fragments; *p; p++) {
    src_len += strlen(*p);
  }

  char *src = (char*) malloc(src_len + 1);
  size_t n = 0;
  for (p = src_fragments; *p; p++) {
    strcpy(src + n, *p);
    n += strlen(*p);
  }

  return src;
}

 
 

#define CACHE_HASH_SIZE 8  

struct cache_hash {
  uint32_t hash[CACHE_HASH_SIZE];
};

 
static void cache_hash_init(struct cache_hash *c);

 
static void cache_hash(struct cache_hash *out, const char *in, size_t n);

 
 
 
 
 
 
 
 
static int cache_restore(const char *fname, const struct cache_hash *hash,
                         unsigned char **buf, size_t *buflen);

 
static int cache_store(const char *fname, const struct cache_hash *hash,
                       const unsigned char *buf, size_t buflen);

 

static void cache_hash_init(struct cache_hash *c) {
  memset(c->hash, 0, CACHE_HASH_SIZE * sizeof(uint32_t));
}

static void cache_hash(struct cache_hash *out, const char *in, size_t n) {
   
   
  uint32_t hash = 5381;
  for (size_t i = 0; i < n; i++) {
    hash = ((hash << 5) + hash) + in[i];
    out->hash[i % CACHE_HASH_SIZE] ^= hash;
  }
}

#define CACHE_HEADER_SIZE 8
static const char cache_header[CACHE_HEADER_SIZE] = "FUTHARK\0";

static int cache_restore(const char *fname, const struct cache_hash *hash,
                         unsigned char **buf, size_t *buflen) {
  FILE *f = fopen(fname, "rb");

  if (f == NULL) {
    return 1;
  }

  char f_header[CACHE_HEADER_SIZE];

  if (fread(f_header, sizeof(char), CACHE_HEADER_SIZE, f) != CACHE_HEADER_SIZE) {
    goto error;
  }

  if (memcmp(f_header, cache_header, CACHE_HEADER_SIZE) != 0) {
    goto error;
  }

  if (fseek(f, 0, SEEK_END) != 0) {
    goto error;
  }
  int64_t f_size = (int64_t)ftell(f);
  if (fseek(f, CACHE_HEADER_SIZE, SEEK_SET) != 0) {
    goto error;
  }

  int64_t expected_size;

  if (fread(&expected_size, sizeof(int64_t), 1, f) != 1) {
    goto error;
  }

  if (f_size != expected_size) {
    errno = 0;
    goto error;
  }

  int32_t f_hash[CACHE_HASH_SIZE];

  if (fread(f_hash, sizeof(int32_t), CACHE_HASH_SIZE, f) != CACHE_HASH_SIZE) {
    goto error;
  }

  if (memcmp(f_hash, hash->hash, CACHE_HASH_SIZE) != 0) {
    errno = 0;
    goto error;
  }

  *buflen = f_size - CACHE_HEADER_SIZE - sizeof(int64_t) - CACHE_HASH_SIZE*sizeof(int32_t);
  *buf = malloc(*buflen);
  if (fread(*buf, sizeof(char), *buflen, f) != *buflen) {
    free(*buf);
    goto error;
  }

  fclose(f);

  return 0;

 error:
  fclose(f);
  return 1;
}

static int cache_store(const char *fname, const struct cache_hash *hash,
                       const unsigned char *buf, size_t buflen) {
  FILE *f = fopen(fname, "wb");

  if (f == NULL) {
    return 1;
  }

  if (fwrite(cache_header, CACHE_HEADER_SIZE, 1, f) != 1) {
    goto error;
  }

  int64_t size = CACHE_HEADER_SIZE + sizeof(int64_t) + CACHE_HASH_SIZE*sizeof(int32_t) + buflen;

  if (fwrite(&size, sizeof(size), 1, f) != 1) {
    goto error;
  }

  if (fwrite(hash->hash, sizeof(int32_t), CACHE_HASH_SIZE, f) != CACHE_HASH_SIZE) {
    goto error;
  }

  if (fwrite(buf, sizeof(unsigned char), buflen, f) != buflen) {
    goto error;
  }

  fclose(f);

  return 0;

 error:
  fclose(f);
  return 1;
}

 
 

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

#ifndef __OPENCL_VERSION__
#define __constant
#endif

__constant static const uint16_t base_table[512] = {
  0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
  0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
  0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
  0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
  0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
  0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
  0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0001, 0x0002, 0x0004, 0x0008, 0x0010, 0x0020, 0x0040, 0x0080, 0x0100,
  0x0200, 0x0400, 0x0800, 0x0C00, 0x1000, 0x1400, 0x1800, 0x1C00, 0x2000, 0x2400, 0x2800, 0x2C00, 0x3000, 0x3400, 0x3800, 0x3C00,
  0x4000, 0x4400, 0x4800, 0x4C00, 0x5000, 0x5400, 0x5800, 0x5C00, 0x6000, 0x6400, 0x6800, 0x6C00, 0x7000, 0x7400, 0x7800, 0x7C00,
  0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00,
  0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00,
  0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00,
  0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00,
  0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00,
  0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00,
  0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00, 0x7C00,
  0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000,
  0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000,
  0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000,
  0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000,
  0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000,
  0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000,
  0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8001, 0x8002, 0x8004, 0x8008, 0x8010, 0x8020, 0x8040, 0x8080, 0x8100,
  0x8200, 0x8400, 0x8800, 0x8C00, 0x9000, 0x9400, 0x9800, 0x9C00, 0xA000, 0xA400, 0xA800, 0xAC00, 0xB000, 0xB400, 0xB800, 0xBC00,
  0xC000, 0xC400, 0xC800, 0xCC00, 0xD000, 0xD400, 0xD800, 0xDC00, 0xE000, 0xE400, 0xE800, 0xEC00, 0xF000, 0xF400, 0xF800, 0xFC00,
  0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00,
  0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00,
  0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00,
  0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00,
  0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00,
  0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00,
  0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00, 0xFC00 };

__constant static const unsigned char shift_table[512] = {
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
  13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 13,
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
  13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
  24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 13 };

__constant static const uint32_t mantissa_table[2048] = {
  0x00000000, 0x33800000, 0x34000000, 0x34400000, 0x34800000, 0x34A00000, 0x34C00000, 0x34E00000, 0x35000000, 0x35100000, 0x35200000, 0x35300000, 0x35400000, 0x35500000, 0x35600000, 0x35700000,
  0x35800000, 0x35880000, 0x35900000, 0x35980000, 0x35A00000, 0x35A80000, 0x35B00000, 0x35B80000, 0x35C00000, 0x35C80000, 0x35D00000, 0x35D80000, 0x35E00000, 0x35E80000, 0x35F00000, 0x35F80000,
  0x36000000, 0x36040000, 0x36080000, 0x360C0000, 0x36100000, 0x36140000, 0x36180000, 0x361C0000, 0x36200000, 0x36240000, 0x36280000, 0x362C0000, 0x36300000, 0x36340000, 0x36380000, 0x363C0000,
  0x36400000, 0x36440000, 0x36480000, 0x364C0000, 0x36500000, 0x36540000, 0x36580000, 0x365C0000, 0x36600000, 0x36640000, 0x36680000, 0x366C0000, 0x36700000, 0x36740000, 0x36780000, 0x367C0000,
  0x36800000, 0x36820000, 0x36840000, 0x36860000, 0x36880000, 0x368A0000, 0x368C0000, 0x368E0000, 0x36900000, 0x36920000, 0x36940000, 0x36960000, 0x36980000, 0x369A0000, 0x369C0000, 0x369E0000,
  0x36A00000, 0x36A20000, 0x36A40000, 0x36A60000, 0x36A80000, 0x36AA0000, 0x36AC0000, 0x36AE0000, 0x36B00000, 0x36B20000, 0x36B40000, 0x36B60000, 0x36B80000, 0x36BA0000, 0x36BC0000, 0x36BE0000,
  0x36C00000, 0x36C20000, 0x36C40000, 0x36C60000, 0x36C80000, 0x36CA0000, 0x36CC0000, 0x36CE0000, 0x36D00000, 0x36D20000, 0x36D40000, 0x36D60000, 0x36D80000, 0x36DA0000, 0x36DC0000, 0x36DE0000,
  0x36E00000, 0x36E20000, 0x36E40000, 0x36E60000, 0x36E80000, 0x36EA0000, 0x36EC0000, 0x36EE0000, 0x36F00000, 0x36F20000, 0x36F40000, 0x36F60000, 0x36F80000, 0x36FA0000, 0x36FC0000, 0x36FE0000,
  0x37000000, 0x37010000, 0x37020000, 0x37030000, 0x37040000, 0x37050000, 0x37060000, 0x37070000, 0x37080000, 0x37090000, 0x370A0000, 0x370B0000, 0x370C0000, 0x370D0000, 0x370E0000, 0x370F0000,
  0x37100000, 0x37110000, 0x37120000, 0x37130000, 0x37140000, 0x37150000, 0x37160000, 0x37170000, 0x37180000, 0x37190000, 0x371A0000, 0x371B0000, 0x371C0000, 0x371D0000, 0x371E0000, 0x371F0000,
  0x37200000, 0x37210000, 0x37220000, 0x37230000, 0x37240000, 0x37250000, 0x37260000, 0x37270000, 0x37280000, 0x37290000, 0x372A0000, 0x372B0000, 0x372C0000, 0x372D0000, 0x372E0000, 0x372F0000,
  0x37300000, 0x37310000, 0x37320000, 0x37330000, 0x37340000, 0x37350000, 0x37360000, 0x37370000, 0x37380000, 0x37390000, 0x373A0000, 0x373B0000, 0x373C0000, 0x373D0000, 0x373E0000, 0x373F0000,
  0x37400000, 0x37410000, 0x37420000, 0x37430000, 0x37440000, 0x37450000, 0x37460000, 0x37470000, 0x37480000, 0x37490000, 0x374A0000, 0x374B0000, 0x374C0000, 0x374D0000, 0x374E0000, 0x374F0000,
  0x37500000, 0x37510000, 0x37520000, 0x37530000, 0x37540000, 0x37550000, 0x37560000, 0x37570000, 0x37580000, 0x37590000, 0x375A0000, 0x375B0000, 0x375C0000, 0x375D0000, 0x375E0000, 0x375F0000,
  0x37600000, 0x37610000, 0x37620000, 0x37630000, 0x37640000, 0x37650000, 0x37660000, 0x37670000, 0x37680000, 0x37690000, 0x376A0000, 0x376B0000, 0x376C0000, 0x376D0000, 0x376E0000, 0x376F0000,
  0x37700000, 0x37710000, 0x37720000, 0x37730000, 0x37740000, 0x37750000, 0x37760000, 0x37770000, 0x37780000, 0x37790000, 0x377A0000, 0x377B0000, 0x377C0000, 0x377D0000, 0x377E0000, 0x377F0000,
  0x37800000, 0x37808000, 0x37810000, 0x37818000, 0x37820000, 0x37828000, 0x37830000, 0x37838000, 0x37840000, 0x37848000, 0x37850000, 0x37858000, 0x37860000, 0x37868000, 0x37870000, 0x37878000,
  0x37880000, 0x37888000, 0x37890000, 0x37898000, 0x378A0000, 0x378A8000, 0x378B0000, 0x378B8000, 0x378C0000, 0x378C8000, 0x378D0000, 0x378D8000, 0x378E0000, 0x378E8000, 0x378F0000, 0x378F8000,
  0x37900000, 0x37908000, 0x37910000, 0x37918000, 0x37920000, 0x37928000, 0x37930000, 0x37938000, 0x37940000, 0x37948000, 0x37950000, 0x37958000, 0x37960000, 0x37968000, 0x37970000, 0x37978000,
  0x37980000, 0x37988000, 0x37990000, 0x37998000, 0x379A0000, 0x379A8000, 0x379B0000, 0x379B8000, 0x379C0000, 0x379C8000, 0x379D0000, 0x379D8000, 0x379E0000, 0x379E8000, 0x379F0000, 0x379F8000,
  0x37A00000, 0x37A08000, 0x37A10000, 0x37A18000, 0x37A20000, 0x37A28000, 0x37A30000, 0x37A38000, 0x37A40000, 0x37A48000, 0x37A50000, 0x37A58000, 0x37A60000, 0x37A68000, 0x37A70000, 0x37A78000,
  0x37A80000, 0x37A88000, 0x37A90000, 0x37A98000, 0x37AA0000, 0x37AA8000, 0x37AB0000, 0x37AB8000, 0x37AC0000, 0x37AC8000, 0x37AD0000, 0x37AD8000, 0x37AE0000, 0x37AE8000, 0x37AF0000, 0x37AF8000,
  0x37B00000, 0x37B08000, 0x37B10000, 0x37B18000, 0x37B20000, 0x37B28000, 0x37B30000, 0x37B38000, 0x37B40000, 0x37B48000, 0x37B50000, 0x37B58000, 0x37B60000, 0x37B68000, 0x37B70000, 0x37B78000,
  0x37B80000, 0x37B88000, 0x37B90000, 0x37B98000, 0x37BA0000, 0x37BA8000, 0x37BB0000, 0x37BB8000, 0x37BC0000, 0x37BC8000, 0x37BD0000, 0x37BD8000, 0x37BE0000, 0x37BE8000, 0x37BF0000, 0x37BF8000,
  0x37C00000, 0x37C08000, 0x37C10000, 0x37C18000, 0x37C20000, 0x37C28000, 0x37C30000, 0x37C38000, 0x37C40000, 0x37C48000, 0x37C50000, 0x37C58000, 0x37C60000, 0x37C68000, 0x37C70000, 0x37C78000,
  0x37C80000, 0x37C88000, 0x37C90000, 0x37C98000, 0x37CA0000, 0x37CA8000, 0x37CB0000, 0x37CB8000, 0x37CC0000, 0x37CC8000, 0x37CD0000, 0x37CD8000, 0x37CE0000, 0x37CE8000, 0x37CF0000, 0x37CF8000,
  0x37D00000, 0x37D08000, 0x37D10000, 0x37D18000, 0x37D20000, 0x37D28000, 0x37D30000, 0x37D38000, 0x37D40000, 0x37D48000, 0x37D50000, 0x37D58000, 0x37D60000, 0x37D68000, 0x37D70000, 0x37D78000,
  0x37D80000, 0x37D88000, 0x37D90000, 0x37D98000, 0x37DA0000, 0x37DA8000, 0x37DB0000, 0x37DB8000, 0x37DC0000, 0x37DC8000, 0x37DD0000, 0x37DD8000, 0x37DE0000, 0x37DE8000, 0x37DF0000, 0x37DF8000,
  0x37E00000, 0x37E08000, 0x37E10000, 0x37E18000, 0x37E20000, 0x37E28000, 0x37E30000, 0x37E38000, 0x37E40000, 0x37E48000, 0x37E50000, 0x37E58000, 0x37E60000, 0x37E68000, 0x37E70000, 0x37E78000,
  0x37E80000, 0x37E88000, 0x37E90000, 0x37E98000, 0x37EA0000, 0x37EA8000, 0x37EB0000, 0x37EB8000, 0x37EC0000, 0x37EC8000, 0x37ED0000, 0x37ED8000, 0x37EE0000, 0x37EE8000, 0x37EF0000, 0x37EF8000,
  0x37F00000, 0x37F08000, 0x37F10000, 0x37F18000, 0x37F20000, 0x37F28000, 0x37F30000, 0x37F38000, 0x37F40000, 0x37F48000, 0x37F50000, 0x37F58000, 0x37F60000, 0x37F68000, 0x37F70000, 0x37F78000,
  0x37F80000, 0x37F88000, 0x37F90000, 0x37F98000, 0x37FA0000, 0x37FA8000, 0x37FB0000, 0x37FB8000, 0x37FC0000, 0x37FC8000, 0x37FD0000, 0x37FD8000, 0x37FE0000, 0x37FE8000, 0x37FF0000, 0x37FF8000,
  0x38000000, 0x38004000, 0x38008000, 0x3800C000, 0x38010000, 0x38014000, 0x38018000, 0x3801C000, 0x38020000, 0x38024000, 0x38028000, 0x3802C000, 0x38030000, 0x38034000, 0x38038000, 0x3803C000,
  0x38040000, 0x38044000, 0x38048000, 0x3804C000, 0x38050000, 0x38054000, 0x38058000, 0x3805C000, 0x38060000, 0x38064000, 0x38068000, 0x3806C000, 0x38070000, 0x38074000, 0x38078000, 0x3807C000,
  0x38080000, 0x38084000, 0x38088000, 0x3808C000, 0x38090000, 0x38094000, 0x38098000, 0x3809C000, 0x380A0000, 0x380A4000, 0x380A8000, 0x380AC000, 0x380B0000, 0x380B4000, 0x380B8000, 0x380BC000,
  0x380C0000, 0x380C4000, 0x380C8000, 0x380CC000, 0x380D0000, 0x380D4000, 0x380D8000, 0x380DC000, 0x380E0000, 0x380E4000, 0x380E8000, 0x380EC000, 0x380F0000, 0x380F4000, 0x380F8000, 0x380FC000,
  0x38100000, 0x38104000, 0x38108000, 0x3810C000, 0x38110000, 0x38114000, 0x38118000, 0x3811C000, 0x38120000, 0x38124000, 0x38128000, 0x3812C000, 0x38130000, 0x38134000, 0x38138000, 0x3813C000,
  0x38140000, 0x38144000, 0x38148000, 0x3814C000, 0x38150000, 0x38154000, 0x38158000, 0x3815C000, 0x38160000, 0x38164000, 0x38168000, 0x3816C000, 0x38170000, 0x38174000, 0x38178000, 0x3817C000,
  0x38180000, 0x38184000, 0x38188000, 0x3818C000, 0x38190000, 0x38194000, 0x38198000, 0x3819C000, 0x381A0000, 0x381A4000, 0x381A8000, 0x381AC000, 0x381B0000, 0x381B4000, 0x381B8000, 0x381BC000,
  0x381C0000, 0x381C4000, 0x381C8000, 0x381CC000, 0x381D0000, 0x381D4000, 0x381D8000, 0x381DC000, 0x381E0000, 0x381E4000, 0x381E8000, 0x381EC000, 0x381F0000, 0x381F4000, 0x381F8000, 0x381FC000,
  0x38200000, 0x38204000, 0x38208000, 0x3820C000, 0x38210000, 0x38214000, 0x38218000, 0x3821C000, 0x38220000, 0x38224000, 0x38228000, 0x3822C000, 0x38230000, 0x38234000, 0x38238000, 0x3823C000,
  0x38240000, 0x38244000, 0x38248000, 0x3824C000, 0x38250000, 0x38254000, 0x38258000, 0x3825C000, 0x38260000, 0x38264000, 0x38268000, 0x3826C000, 0x38270000, 0x38274000, 0x38278000, 0x3827C000,
  0x38280000, 0x38284000, 0x38288000, 0x3828C000, 0x38290000, 0x38294000, 0x38298000, 0x3829C000, 0x382A0000, 0x382A4000, 0x382A8000, 0x382AC000, 0x382B0000, 0x382B4000, 0x382B8000, 0x382BC000,
  0x382C0000, 0x382C4000, 0x382C8000, 0x382CC000, 0x382D0000, 0x382D4000, 0x382D8000, 0x382DC000, 0x382E0000, 0x382E4000, 0x382E8000, 0x382EC000, 0x382F0000, 0x382F4000, 0x382F8000, 0x382FC000,
  0x38300000, 0x38304000, 0x38308000, 0x3830C000, 0x38310000, 0x38314000, 0x38318000, 0x3831C000, 0x38320000, 0x38324000, 0x38328000, 0x3832C000, 0x38330000, 0x38334000, 0x38338000, 0x3833C000,
  0x38340000, 0x38344000, 0x38348000, 0x3834C000, 0x38350000, 0x38354000, 0x38358000, 0x3835C000, 0x38360000, 0x38364000, 0x38368000, 0x3836C000, 0x38370000, 0x38374000, 0x38378000, 0x3837C000,
  0x38380000, 0x38384000, 0x38388000, 0x3838C000, 0x38390000, 0x38394000, 0x38398000, 0x3839C000, 0x383A0000, 0x383A4000, 0x383A8000, 0x383AC000, 0x383B0000, 0x383B4000, 0x383B8000, 0x383BC000,
  0x383C0000, 0x383C4000, 0x383C8000, 0x383CC000, 0x383D0000, 0x383D4000, 0x383D8000, 0x383DC000, 0x383E0000, 0x383E4000, 0x383E8000, 0x383EC000, 0x383F0000, 0x383F4000, 0x383F8000, 0x383FC000,
  0x38400000, 0x38404000, 0x38408000, 0x3840C000, 0x38410000, 0x38414000, 0x38418000, 0x3841C000, 0x38420000, 0x38424000, 0x38428000, 0x3842C000, 0x38430000, 0x38434000, 0x38438000, 0x3843C000,
  0x38440000, 0x38444000, 0x38448000, 0x3844C000, 0x38450000, 0x38454000, 0x38458000, 0x3845C000, 0x38460000, 0x38464000, 0x38468000, 0x3846C000, 0x38470000, 0x38474000, 0x38478000, 0x3847C000,
  0x38480000, 0x38484000, 0x38488000, 0x3848C000, 0x38490000, 0x38494000, 0x38498000, 0x3849C000, 0x384A0000, 0x384A4000, 0x384A8000, 0x384AC000, 0x384B0000, 0x384B4000, 0x384B8000, 0x384BC000,
  0x384C0000, 0x384C4000, 0x384C8000, 0x384CC000, 0x384D0000, 0x384D4000, 0x384D8000, 0x384DC000, 0x384E0000, 0x384E4000, 0x384E8000, 0x384EC000, 0x384F0000, 0x384F4000, 0x384F8000, 0x384FC000,
  0x38500000, 0x38504000, 0x38508000, 0x3850C000, 0x38510000, 0x38514000, 0x38518000, 0x3851C000, 0x38520000, 0x38524000, 0x38528000, 0x3852C000, 0x38530000, 0x38534000, 0x38538000, 0x3853C000,
  0x38540000, 0x38544000, 0x38548000, 0x3854C000, 0x38550000, 0x38554000, 0x38558000, 0x3855C000, 0x38560000, 0x38564000, 0x38568000, 0x3856C000, 0x38570000, 0x38574000, 0x38578000, 0x3857C000,
  0x38580000, 0x38584000, 0x38588000, 0x3858C000, 0x38590000, 0x38594000, 0x38598000, 0x3859C000, 0x385A0000, 0x385A4000, 0x385A8000, 0x385AC000, 0x385B0000, 0x385B4000, 0x385B8000, 0x385BC000,
  0x385C0000, 0x385C4000, 0x385C8000, 0x385CC000, 0x385D0000, 0x385D4000, 0x385D8000, 0x385DC000, 0x385E0000, 0x385E4000, 0x385E8000, 0x385EC000, 0x385F0000, 0x385F4000, 0x385F8000, 0x385FC000,
  0x38600000, 0x38604000, 0x38608000, 0x3860C000, 0x38610000, 0x38614000, 0x38618000, 0x3861C000, 0x38620000, 0x38624000, 0x38628000, 0x3862C000, 0x38630000, 0x38634000, 0x38638000, 0x3863C000,
  0x38640000, 0x38644000, 0x38648000, 0x3864C000, 0x38650000, 0x38654000, 0x38658000, 0x3865C000, 0x38660000, 0x38664000, 0x38668000, 0x3866C000, 0x38670000, 0x38674000, 0x38678000, 0x3867C000,
  0x38680000, 0x38684000, 0x38688000, 0x3868C000, 0x38690000, 0x38694000, 0x38698000, 0x3869C000, 0x386A0000, 0x386A4000, 0x386A8000, 0x386AC000, 0x386B0000, 0x386B4000, 0x386B8000, 0x386BC000,
  0x386C0000, 0x386C4000, 0x386C8000, 0x386CC000, 0x386D0000, 0x386D4000, 0x386D8000, 0x386DC000, 0x386E0000, 0x386E4000, 0x386E8000, 0x386EC000, 0x386F0000, 0x386F4000, 0x386F8000, 0x386FC000,
  0x38700000, 0x38704000, 0x38708000, 0x3870C000, 0x38710000, 0x38714000, 0x38718000, 0x3871C000, 0x38720000, 0x38724000, 0x38728000, 0x3872C000, 0x38730000, 0x38734000, 0x38738000, 0x3873C000,
  0x38740000, 0x38744000, 0x38748000, 0x3874C000, 0x38750000, 0x38754000, 0x38758000, 0x3875C000, 0x38760000, 0x38764000, 0x38768000, 0x3876C000, 0x38770000, 0x38774000, 0x38778000, 0x3877C000,
  0x38780000, 0x38784000, 0x38788000, 0x3878C000, 0x38790000, 0x38794000, 0x38798000, 0x3879C000, 0x387A0000, 0x387A4000, 0x387A8000, 0x387AC000, 0x387B0000, 0x387B4000, 0x387B8000, 0x387BC000,
  0x387C0000, 0x387C4000, 0x387C8000, 0x387CC000, 0x387D0000, 0x387D4000, 0x387D8000, 0x387DC000, 0x387E0000, 0x387E4000, 0x387E8000, 0x387EC000, 0x387F0000, 0x387F4000, 0x387F8000, 0x387FC000,
  0x38000000, 0x38002000, 0x38004000, 0x38006000, 0x38008000, 0x3800A000, 0x3800C000, 0x3800E000, 0x38010000, 0x38012000, 0x38014000, 0x38016000, 0x38018000, 0x3801A000, 0x3801C000, 0x3801E000,
  0x38020000, 0x38022000, 0x38024000, 0x38026000, 0x38028000, 0x3802A000, 0x3802C000, 0x3802E000, 0x38030000, 0x38032000, 0x38034000, 0x38036000, 0x38038000, 0x3803A000, 0x3803C000, 0x3803E000,
  0x38040000, 0x38042000, 0x38044000, 0x38046000, 0x38048000, 0x3804A000, 0x3804C000, 0x3804E000, 0x38050000, 0x38052000, 0x38054000, 0x38056000, 0x38058000, 0x3805A000, 0x3805C000, 0x3805E000,
  0x38060000, 0x38062000, 0x38064000, 0x38066000, 0x38068000, 0x3806A000, 0x3806C000, 0x3806E000, 0x38070000, 0x38072000, 0x38074000, 0x38076000, 0x38078000, 0x3807A000, 0x3807C000, 0x3807E000,
  0x38080000, 0x38082000, 0x38084000, 0x38086000, 0x38088000, 0x3808A000, 0x3808C000, 0x3808E000, 0x38090000, 0x38092000, 0x38094000, 0x38096000, 0x38098000, 0x3809A000, 0x3809C000, 0x3809E000,
  0x380A0000, 0x380A2000, 0x380A4000, 0x380A6000, 0x380A8000, 0x380AA000, 0x380AC000, 0x380AE000, 0x380B0000, 0x380B2000, 0x380B4000, 0x380B6000, 0x380B8000, 0x380BA000, 0x380BC000, 0x380BE000,
  0x380C0000, 0x380C2000, 0x380C4000, 0x380C6000, 0x380C8000, 0x380CA000, 0x380CC000, 0x380CE000, 0x380D0000, 0x380D2000, 0x380D4000, 0x380D6000, 0x380D8000, 0x380DA000, 0x380DC000, 0x380DE000,
  0x380E0000, 0x380E2000, 0x380E4000, 0x380E6000, 0x380E8000, 0x380EA000, 0x380EC000, 0x380EE000, 0x380F0000, 0x380F2000, 0x380F4000, 0x380F6000, 0x380F8000, 0x380FA000, 0x380FC000, 0x380FE000,
  0x38100000, 0x38102000, 0x38104000, 0x38106000, 0x38108000, 0x3810A000, 0x3810C000, 0x3810E000, 0x38110000, 0x38112000, 0x38114000, 0x38116000, 0x38118000, 0x3811A000, 0x3811C000, 0x3811E000,
  0x38120000, 0x38122000, 0x38124000, 0x38126000, 0x38128000, 0x3812A000, 0x3812C000, 0x3812E000, 0x38130000, 0x38132000, 0x38134000, 0x38136000, 0x38138000, 0x3813A000, 0x3813C000, 0x3813E000,
  0x38140000, 0x38142000, 0x38144000, 0x38146000, 0x38148000, 0x3814A000, 0x3814C000, 0x3814E000, 0x38150000, 0x38152000, 0x38154000, 0x38156000, 0x38158000, 0x3815A000, 0x3815C000, 0x3815E000,
  0x38160000, 0x38162000, 0x38164000, 0x38166000, 0x38168000, 0x3816A000, 0x3816C000, 0x3816E000, 0x38170000, 0x38172000, 0x38174000, 0x38176000, 0x38178000, 0x3817A000, 0x3817C000, 0x3817E000,
  0x38180000, 0x38182000, 0x38184000, 0x38186000, 0x38188000, 0x3818A000, 0x3818C000, 0x3818E000, 0x38190000, 0x38192000, 0x38194000, 0x38196000, 0x38198000, 0x3819A000, 0x3819C000, 0x3819E000,
  0x381A0000, 0x381A2000, 0x381A4000, 0x381A6000, 0x381A8000, 0x381AA000, 0x381AC000, 0x381AE000, 0x381B0000, 0x381B2000, 0x381B4000, 0x381B6000, 0x381B8000, 0x381BA000, 0x381BC000, 0x381BE000,
  0x381C0000, 0x381C2000, 0x381C4000, 0x381C6000, 0x381C8000, 0x381CA000, 0x381CC000, 0x381CE000, 0x381D0000, 0x381D2000, 0x381D4000, 0x381D6000, 0x381D8000, 0x381DA000, 0x381DC000, 0x381DE000,
  0x381E0000, 0x381E2000, 0x381E4000, 0x381E6000, 0x381E8000, 0x381EA000, 0x381EC000, 0x381EE000, 0x381F0000, 0x381F2000, 0x381F4000, 0x381F6000, 0x381F8000, 0x381FA000, 0x381FC000, 0x381FE000,
  0x38200000, 0x38202000, 0x38204000, 0x38206000, 0x38208000, 0x3820A000, 0x3820C000, 0x3820E000, 0x38210000, 0x38212000, 0x38214000, 0x38216000, 0x38218000, 0x3821A000, 0x3821C000, 0x3821E000,
  0x38220000, 0x38222000, 0x38224000, 0x38226000, 0x38228000, 0x3822A000, 0x3822C000, 0x3822E000, 0x38230000, 0x38232000, 0x38234000, 0x38236000, 0x38238000, 0x3823A000, 0x3823C000, 0x3823E000,
  0x38240000, 0x38242000, 0x38244000, 0x38246000, 0x38248000, 0x3824A000, 0x3824C000, 0x3824E000, 0x38250000, 0x38252000, 0x38254000, 0x38256000, 0x38258000, 0x3825A000, 0x3825C000, 0x3825E000,
  0x38260000, 0x38262000, 0x38264000, 0x38266000, 0x38268000, 0x3826A000, 0x3826C000, 0x3826E000, 0x38270000, 0x38272000, 0x38274000, 0x38276000, 0x38278000, 0x3827A000, 0x3827C000, 0x3827E000,
  0x38280000, 0x38282000, 0x38284000, 0x38286000, 0x38288000, 0x3828A000, 0x3828C000, 0x3828E000, 0x38290000, 0x38292000, 0x38294000, 0x38296000, 0x38298000, 0x3829A000, 0x3829C000, 0x3829E000,
  0x382A0000, 0x382A2000, 0x382A4000, 0x382A6000, 0x382A8000, 0x382AA000, 0x382AC000, 0x382AE000, 0x382B0000, 0x382B2000, 0x382B4000, 0x382B6000, 0x382B8000, 0x382BA000, 0x382BC000, 0x382BE000,
  0x382C0000, 0x382C2000, 0x382C4000, 0x382C6000, 0x382C8000, 0x382CA000, 0x382CC000, 0x382CE000, 0x382D0000, 0x382D2000, 0x382D4000, 0x382D6000, 0x382D8000, 0x382DA000, 0x382DC000, 0x382DE000,
  0x382E0000, 0x382E2000, 0x382E4000, 0x382E6000, 0x382E8000, 0x382EA000, 0x382EC000, 0x382EE000, 0x382F0000, 0x382F2000, 0x382F4000, 0x382F6000, 0x382F8000, 0x382FA000, 0x382FC000, 0x382FE000,
  0x38300000, 0x38302000, 0x38304000, 0x38306000, 0x38308000, 0x3830A000, 0x3830C000, 0x3830E000, 0x38310000, 0x38312000, 0x38314000, 0x38316000, 0x38318000, 0x3831A000, 0x3831C000, 0x3831E000,
  0x38320000, 0x38322000, 0x38324000, 0x38326000, 0x38328000, 0x3832A000, 0x3832C000, 0x3832E000, 0x38330000, 0x38332000, 0x38334000, 0x38336000, 0x38338000, 0x3833A000, 0x3833C000, 0x3833E000,
  0x38340000, 0x38342000, 0x38344000, 0x38346000, 0x38348000, 0x3834A000, 0x3834C000, 0x3834E000, 0x38350000, 0x38352000, 0x38354000, 0x38356000, 0x38358000, 0x3835A000, 0x3835C000, 0x3835E000,
  0x38360000, 0x38362000, 0x38364000, 0x38366000, 0x38368000, 0x3836A000, 0x3836C000, 0x3836E000, 0x38370000, 0x38372000, 0x38374000, 0x38376000, 0x38378000, 0x3837A000, 0x3837C000, 0x3837E000,
  0x38380000, 0x38382000, 0x38384000, 0x38386000, 0x38388000, 0x3838A000, 0x3838C000, 0x3838E000, 0x38390000, 0x38392000, 0x38394000, 0x38396000, 0x38398000, 0x3839A000, 0x3839C000, 0x3839E000,
  0x383A0000, 0x383A2000, 0x383A4000, 0x383A6000, 0x383A8000, 0x383AA000, 0x383AC000, 0x383AE000, 0x383B0000, 0x383B2000, 0x383B4000, 0x383B6000, 0x383B8000, 0x383BA000, 0x383BC000, 0x383BE000,
  0x383C0000, 0x383C2000, 0x383C4000, 0x383C6000, 0x383C8000, 0x383CA000, 0x383CC000, 0x383CE000, 0x383D0000, 0x383D2000, 0x383D4000, 0x383D6000, 0x383D8000, 0x383DA000, 0x383DC000, 0x383DE000,
  0x383E0000, 0x383E2000, 0x383E4000, 0x383E6000, 0x383E8000, 0x383EA000, 0x383EC000, 0x383EE000, 0x383F0000, 0x383F2000, 0x383F4000, 0x383F6000, 0x383F8000, 0x383FA000, 0x383FC000, 0x383FE000,
  0x38400000, 0x38402000, 0x38404000, 0x38406000, 0x38408000, 0x3840A000, 0x3840C000, 0x3840E000, 0x38410000, 0x38412000, 0x38414000, 0x38416000, 0x38418000, 0x3841A000, 0x3841C000, 0x3841E000,
  0x38420000, 0x38422000, 0x38424000, 0x38426000, 0x38428000, 0x3842A000, 0x3842C000, 0x3842E000, 0x38430000, 0x38432000, 0x38434000, 0x38436000, 0x38438000, 0x3843A000, 0x3843C000, 0x3843E000,
  0x38440000, 0x38442000, 0x38444000, 0x38446000, 0x38448000, 0x3844A000, 0x3844C000, 0x3844E000, 0x38450000, 0x38452000, 0x38454000, 0x38456000, 0x38458000, 0x3845A000, 0x3845C000, 0x3845E000,
  0x38460000, 0x38462000, 0x38464000, 0x38466000, 0x38468000, 0x3846A000, 0x3846C000, 0x3846E000, 0x38470000, 0x38472000, 0x38474000, 0x38476000, 0x38478000, 0x3847A000, 0x3847C000, 0x3847E000,
  0x38480000, 0x38482000, 0x38484000, 0x38486000, 0x38488000, 0x3848A000, 0x3848C000, 0x3848E000, 0x38490000, 0x38492000, 0x38494000, 0x38496000, 0x38498000, 0x3849A000, 0x3849C000, 0x3849E000,
  0x384A0000, 0x384A2000, 0x384A4000, 0x384A6000, 0x384A8000, 0x384AA000, 0x384AC000, 0x384AE000, 0x384B0000, 0x384B2000, 0x384B4000, 0x384B6000, 0x384B8000, 0x384BA000, 0x384BC000, 0x384BE000,
  0x384C0000, 0x384C2000, 0x384C4000, 0x384C6000, 0x384C8000, 0x384CA000, 0x384CC000, 0x384CE000, 0x384D0000, 0x384D2000, 0x384D4000, 0x384D6000, 0x384D8000, 0x384DA000, 0x384DC000, 0x384DE000,
  0x384E0000, 0x384E2000, 0x384E4000, 0x384E6000, 0x384E8000, 0x384EA000, 0x384EC000, 0x384EE000, 0x384F0000, 0x384F2000, 0x384F4000, 0x384F6000, 0x384F8000, 0x384FA000, 0x384FC000, 0x384FE000,
  0x38500000, 0x38502000, 0x38504000, 0x38506000, 0x38508000, 0x3850A000, 0x3850C000, 0x3850E000, 0x38510000, 0x38512000, 0x38514000, 0x38516000, 0x38518000, 0x3851A000, 0x3851C000, 0x3851E000,
  0x38520000, 0x38522000, 0x38524000, 0x38526000, 0x38528000, 0x3852A000, 0x3852C000, 0x3852E000, 0x38530000, 0x38532000, 0x38534000, 0x38536000, 0x38538000, 0x3853A000, 0x3853C000, 0x3853E000,
  0x38540000, 0x38542000, 0x38544000, 0x38546000, 0x38548000, 0x3854A000, 0x3854C000, 0x3854E000, 0x38550000, 0x38552000, 0x38554000, 0x38556000, 0x38558000, 0x3855A000, 0x3855C000, 0x3855E000,
  0x38560000, 0x38562000, 0x38564000, 0x38566000, 0x38568000, 0x3856A000, 0x3856C000, 0x3856E000, 0x38570000, 0x38572000, 0x38574000, 0x38576000, 0x38578000, 0x3857A000, 0x3857C000, 0x3857E000,
  0x38580000, 0x38582000, 0x38584000, 0x38586000, 0x38588000, 0x3858A000, 0x3858C000, 0x3858E000, 0x38590000, 0x38592000, 0x38594000, 0x38596000, 0x38598000, 0x3859A000, 0x3859C000, 0x3859E000,
  0x385A0000, 0x385A2000, 0x385A4000, 0x385A6000, 0x385A8000, 0x385AA000, 0x385AC000, 0x385AE000, 0x385B0000, 0x385B2000, 0x385B4000, 0x385B6000, 0x385B8000, 0x385BA000, 0x385BC000, 0x385BE000,
  0x385C0000, 0x385C2000, 0x385C4000, 0x385C6000, 0x385C8000, 0x385CA000, 0x385CC000, 0x385CE000, 0x385D0000, 0x385D2000, 0x385D4000, 0x385D6000, 0x385D8000, 0x385DA000, 0x385DC000, 0x385DE000,
  0x385E0000, 0x385E2000, 0x385E4000, 0x385E6000, 0x385E8000, 0x385EA000, 0x385EC000, 0x385EE000, 0x385F0000, 0x385F2000, 0x385F4000, 0x385F6000, 0x385F8000, 0x385FA000, 0x385FC000, 0x385FE000,
  0x38600000, 0x38602000, 0x38604000, 0x38606000, 0x38608000, 0x3860A000, 0x3860C000, 0x3860E000, 0x38610000, 0x38612000, 0x38614000, 0x38616000, 0x38618000, 0x3861A000, 0x3861C000, 0x3861E000,
  0x38620000, 0x38622000, 0x38624000, 0x38626000, 0x38628000, 0x3862A000, 0x3862C000, 0x3862E000, 0x38630000, 0x38632000, 0x38634000, 0x38636000, 0x38638000, 0x3863A000, 0x3863C000, 0x3863E000,
  0x38640000, 0x38642000, 0x38644000, 0x38646000, 0x38648000, 0x3864A000, 0x3864C000, 0x3864E000, 0x38650000, 0x38652000, 0x38654000, 0x38656000, 0x38658000, 0x3865A000, 0x3865C000, 0x3865E000,
  0x38660000, 0x38662000, 0x38664000, 0x38666000, 0x38668000, 0x3866A000, 0x3866C000, 0x3866E000, 0x38670000, 0x38672000, 0x38674000, 0x38676000, 0x38678000, 0x3867A000, 0x3867C000, 0x3867E000,
  0x38680000, 0x38682000, 0x38684000, 0x38686000, 0x38688000, 0x3868A000, 0x3868C000, 0x3868E000, 0x38690000, 0x38692000, 0x38694000, 0x38696000, 0x38698000, 0x3869A000, 0x3869C000, 0x3869E000,
  0x386A0000, 0x386A2000, 0x386A4000, 0x386A6000, 0x386A8000, 0x386AA000, 0x386AC000, 0x386AE000, 0x386B0000, 0x386B2000, 0x386B4000, 0x386B6000, 0x386B8000, 0x386BA000, 0x386BC000, 0x386BE000,
  0x386C0000, 0x386C2000, 0x386C4000, 0x386C6000, 0x386C8000, 0x386CA000, 0x386CC000, 0x386CE000, 0x386D0000, 0x386D2000, 0x386D4000, 0x386D6000, 0x386D8000, 0x386DA000, 0x386DC000, 0x386DE000,
  0x386E0000, 0x386E2000, 0x386E4000, 0x386E6000, 0x386E8000, 0x386EA000, 0x386EC000, 0x386EE000, 0x386F0000, 0x386F2000, 0x386F4000, 0x386F6000, 0x386F8000, 0x386FA000, 0x386FC000, 0x386FE000,
  0x38700000, 0x38702000, 0x38704000, 0x38706000, 0x38708000, 0x3870A000, 0x3870C000, 0x3870E000, 0x38710000, 0x38712000, 0x38714000, 0x38716000, 0x38718000, 0x3871A000, 0x3871C000, 0x3871E000,
  0x38720000, 0x38722000, 0x38724000, 0x38726000, 0x38728000, 0x3872A000, 0x3872C000, 0x3872E000, 0x38730000, 0x38732000, 0x38734000, 0x38736000, 0x38738000, 0x3873A000, 0x3873C000, 0x3873E000,
  0x38740000, 0x38742000, 0x38744000, 0x38746000, 0x38748000, 0x3874A000, 0x3874C000, 0x3874E000, 0x38750000, 0x38752000, 0x38754000, 0x38756000, 0x38758000, 0x3875A000, 0x3875C000, 0x3875E000,
  0x38760000, 0x38762000, 0x38764000, 0x38766000, 0x38768000, 0x3876A000, 0x3876C000, 0x3876E000, 0x38770000, 0x38772000, 0x38774000, 0x38776000, 0x38778000, 0x3877A000, 0x3877C000, 0x3877E000,
  0x38780000, 0x38782000, 0x38784000, 0x38786000, 0x38788000, 0x3878A000, 0x3878C000, 0x3878E000, 0x38790000, 0x38792000, 0x38794000, 0x38796000, 0x38798000, 0x3879A000, 0x3879C000, 0x3879E000,
  0x387A0000, 0x387A2000, 0x387A4000, 0x387A6000, 0x387A8000, 0x387AA000, 0x387AC000, 0x387AE000, 0x387B0000, 0x387B2000, 0x387B4000, 0x387B6000, 0x387B8000, 0x387BA000, 0x387BC000, 0x387BE000,
  0x387C0000, 0x387C2000, 0x387C4000, 0x387C6000, 0x387C8000, 0x387CA000, 0x387CC000, 0x387CE000, 0x387D0000, 0x387D2000, 0x387D4000, 0x387D6000, 0x387D8000, 0x387DA000, 0x387DC000, 0x387DE000,
  0x387E0000, 0x387E2000, 0x387E4000, 0x387E6000, 0x387E8000, 0x387EA000, 0x387EC000, 0x387EE000, 0x387F0000, 0x387F2000, 0x387F4000, 0x387F6000, 0x387F8000, 0x387FA000, 0x387FC000, 0x387FE000 };
__constant static const uint32_t exponent_table[64] = {
  0x00000000, 0x00800000, 0x01000000, 0x01800000, 0x02000000, 0x02800000, 0x03000000, 0x03800000, 0x04000000, 0x04800000, 0x05000000, 0x05800000, 0x06000000, 0x06800000, 0x07000000, 0x07800000,
  0x08000000, 0x08800000, 0x09000000, 0x09800000, 0x0A000000, 0x0A800000, 0x0B000000, 0x0B800000, 0x0C000000, 0x0C800000, 0x0D000000, 0x0D800000, 0x0E000000, 0x0E800000, 0x0F000000, 0x47800000,
  0x80000000, 0x80800000, 0x81000000, 0x81800000, 0x82000000, 0x82800000, 0x83000000, 0x83800000, 0x84000000, 0x84800000, 0x85000000, 0x85800000, 0x86000000, 0x86800000, 0x87000000, 0x87800000,
  0x88000000, 0x88800000, 0x89000000, 0x89800000, 0x8A000000, 0x8A800000, 0x8B000000, 0x8B800000, 0x8C000000, 0x8C800000, 0x8D000000, 0x8D800000, 0x8E000000, 0x8E800000, 0x8F000000, 0xC7800000 };
__constant static const unsigned short offset_table[64] = {
  0, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024,
  0, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024, 1024 };

SCALAR_FUN_ATTR uint16_t float2halfbits(float value) {
  union { float x; uint32_t y; } u;
  u.x = value;
  uint32_t bits = u.y;

  uint16_t hbits = base_table[bits>>23] + (uint16_t)((bits&0x7FFFFF)>>shift_table[bits>>23]);;

  return hbits;
}

SCALAR_FUN_ATTR float halfbits2float(uint16_t value) {
  uint32_t bits = mantissa_table[offset_table[value>>10]+(value&0x3FF)] + exponent_table[value>>10];

  union { uint32_t x; float y; } u;
  u.x = bits;
  return u.y;
}

SCALAR_FUN_ATTR uint16_t halfbitsnextafter(uint16_t from, uint16_t to) {
  int fabs = from & 0x7FFF, tabs = to & 0x7FFF;
  if(fabs > 0x7C00 || tabs > 0x7C00) {
    return ((from&0x7FFF)>0x7C00) ? (from|0x200) : (to|0x200);
  }
  if(from == to || !(fabs|tabs)) {
    return to;
  }
  if(!fabs) {
    return (to&0x8000)+1;
  }
  unsigned int out =
    from +
    (((from>>15)^(unsigned int)((from^(0x8000|(0x8000-(from>>15))))<(to^(0x8000|(0x8000-(to>>15))))))<<1)
    - 1;
  return out;
}

 
 

 
 

#ifdef _WIN32

#include <windows.h>

static int64_t get_wall_time(void) {
  LARGE_INTEGER time,freq;
  assert(QueryPerformanceFrequency(&freq));
  assert(QueryPerformanceCounter(&time));
  return ((double)time.QuadPart / freq.QuadPart) * 1000000;
}

static int64_t get_wall_time_ns(void) {
  return get_wall_time() * 1000;
}

#else
 

#include <time.h>
#include <sys/time.h>

static int64_t get_wall_time_ns(void) {
  struct timespec time;
  assert(clock_gettime(CLOCK_MONOTONIC, &time) == 0);
  return time.tv_sec * 1000000000 + time.tv_nsec;
}

static int64_t get_wall_time(void) {
  return get_wall_time_ns() / 1000;
}


#endif

 
 

 
 
 
 
 
 

#ifdef _WIN32

typedef HANDLE lock_t;

static void create_lock(lock_t *lock) {
  *lock = CreateMutex(NULL,   
                      FALSE,  
                      NULL);  
}

static void lock_lock(lock_t *lock) {
  assert(WaitForSingleObject(*lock, INFINITE) == WAIT_OBJECT_0);
}

static void lock_unlock(lock_t *lock) {
  assert(ReleaseMutex(*lock));
}

static void free_lock(lock_t *lock) {
  CloseHandle(*lock);
}

#else
 

#include <pthread.h>

typedef pthread_mutex_t lock_t;

static void create_lock(lock_t *lock) {
  int r = pthread_mutex_init(lock, NULL);
  assert(r == 0);
}

static void lock_lock(lock_t *lock) {
  int r = pthread_mutex_lock(lock);
  assert(r == 0);
}

static void lock_unlock(lock_t *lock) {
  int r = pthread_mutex_unlock(lock);
  assert(r == 0);
}

static void free_lock(lock_t *lock) {
   
  (void)lock;
}

#endif

 
 

typedef uintptr_t fl_mem;

 
 
 
struct free_list_entry {
  size_t size;
  fl_mem mem;
  const char *tag;
  unsigned char valid;
};

struct free_list {
  struct free_list_entry *entries;  
  int capacity;                     
  int used;                         
  lock_t lock;                      
};

static void free_list_init(struct free_list *l) {
  l->capacity = 30;  
  l->used = 0;
  l->entries = (struct free_list_entry*) malloc(sizeof(struct free_list_entry) * l->capacity);
  for (int i = 0; i < l->capacity; i++) {
    l->entries[i].valid = 0;
  }
  create_lock(&l->lock);
}

 
static void free_list_pack(struct free_list *l) {
  lock_lock(&l->lock);
  int p = 0;
  for (int i = 0; i < l->capacity; i++) {
    if (l->entries[i].valid) {
      l->entries[p] = l->entries[i];
      if (i > p) {
        l->entries[i].valid = 0;
      }
      p++;
    }
  }

   
   
   
  if (p < 30) {
    p = 30;
  }
  l->entries = realloc(l->entries, p * sizeof(struct free_list_entry));
  l->capacity = p;
  lock_unlock(&l->lock);
}

static void free_list_destroy(struct free_list *l) {
  assert(l->used == 0);
  free(l->entries);
  free_lock(&l->lock);
}

 
static int free_list_find_invalid(struct free_list *l) {
  int i;
  for (i = 0; i < l->capacity; i++) {
    if (!l->entries[i].valid) {
      break;
    }
  }
  return i;
}

static void free_list_insert(struct free_list *l, size_t size, fl_mem mem, const char *tag) {
  lock_lock(&l->lock);
  int i = free_list_find_invalid(l);

  if (i == l->capacity) {
     
    int new_capacity = l->capacity * 2 * sizeof(struct free_list_entry);
    l->entries = realloc(l->entries, new_capacity);
    for (int j = 0; j < l->capacity; j++) {
      l->entries[j+l->capacity].valid = 0;
    }
    l->capacity *= 2;
  }

   
  l->entries[i].valid = 1;
  l->entries[i].size = size;
  l->entries[i].mem = mem;
  l->entries[i].tag = tag;

  l->used++;
  lock_unlock(&l->lock);
}

 
 
static bool free_list_acceptable(size_t size, const char* tag, struct free_list_entry *entry) {
   
   
   
   

  if (!entry->valid) {
    return false;
  }

  if (size > entry->size) {
    return false;
  }

   
   
   
   
   
   
   
   
   

  if (entry->size < 4096) {
    return true;
  }

  if (entry->tag == tag) {
    return true;
  }

  if (entry->size < size * 2) {
    return true;
  }

  return false;
}

 
 
 
static int free_list_find(struct free_list *l, size_t size, const char *tag,
                          size_t *size_out, fl_mem *mem_out) {
  lock_lock(&l->lock);
  int size_match = -1;
  int i;
  int ret = 1;
  for (i = 0; i < l->capacity; i++) {
    if (free_list_acceptable(size, tag, &l->entries[i]) &&
        (size_match < 0 || l->entries[i].size < l->entries[size_match].size)) {
       
       
      size_match = i;
    }
  }

  if (size_match >= 0) {
    l->entries[size_match].valid = 0;
    *size_out = l->entries[size_match].size;
    *mem_out = l->entries[size_match].mem;
    l->used--;
    ret = 0;
  }
  lock_unlock(&l->lock);
  return ret;
}

 
 
static int free_list_first(struct free_list *l, fl_mem *mem_out) {
  lock_lock(&l->lock);
  int ret = 1;
  for (int i = 0; i < l->capacity; i++) {
    if (l->entries[i].valid) {
      l->entries[i].valid = 0;
      *mem_out = l->entries[i].mem;
      l->used--;
      ret = 0;
      break;
    }
  }
  lock_unlock(&l->lock);
  return ret;
}

 
 

typedef int (*event_report_fn)(struct str_builder*, void*);

struct event {
  void* data;
  event_report_fn f;
  const char* name;
  char *description;
};

struct event_list {
  struct event *events;
  int num_events;
  int capacity;
};

static void event_list_init(struct event_list *l) {
  l->capacity = 100;
  l->num_events = 0;
  l->events = calloc(l->capacity, sizeof(struct event));
}

static void event_list_free(struct event_list *l) {
  free(l->events);
}

static void add_event_to_list(struct event_list *l,
                              const char* name,
                              char* description,
                              void* data,
                              event_report_fn f) {
  if (l->num_events == l->capacity) {
    l->capacity *= 2;
    l->events = realloc(l->events, l->capacity * sizeof(struct event));
  }
  l->events[l->num_events].name = name;
  l->events[l->num_events].description = description;
  l->events[l->num_events].data = data;
  l->events[l->num_events].f = f;
  l->num_events++;
}

static int report_events_in_list(struct event_list *l,
                                 struct str_builder* sb) {
  int ret = 0;
  for (int i = 0; i < l->num_events; i++) {
    if (i != 0) {
      str_builder_str(sb, ",");
    }
    str_builder_str(sb, "{\"name\":");
    str_builder_json_str(sb, l->events[i].name);
    str_builder_str(sb, ",\"description\":");
    str_builder_json_str(sb, l->events[i].description);
    free(l->events[i].description);
    if (l->events[i].f(sb, l->events[i].data) != 0) {
      ret = 1;
      break;
    }
    str_builder(sb, "}");
  }
  event_list_free(l);
  event_list_init(l);
  return ret;
}

 

#ifdef _MSC_VER
#define inline __inline
#endif
#include <string.h>
#include <string.h>
#include <errno.h>
#include <assert.h>
#include <ctype.h>



#define FUTHARK_F64_ENABLED

 

 
 
 
 
 
 

 
 
 
 
 
 

 
 

SCALAR_FUN_ATTR int32_t futrts_to_bits32(float x);
SCALAR_FUN_ATTR float futrts_from_bits32(int32_t x);

SCALAR_FUN_ATTR uint8_t add8(uint8_t x, uint8_t y) {
  return x + y;
}

SCALAR_FUN_ATTR uint16_t add16(uint16_t x, uint16_t y) {
  return x + y;
}

SCALAR_FUN_ATTR uint32_t add32(uint32_t x, uint32_t y) {
  return x + y;
}

SCALAR_FUN_ATTR uint64_t add64(uint64_t x, uint64_t y) {
  return x + y;
}

SCALAR_FUN_ATTR uint8_t sub8(uint8_t x, uint8_t y) {
  return x - y;
}

SCALAR_FUN_ATTR uint16_t sub16(uint16_t x, uint16_t y) {
  return x - y;
}

SCALAR_FUN_ATTR uint32_t sub32(uint32_t x, uint32_t y) {
  return x - y;
}

SCALAR_FUN_ATTR uint64_t sub64(uint64_t x, uint64_t y) {
  return x - y;
}

SCALAR_FUN_ATTR uint8_t mul8(uint8_t x, uint8_t y) {
  return x * y;
}

SCALAR_FUN_ATTR uint16_t mul16(uint16_t x, uint16_t y) {
  return x * y;
}

SCALAR_FUN_ATTR uint32_t mul32(uint32_t x, uint32_t y) {
  return x * y;
}

SCALAR_FUN_ATTR uint64_t mul64(uint64_t x, uint64_t y) {
  return x * y;
}

#if defined(ISPC)

SCALAR_FUN_ATTR uint8_t udiv8(uint8_t x, uint8_t y) {
   
   
   
   
  uint8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x / ys;
}

SCALAR_FUN_ATTR uint16_t udiv16(uint16_t x, uint16_t y) {
  uint16_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x / ys;
}

SCALAR_FUN_ATTR uint32_t udiv32(uint32_t x, uint32_t y) {
  uint32_t ys = 1;
  foreach_active(i){
    ys = y;
  }


  return x / ys;
}

SCALAR_FUN_ATTR uint64_t udiv64(uint64_t x, uint64_t y) {
  uint64_t ys = 1;
  foreach_active(i){
    ys = y;
  }


  return x / ys;
}

SCALAR_FUN_ATTR uint8_t udiv_up8(uint8_t x, uint8_t y) {
  uint8_t ys = 1;
  foreach_active(i){
    ys = y;
  }


  return (x + y - 1) / ys;
}

SCALAR_FUN_ATTR uint16_t udiv_up16(uint16_t x, uint16_t y) {
  uint16_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return (x + y - 1) / ys;
}

SCALAR_FUN_ATTR uint32_t udiv_up32(uint32_t x, uint32_t y) {
  uint32_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return (x + y - 1) / ys;
}

SCALAR_FUN_ATTR uint64_t udiv_up64(uint64_t x, uint64_t y) {
  uint64_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return (x + y - 1) / ys;
}

SCALAR_FUN_ATTR uint8_t umod8(uint8_t x, uint8_t y) {
  uint8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x % ys;
}

SCALAR_FUN_ATTR uint16_t umod16(uint16_t x, uint16_t y) {
  uint16_t ys = 1;
  foreach_active(i){
    ys = y;
  }


  return x % ys;
}

SCALAR_FUN_ATTR uint32_t umod32(uint32_t x, uint32_t y) {
  uint32_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x % ys;
}

SCALAR_FUN_ATTR uint64_t umod64(uint64_t x, uint64_t y) {
  uint64_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x % ys;
}

SCALAR_FUN_ATTR uint8_t udiv_safe8(uint8_t x, uint8_t y) {
  uint8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x / ys;
}

SCALAR_FUN_ATTR uint16_t udiv_safe16(uint16_t x, uint16_t y) {
  uint16_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x / ys;
}

SCALAR_FUN_ATTR uint32_t udiv_safe32(uint32_t x, uint32_t y) {
  uint32_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x / ys;
}

SCALAR_FUN_ATTR uint64_t udiv_safe64(uint64_t x, uint64_t y) {
  uint64_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x / ys;
}

SCALAR_FUN_ATTR uint8_t udiv_up_safe8(uint8_t x, uint8_t y) {
  uint8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : (x + y - 1) / ys;
}

SCALAR_FUN_ATTR uint16_t udiv_up_safe16(uint16_t x, uint16_t y) {
  uint16_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : (x + y - 1) / ys;
}

SCALAR_FUN_ATTR uint32_t udiv_up_safe32(uint32_t x, uint32_t y) {
  uint32_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : (x + y - 1) / ys;
}

SCALAR_FUN_ATTR uint64_t udiv_up_safe64(uint64_t x, uint64_t y) {
  uint64_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : (x + y - 1) / ys;
}

SCALAR_FUN_ATTR uint8_t umod_safe8(uint8_t x, uint8_t y) {
  uint8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x % ys;
}

SCALAR_FUN_ATTR uint16_t umod_safe16(uint16_t x, uint16_t y) {
  uint16_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x % ys;
}

SCALAR_FUN_ATTR uint32_t umod_safe32(uint32_t x, uint32_t y) {
  uint32_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x % ys;
}

SCALAR_FUN_ATTR uint64_t umod_safe64(uint64_t x, uint64_t y) {
  uint64_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x % ys;
}

SCALAR_FUN_ATTR int8_t sdiv8(int8_t x, int8_t y) {
  int8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  int8_t q = x / ys;
  int8_t r = x % ys;

  return q - ((r != 0 && r < 0 != y < 0) ? 1 : 0);
}

SCALAR_FUN_ATTR int16_t sdiv16(int16_t x, int16_t y) {
  int16_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  int16_t q = x / ys;
  int16_t r = x % ys;

  return q - ((r != 0 && r < 0 != y < 0) ? 1 : 0);
}

SCALAR_FUN_ATTR int32_t sdiv32(int32_t x, int32_t y) {
  int32_t ys = 1;
  foreach_active(i){
    ys = y;
  }
  int32_t q = x / ys;
  int32_t r = x % ys;

  return q - ((r != 0 && r < 0 != y < 0) ? 1 : 0);
}

SCALAR_FUN_ATTR int64_t sdiv64(int64_t x, int64_t y) {
  int64_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  int64_t q = x / ys;
  int64_t r = x % ys;

  return q - ((r != 0 && r < 0 != y < 0) ? 1 : 0);
}

SCALAR_FUN_ATTR int8_t sdiv_up8(int8_t x, int8_t y) {
  return sdiv8(x + y - 1, y);
}

SCALAR_FUN_ATTR int16_t sdiv_up16(int16_t x, int16_t y) {
  return sdiv16(x + y - 1, y);
}

SCALAR_FUN_ATTR int32_t sdiv_up32(int32_t x, int32_t y) {
  return sdiv32(x + y - 1, y);
}

SCALAR_FUN_ATTR int64_t sdiv_up64(int64_t x, int64_t y) {
  return sdiv64(x + y - 1, y);
}

SCALAR_FUN_ATTR int8_t smod8(int8_t x, int8_t y) {
  int8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  int8_t r = x % ys;

  return r + (r == 0 || (x > 0 && y > 0) || (x < 0 && y < 0) ? 0 : y);
}

SCALAR_FUN_ATTR int16_t smod16(int16_t x, int16_t y) {
  int16_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  int16_t r = x % ys;

  return r + (r == 0 || (x > 0 && y > 0) || (x < 0 && y < 0) ? 0 : y);
}

SCALAR_FUN_ATTR int32_t smod32(int32_t x, int32_t y) {
  int32_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  int32_t r = x % ys;

  return r + (r == 0 || (x > 0 && y > 0) || (x < 0 && y < 0) ? 0 : y);
}

SCALAR_FUN_ATTR int64_t smod64(int64_t x, int64_t y) {
  int64_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  int64_t r = x % ys;

  return r + (r == 0 || (x > 0 && y > 0) || (x < 0 && y < 0) ? 0 : y);
}

SCALAR_FUN_ATTR int8_t sdiv_safe8(int8_t x, int8_t y) {
  return y == 0 ? 0 : sdiv8(x, y);
}

SCALAR_FUN_ATTR int16_t sdiv_safe16(int16_t x, int16_t y) {
  return y == 0 ? 0 : sdiv16(x, y);
}

SCALAR_FUN_ATTR int32_t sdiv_safe32(int32_t x, int32_t y) {
  return y == 0 ? 0 : sdiv32(x, y);
}

SCALAR_FUN_ATTR int64_t sdiv_safe64(int64_t x, int64_t y) {
  return y == 0 ? 0 : sdiv64(x, y);
}

SCALAR_FUN_ATTR int8_t sdiv_up_safe8(int8_t x, int8_t y) {
  return sdiv_safe8(x + y - 1, y);
}

SCALAR_FUN_ATTR int16_t sdiv_up_safe16(int16_t x, int16_t y) {
  return sdiv_safe16(x + y - 1, y);
}

SCALAR_FUN_ATTR int32_t sdiv_up_safe32(int32_t x, int32_t y) {
  return sdiv_safe32(x + y - 1, y);
}

SCALAR_FUN_ATTR int64_t sdiv_up_safe64(int64_t x, int64_t y) {
  return sdiv_safe64(x + y - 1, y);
}

SCALAR_FUN_ATTR int8_t smod_safe8(int8_t x, int8_t y) {
  return y == 0 ? 0 : smod8(x, y);
}

SCALAR_FUN_ATTR int16_t smod_safe16(int16_t x, int16_t y) {
  return y == 0 ? 0 : smod16(x, y);
}

SCALAR_FUN_ATTR int32_t smod_safe32(int32_t x, int32_t y) {
  return y == 0 ? 0 : smod32(x, y);
}

SCALAR_FUN_ATTR int64_t smod_safe64(int64_t x, int64_t y) {
  return y == 0 ? 0 : smod64(x, y);
}

SCALAR_FUN_ATTR int8_t squot8(int8_t x, int8_t y) {
  int8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x / ys;
}

SCALAR_FUN_ATTR int16_t squot16(int16_t x, int16_t y) {
  int16_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x / ys;
}

SCALAR_FUN_ATTR int32_t squot32(int32_t x, int32_t y) {
  int32_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x / ys;
}

SCALAR_FUN_ATTR int64_t squot64(int64_t x, int64_t y) {
  int64_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x / ys;
}

SCALAR_FUN_ATTR int8_t srem8(int8_t x, int8_t y) {
  int8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x % ys;
}

SCALAR_FUN_ATTR int16_t srem16(int16_t x, int16_t y) {
  int16_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x % ys;
}

SCALAR_FUN_ATTR int32_t srem32(int32_t x, int32_t y) {
  int32_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x % ys;
}

SCALAR_FUN_ATTR int64_t srem64(int64_t x, int64_t y) {
  int8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return x % ys;
}

SCALAR_FUN_ATTR int8_t squot_safe8(int8_t x, int8_t y) {
  int8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x / ys;
}

SCALAR_FUN_ATTR int16_t squot_safe16(int16_t x, int16_t y) {
  int16_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x / ys;
}

SCALAR_FUN_ATTR int32_t squot_safe32(int32_t x, int32_t y) {
  int32_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x / ys;
}

SCALAR_FUN_ATTR int64_t squot_safe64(int64_t x, int64_t y) {
  int64_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x / ys;
}

SCALAR_FUN_ATTR int8_t srem_safe8(int8_t x, int8_t y) {
  int8_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x % ys;
}

SCALAR_FUN_ATTR int16_t srem_safe16(int16_t x, int16_t y) {
  int16_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x % ys;
}

SCALAR_FUN_ATTR int32_t srem_safe32(int32_t x, int32_t y) {
  int32_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x % ys;
}

SCALAR_FUN_ATTR int64_t srem_safe64(int64_t x, int64_t y) {
  int64_t ys = 1;
  foreach_active(i){
    ys = y;
  }

  return y == 0 ? 0 : x % ys;
}

#else

SCALAR_FUN_ATTR uint8_t udiv8(uint8_t x, uint8_t y) {
  return x / y;
}

SCALAR_FUN_ATTR uint16_t udiv16(uint16_t x, uint16_t y) {
  return x / y;
}

SCALAR_FUN_ATTR uint32_t udiv32(uint32_t x, uint32_t y) {
  return x / y;
}

SCALAR_FUN_ATTR uint64_t udiv64(uint64_t x, uint64_t y) {
  return x / y;
}

SCALAR_FUN_ATTR uint8_t udiv_up8(uint8_t x, uint8_t y) {
  return (x + y - 1) / y;
}

SCALAR_FUN_ATTR uint16_t udiv_up16(uint16_t x, uint16_t y) {
  return (x + y - 1) / y;
}

SCALAR_FUN_ATTR uint32_t udiv_up32(uint32_t x, uint32_t y) {
  return (x + y - 1) / y;
}

SCALAR_FUN_ATTR uint64_t udiv_up64(uint64_t x, uint64_t y) {
  return (x + y - 1) / y;
}

SCALAR_FUN_ATTR uint8_t umod8(uint8_t x, uint8_t y) {
  return x % y;
}

SCALAR_FUN_ATTR uint16_t umod16(uint16_t x, uint16_t y) {
  return x % y;
}

SCALAR_FUN_ATTR uint32_t umod32(uint32_t x, uint32_t y) {
  return x % y;
}

SCALAR_FUN_ATTR uint64_t umod64(uint64_t x, uint64_t y) {
  return x % y;
}

SCALAR_FUN_ATTR uint8_t udiv_safe8(uint8_t x, uint8_t y) {
  return y == 0 ? 0 : x / y;
}

SCALAR_FUN_ATTR uint16_t udiv_safe16(uint16_t x, uint16_t y) {
  return y == 0 ? 0 : x / y;
}

SCALAR_FUN_ATTR uint32_t udiv_safe32(uint32_t x, uint32_t y) {
  return y == 0 ? 0 : x / y;
}

SCALAR_FUN_ATTR uint64_t udiv_safe64(uint64_t x, uint64_t y) {
  return y == 0 ? 0 : x / y;
}

SCALAR_FUN_ATTR uint8_t udiv_up_safe8(uint8_t x, uint8_t y) {
  return y == 0 ? 0 : (x + y - 1) / y;
}

SCALAR_FUN_ATTR uint16_t udiv_up_safe16(uint16_t x, uint16_t y) {
  return y == 0 ? 0 : (x + y - 1) / y;
}

SCALAR_FUN_ATTR uint32_t udiv_up_safe32(uint32_t x, uint32_t y) {
  return y == 0 ? 0 : (x + y - 1) / y;
}

SCALAR_FUN_ATTR uint64_t udiv_up_safe64(uint64_t x, uint64_t y) {
  return y == 0 ? 0 : (x + y - 1) / y;
}

SCALAR_FUN_ATTR uint8_t umod_safe8(uint8_t x, uint8_t y) {
  return y == 0 ? 0 : x % y;
}

SCALAR_FUN_ATTR uint16_t umod_safe16(uint16_t x, uint16_t y) {
  return y == 0 ? 0 : x % y;
}

SCALAR_FUN_ATTR uint32_t umod_safe32(uint32_t x, uint32_t y) {
  return y == 0 ? 0 : x % y;
}

SCALAR_FUN_ATTR uint64_t umod_safe64(uint64_t x, uint64_t y) {
  return y == 0 ? 0 : x % y;
}

SCALAR_FUN_ATTR int8_t sdiv8(int8_t x, int8_t y) {
  int8_t q = x / y;
  int8_t r = x % y;

  return q - ((r != 0 && r < 0 != y < 0) ? 1 : 0);
}

SCALAR_FUN_ATTR int16_t sdiv16(int16_t x, int16_t y) {
  int16_t q = x / y;
  int16_t r = x % y;

  return q - ((r != 0 && r < 0 != y < 0) ? 1 : 0);
}

SCALAR_FUN_ATTR int32_t sdiv32(int32_t x, int32_t y) {
  int32_t q = x / y;
  int32_t r = x % y;

  return q - ((r != 0 && r < 0 != y < 0) ? 1 : 0);
}

SCALAR_FUN_ATTR int64_t sdiv64(int64_t x, int64_t y) {
  int64_t q = x / y;
  int64_t r = x % y;

  return q - ((r != 0 && r < 0 != y < 0) ? 1 : 0);
}

SCALAR_FUN_ATTR int8_t sdiv_up8(int8_t x, int8_t y) {
  return sdiv8(x + y - 1, y);
}

SCALAR_FUN_ATTR int16_t sdiv_up16(int16_t x, int16_t y) {
  return sdiv16(x + y - 1, y);
}

SCALAR_FUN_ATTR int32_t sdiv_up32(int32_t x, int32_t y) {
  return sdiv32(x + y - 1, y);
}

SCALAR_FUN_ATTR int64_t sdiv_up64(int64_t x, int64_t y) {
  return sdiv64(x + y - 1, y);
}

SCALAR_FUN_ATTR int8_t smod8(int8_t x, int8_t y) {
  int8_t r = x % y;

  return r + (r == 0 || (x > 0 && y > 0) || (x < 0 && y < 0) ? 0 : y);
}

SCALAR_FUN_ATTR int16_t smod16(int16_t x, int16_t y) {
  int16_t r = x % y;

  return r + (r == 0 || (x > 0 && y > 0) || (x < 0 && y < 0) ? 0 : y);
}

SCALAR_FUN_ATTR int32_t smod32(int32_t x, int32_t y) {
  int32_t r = x % y;

  return r + (r == 0 || (x > 0 && y > 0) || (x < 0 && y < 0) ? 0 : y);
}

SCALAR_FUN_ATTR int64_t smod64(int64_t x, int64_t y) {
  int64_t r = x % y;

  return r + (r == 0 || (x > 0 && y > 0) || (x < 0 && y < 0) ? 0 : y);
}

SCALAR_FUN_ATTR int8_t sdiv_safe8(int8_t x, int8_t y) {
  return y == 0 ? 0 : sdiv8(x, y);
}

SCALAR_FUN_ATTR int16_t sdiv_safe16(int16_t x, int16_t y) {
  return y == 0 ? 0 : sdiv16(x, y);
}

SCALAR_FUN_ATTR int32_t sdiv_safe32(int32_t x, int32_t y) {
  return y == 0 ? 0 : sdiv32(x, y);
}

SCALAR_FUN_ATTR int64_t sdiv_safe64(int64_t x, int64_t y) {
  return y == 0 ? 0 : sdiv64(x, y);
}

SCALAR_FUN_ATTR int8_t sdiv_up_safe8(int8_t x, int8_t y) {
  return sdiv_safe8(x + y - 1, y);
}

SCALAR_FUN_ATTR int16_t sdiv_up_safe16(int16_t x, int16_t y) {
  return sdiv_safe16(x + y - 1, y);
}

SCALAR_FUN_ATTR int32_t sdiv_up_safe32(int32_t x, int32_t y) {
  return sdiv_safe32(x + y - 1, y);
}

SCALAR_FUN_ATTR int64_t sdiv_up_safe64(int64_t x, int64_t y) {
  return sdiv_safe64(x + y - 1, y);
}

SCALAR_FUN_ATTR int8_t smod_safe8(int8_t x, int8_t y) {
  return y == 0 ? 0 : smod8(x, y);
}

SCALAR_FUN_ATTR int16_t smod_safe16(int16_t x, int16_t y) {
  return y == 0 ? 0 : smod16(x, y);
}

SCALAR_FUN_ATTR int32_t smod_safe32(int32_t x, int32_t y) {
  return y == 0 ? 0 : smod32(x, y);
}

SCALAR_FUN_ATTR int64_t smod_safe64(int64_t x, int64_t y) {
  return y == 0 ? 0 : smod64(x, y);
}

SCALAR_FUN_ATTR int8_t squot8(int8_t x, int8_t y) {
  return x / y;
}

SCALAR_FUN_ATTR int16_t squot16(int16_t x, int16_t y) {
  return x / y;
}

SCALAR_FUN_ATTR int32_t squot32(int32_t x, int32_t y) {
  return x / y;
}

SCALAR_FUN_ATTR int64_t squot64(int64_t x, int64_t y) {
  return x / y;
}

SCALAR_FUN_ATTR int8_t srem8(int8_t x, int8_t y) {
  return x % y;
}

SCALAR_FUN_ATTR int16_t srem16(int16_t x, int16_t y) {
  return x % y;
}

SCALAR_FUN_ATTR int32_t srem32(int32_t x, int32_t y) {
  return x % y;
}

SCALAR_FUN_ATTR int64_t srem64(int64_t x, int64_t y) {
  return x % y;
}

SCALAR_FUN_ATTR int8_t squot_safe8(int8_t x, int8_t y) {
  return y == 0 ? 0 : x / y;
}

SCALAR_FUN_ATTR int16_t squot_safe16(int16_t x, int16_t y) {
  return y == 0 ? 0 : x / y;
}

SCALAR_FUN_ATTR int32_t squot_safe32(int32_t x, int32_t y) {
  return y == 0 ? 0 : x / y;
}

SCALAR_FUN_ATTR int64_t squot_safe64(int64_t x, int64_t y) {
  return y == 0 ? 0 : x / y;
}

SCALAR_FUN_ATTR int8_t srem_safe8(int8_t x, int8_t y) {
  return y == 0 ? 0 : x % y;
}

SCALAR_FUN_ATTR int16_t srem_safe16(int16_t x, int16_t y) {
  return y == 0 ? 0 : x % y;
}

SCALAR_FUN_ATTR int32_t srem_safe32(int32_t x, int32_t y) {
  return y == 0 ? 0 : x % y;
}

SCALAR_FUN_ATTR int64_t srem_safe64(int64_t x, int64_t y) {
  return y == 0 ? 0 : x % y;
}

#endif

SCALAR_FUN_ATTR int8_t smin8(int8_t x, int8_t y) {
  return x < y ? x : y;
}

SCALAR_FUN_ATTR int16_t smin16(int16_t x, int16_t y) {
  return x < y ? x : y;
}

SCALAR_FUN_ATTR int32_t smin32(int32_t x, int32_t y) {
  return x < y ? x : y;
}

SCALAR_FUN_ATTR int64_t smin64(int64_t x, int64_t y) {
  return x < y ? x : y;
}

SCALAR_FUN_ATTR uint8_t umin8(uint8_t x, uint8_t y) {
  return x < y ? x : y;
}

SCALAR_FUN_ATTR uint16_t umin16(uint16_t x, uint16_t y) {
  return x < y ? x : y;
}

SCALAR_FUN_ATTR uint32_t umin32(uint32_t x, uint32_t y) {
  return x < y ? x : y;
}

SCALAR_FUN_ATTR uint64_t umin64(uint64_t x, uint64_t y) {
  return x < y ? x : y;
}

SCALAR_FUN_ATTR int8_t smax8(int8_t x, int8_t y) {
  return x < y ? y : x;
}

SCALAR_FUN_ATTR int16_t smax16(int16_t x, int16_t y) {
  return x < y ? y : x;
}

SCALAR_FUN_ATTR int32_t smax32(int32_t x, int32_t y) {
  return x < y ? y : x;
}

SCALAR_FUN_ATTR int64_t smax64(int64_t x, int64_t y) {
  return x < y ? y : x;
}

SCALAR_FUN_ATTR uint8_t umax8(uint8_t x, uint8_t y) {
  return x < y ? y : x;
}

SCALAR_FUN_ATTR uint16_t umax16(uint16_t x, uint16_t y) {
  return x < y ? y : x;
}

SCALAR_FUN_ATTR uint32_t umax32(uint32_t x, uint32_t y) {
  return x < y ? y : x;
}

SCALAR_FUN_ATTR uint64_t umax64(uint64_t x, uint64_t y) {
  return x < y ? y : x;
}

SCALAR_FUN_ATTR uint8_t shl8(uint8_t x, uint8_t y) {
  return (uint8_t)(x << y);
}

SCALAR_FUN_ATTR uint16_t shl16(uint16_t x, uint16_t y) {
  return (uint16_t)(x << y);
}

SCALAR_FUN_ATTR uint32_t shl32(uint32_t x, uint32_t y) {
  return x << y;
}

SCALAR_FUN_ATTR uint64_t shl64(uint64_t x, uint64_t y) {
  return x << y;
}

SCALAR_FUN_ATTR uint8_t lshr8(uint8_t x, uint8_t y) {
  return x >> y;
}

SCALAR_FUN_ATTR uint16_t lshr16(uint16_t x, uint16_t y) {
  return x >> y;
}

SCALAR_FUN_ATTR uint32_t lshr32(uint32_t x, uint32_t y) {
  return x >> y;
}

SCALAR_FUN_ATTR uint64_t lshr64(uint64_t x, uint64_t y) {
  return x >> y;
}

SCALAR_FUN_ATTR int8_t ashr8(int8_t x, int8_t y) {
  return x >> y;
}

SCALAR_FUN_ATTR int16_t ashr16(int16_t x, int16_t y) {
  return x >> y;
}

SCALAR_FUN_ATTR int32_t ashr32(int32_t x, int32_t y) {
  return x >> y;
}

SCALAR_FUN_ATTR int64_t ashr64(int64_t x, int64_t y) {
  return x >> y;
}

SCALAR_FUN_ATTR uint8_t and8(uint8_t x, uint8_t y) {
  return x & y;
}

SCALAR_FUN_ATTR uint16_t and16(uint16_t x, uint16_t y) {
  return x & y;
}

SCALAR_FUN_ATTR uint32_t and32(uint32_t x, uint32_t y) {
  return x & y;
}

SCALAR_FUN_ATTR uint64_t and64(uint64_t x, uint64_t y) {
  return x & y;
}

SCALAR_FUN_ATTR uint8_t or8(uint8_t x, uint8_t y) {
  return x | y;
}

SCALAR_FUN_ATTR uint16_t or16(uint16_t x, uint16_t y) {
  return x | y;
}

SCALAR_FUN_ATTR uint32_t or32(uint32_t x, uint32_t y) {
  return x | y;
}

SCALAR_FUN_ATTR uint64_t or64(uint64_t x, uint64_t y) {
  return x | y;
}

SCALAR_FUN_ATTR uint8_t xor8(uint8_t x, uint8_t y) {
  return x ^ y;
}

SCALAR_FUN_ATTR uint16_t xor16(uint16_t x, uint16_t y) {
  return x ^ y;
}

SCALAR_FUN_ATTR uint32_t xor32(uint32_t x, uint32_t y) {
  return x ^ y;
}

SCALAR_FUN_ATTR uint64_t xor64(uint64_t x, uint64_t y) {
  return x ^ y;
}

SCALAR_FUN_ATTR bool ult8(uint8_t x, uint8_t y) {
  return x < y;
}

SCALAR_FUN_ATTR bool ult16(uint16_t x, uint16_t y) {
  return x < y;
}

SCALAR_FUN_ATTR bool ult32(uint32_t x, uint32_t y) {
  return x < y;
}

SCALAR_FUN_ATTR bool ult64(uint64_t x, uint64_t y) {
  return x < y;
}

SCALAR_FUN_ATTR bool ule8(uint8_t x, uint8_t y) {
  return x <= y;
}

SCALAR_FUN_ATTR bool ule16(uint16_t x, uint16_t y) {
  return x <= y;
}

SCALAR_FUN_ATTR bool ule32(uint32_t x, uint32_t y) {
  return x <= y;
}

SCALAR_FUN_ATTR bool ule64(uint64_t x, uint64_t y) {
  return x <= y;
}

SCALAR_FUN_ATTR bool slt8(int8_t x, int8_t y) {
  return x < y;
}

SCALAR_FUN_ATTR bool slt16(int16_t x, int16_t y) {
  return x < y;
}

SCALAR_FUN_ATTR bool slt32(int32_t x, int32_t y) {
  return x < y;
}

SCALAR_FUN_ATTR bool slt64(int64_t x, int64_t y) {
  return x < y;
}

SCALAR_FUN_ATTR bool sle8(int8_t x, int8_t y) {
  return x <= y;
}

SCALAR_FUN_ATTR bool sle16(int16_t x, int16_t y) {
  return x <= y;
}

SCALAR_FUN_ATTR bool sle32(int32_t x, int32_t y) {
  return x <= y;
}

SCALAR_FUN_ATTR bool sle64(int64_t x, int64_t y) {
  return x <= y;
}

SCALAR_FUN_ATTR uint8_t pow8(uint8_t x, uint8_t y) {
  uint8_t res = 1, rem = y;

  while (rem != 0) {
    if (rem & 1)
      res *= x;
    rem >>= 1;
    x *= x;
  }
  return res;
}

SCALAR_FUN_ATTR uint16_t pow16(uint16_t x, uint16_t y) {
  uint16_t res = 1, rem = y;

  while (rem != 0) {
    if (rem & 1)
      res *= x;
    rem >>= 1;
    x *= x;
  }
  return res;
}

SCALAR_FUN_ATTR uint32_t pow32(uint32_t x, uint32_t y) {
  uint32_t res = 1, rem = y;

  while (rem != 0) {
    if (rem & 1)
      res *= x;
    rem >>= 1;
    x *= x;
  }
  return res;
}

SCALAR_FUN_ATTR uint64_t pow64(uint64_t x, uint64_t y) {
  uint64_t res = 1, rem = y;

  while (rem != 0) {
    if (rem & 1)
      res *= x;
    rem >>= 1;
    x *= x;
  }
  return res;
}

SCALAR_FUN_ATTR bool itob_i8_bool(int8_t x) {
  return x != 0;
}

SCALAR_FUN_ATTR bool itob_i16_bool(int16_t x) {
  return x != 0;
}

SCALAR_FUN_ATTR bool itob_i32_bool(int32_t x) {
  return x != 0;
}

SCALAR_FUN_ATTR bool itob_i64_bool(int64_t x) {
  return x != 0;
}

SCALAR_FUN_ATTR int8_t btoi_bool_i8(bool x) {
  return x;
}

SCALAR_FUN_ATTR int16_t btoi_bool_i16(bool x) {
  return x;
}

SCALAR_FUN_ATTR int32_t btoi_bool_i32(bool x) {
  return x;
}

SCALAR_FUN_ATTR int64_t btoi_bool_i64(bool x) {
  return x;
}

#define sext_i8_i8(x) ((int8_t) (int8_t) (x))
#define sext_i8_i16(x) ((int16_t) (int8_t) (x))
#define sext_i8_i32(x) ((int32_t) (int8_t) (x))
#define sext_i8_i64(x) ((int64_t) (int8_t) (x))
#define sext_i16_i8(x) ((int8_t) (int16_t) (x))
#define sext_i16_i16(x) ((int16_t) (int16_t) (x))
#define sext_i16_i32(x) ((int32_t) (int16_t) (x))
#define sext_i16_i64(x) ((int64_t) (int16_t) (x))
#define sext_i32_i8(x) ((int8_t) (int32_t) (x))
#define sext_i32_i16(x) ((int16_t) (int32_t) (x))
#define sext_i32_i32(x) ((int32_t) (int32_t) (x))
#define sext_i32_i64(x) ((int64_t) (int32_t) (x))
#define sext_i64_i8(x) ((int8_t) (int64_t) (x))
#define sext_i64_i16(x) ((int16_t) (int64_t) (x))
#define sext_i64_i32(x) ((int32_t) (int64_t) (x))
#define sext_i64_i64(x) ((int64_t) (int64_t) (x))
#define zext_i8_i8(x) ((int8_t) (uint8_t) (x))
#define zext_i8_i16(x) ((int16_t) (uint8_t) (x))
#define zext_i8_i32(x) ((int32_t) (uint8_t) (x))
#define zext_i8_i64(x) ((int64_t) (uint8_t) (x))
#define zext_i16_i8(x) ((int8_t) (uint16_t) (x))
#define zext_i16_i16(x) ((int16_t) (uint16_t) (x))
#define zext_i16_i32(x) ((int32_t) (uint16_t) (x))
#define zext_i16_i64(x) ((int64_t) (uint16_t) (x))
#define zext_i32_i8(x) ((int8_t) (uint32_t) (x))
#define zext_i32_i16(x) ((int16_t) (uint32_t) (x))
#define zext_i32_i32(x) ((int32_t) (uint32_t) (x))
#define zext_i32_i64(x) ((int64_t) (uint32_t) (x))
#define zext_i64_i8(x) ((int8_t) (uint64_t) (x))
#define zext_i64_i16(x) ((int16_t) (uint64_t) (x))
#define zext_i64_i32(x) ((int32_t) (uint64_t) (x))
#define zext_i64_i64(x) ((int64_t) (uint64_t) (x))

SCALAR_FUN_ATTR int8_t abs8(int8_t x) {
  return (int8_t)abs(x);
}

SCALAR_FUN_ATTR int16_t abs16(int16_t x) {
  return (int16_t)abs(x);
}

SCALAR_FUN_ATTR int32_t abs32(int32_t x) {
  return abs(x);
}

SCALAR_FUN_ATTR int64_t abs64(int64_t x) {
#if defined(__OPENCL_VERSION__) || defined(ISPC)
  return abs(x);
#else
  return llabs(x);
#endif
}

#if defined(__OPENCL_VERSION__)
SCALAR_FUN_ATTR int32_t futrts_popc8(int8_t x) {
  return popcount(x);
}

SCALAR_FUN_ATTR int32_t futrts_popc16(int16_t x) {
  return popcount(x);
}

SCALAR_FUN_ATTR int32_t futrts_popc32(int32_t x) {
  return popcount(x);
}

SCALAR_FUN_ATTR int32_t futrts_popc64(int64_t x) {
  return popcount(x);
}
#elif defined(__CUDA_ARCH__)

SCALAR_FUN_ATTR int32_t futrts_popc8(int8_t x) {
  return __popc(zext_i8_i32(x));
}

SCALAR_FUN_ATTR int32_t futrts_popc16(int16_t x) {
  return __popc(zext_i16_i32(x));
}

SCALAR_FUN_ATTR int32_t futrts_popc32(int32_t x) {
  return __popc(x);
}

SCALAR_FUN_ATTR int32_t futrts_popc64(int64_t x) {
  return __popcll(x);
}

#else  

SCALAR_FUN_ATTR int32_t futrts_popc8(uint8_t x) {
  int c = 0;
  for (; x; ++c) { x &= x - 1; }
  return c;
}

SCALAR_FUN_ATTR int32_t futrts_popc16(uint16_t x) {
  int c = 0;
  for (; x; ++c) { x &= x - 1; }
  return c;
}

SCALAR_FUN_ATTR int32_t futrts_popc32(uint32_t x) {
  int c = 0;
  for (; x; ++c) { x &= x - 1; }
  return c;
}

SCALAR_FUN_ATTR int32_t futrts_popc64(uint64_t x) {
  int c = 0;
  for (; x; ++c) { x &= x - 1; }
  return c;
}
#endif

#if defined(__OPENCL_VERSION__)
SCALAR_FUN_ATTR uint8_t  futrts_umul_hi8 ( uint8_t a,  uint8_t b) { return mul_hi(a, b); }
SCALAR_FUN_ATTR uint16_t futrts_umul_hi16(uint16_t a, uint16_t b) { return mul_hi(a, b); }
SCALAR_FUN_ATTR uint32_t futrts_umul_hi32(uint32_t a, uint32_t b) { return mul_hi(a, b); }
SCALAR_FUN_ATTR uint64_t futrts_umul_hi64(uint64_t a, uint64_t b) { return mul_hi(a, b); }
SCALAR_FUN_ATTR uint8_t  futrts_smul_hi8 ( int8_t a,  int8_t b) { return mul_hi(a, b); }
SCALAR_FUN_ATTR uint16_t futrts_smul_hi16(int16_t a, int16_t b) { return mul_hi(a, b); }
SCALAR_FUN_ATTR uint32_t futrts_smul_hi32(int32_t a, int32_t b) { return mul_hi(a, b); }
SCALAR_FUN_ATTR uint64_t futrts_smul_hi64(int64_t a, int64_t b) { return mul_hi(a, b); }
#elif defined(__CUDA_ARCH__)
SCALAR_FUN_ATTR  uint8_t futrts_umul_hi8(uint8_t a, uint8_t b) { return ((uint16_t)a) * ((uint16_t)b) >> 8; }
SCALAR_FUN_ATTR uint16_t futrts_umul_hi16(uint16_t a, uint16_t b) { return ((uint32_t)a) * ((uint32_t)b) >> 16; }
SCALAR_FUN_ATTR uint32_t futrts_umul_hi32(uint32_t a, uint32_t b) { return __umulhi(a, b); }
SCALAR_FUN_ATTR uint64_t futrts_umul_hi64(uint64_t a, uint64_t b) { return __umul64hi(a, b); }
SCALAR_FUN_ATTR  uint8_t futrts_smul_hi8 ( int8_t a, int8_t b) { return ((int16_t)a) * ((int16_t)b) >> 8; }
SCALAR_FUN_ATTR uint16_t futrts_smul_hi16(int16_t a, int16_t b) { return ((int32_t)a) * ((int32_t)b) >> 16; }
SCALAR_FUN_ATTR uint32_t futrts_smul_hi32(int32_t a, int32_t b) { return __mulhi(a, b); }
SCALAR_FUN_ATTR uint64_t futrts_smul_hi64(int64_t a, int64_t b) { return __mul64hi(a, b); }
#elif defined(ISPC)
SCALAR_FUN_ATTR uint8_t futrts_umul_hi8(uint8_t a, uint8_t b) { return ((uint16_t)a) * ((uint16_t)b) >> 8; }
SCALAR_FUN_ATTR uint16_t futrts_umul_hi16(uint16_t a, uint16_t b) { return ((uint32_t)a) * ((uint32_t)b) >> 16; }
SCALAR_FUN_ATTR uint32_t futrts_umul_hi32(uint32_t a, uint32_t b) { return ((uint64_t)a) * ((uint64_t)b) >> 32; }
SCALAR_FUN_ATTR uint64_t futrts_umul_hi64(uint64_t a, uint64_t b) {
  uint64_t ah = a >> 32;
  uint64_t al = a & 0xffffffff;
  uint64_t bh = b >> 32;
  uint64_t bl = b & 0xffffffff;

  uint64_t p1 = al * bl;
  uint64_t p2 = al * bh;
  uint64_t p3 = ah * bl;
  uint64_t p4 = ah * bh;

  uint64_t p1h = p1 >> 32;
  uint64_t p2h = p2 >> 32;
  uint64_t p3h = p3 >> 32;
  uint64_t p2l = p2 & 0xffffffff;
  uint64_t p3l = p3 & 0xffffffff;

  uint64_t l = p1h + p2l + p3l;
  uint64_t m = (p2 >> 32) + (p3 >> 32);
  uint64_t h = (l >> 32) + m + p4;

  return h;
}
SCALAR_FUN_ATTR  int8_t futrts_smul_hi8 ( int8_t a,  int8_t b) { return ((uint16_t)a) * ((uint16_t)b) >> 8; }
SCALAR_FUN_ATTR int16_t futrts_smul_hi16(int16_t a, int16_t b) { return ((uint32_t)a) * ((uint32_t)b) >> 16; }
SCALAR_FUN_ATTR int32_t futrts_smul_hi32(int32_t a, int32_t b) { return ((uint64_t)a) * ((uint64_t)b) >> 32; }
SCALAR_FUN_ATTR int64_t futrts_smul_hi64(int64_t a, int64_t b) {
  uint64_t ah = a >> 32;
  uint64_t al = a & 0xffffffff;
  uint64_t bh = b >> 32;
  uint64_t bl = b & 0xffffffff;

  uint64_t p1 =  al * bl;
  int64_t  p2 = al * bh;
  int64_t  p3 = ah * bl;
  uint64_t p4 =  ah * bh;

  uint64_t p1h = p1 >> 32;
  uint64_t p2h = p2 >> 32;
  uint64_t p3h = p3 >> 32;
  uint64_t p2l = p2 & 0xffffffff;
  uint64_t p3l = p3 & 0xffffffff;

  uint64_t l = p1h + p2l + p3l;
  uint64_t m = (p2 >> 32) + (p3 >> 32);
  uint64_t h = (l >> 32) + m + p4;

  return h;
}

#else  
SCALAR_FUN_ATTR uint8_t futrts_umul_hi8(uint8_t a, uint8_t b) { return ((uint16_t)a) * ((uint16_t)b) >> 8; }
SCALAR_FUN_ATTR uint16_t futrts_umul_hi16(uint16_t a, uint16_t b) { return ((uint32_t)a) * ((uint32_t)b) >> 16; }
SCALAR_FUN_ATTR uint32_t futrts_umul_hi32(uint32_t a, uint32_t b) { return ((uint64_t)a) * ((uint64_t)b) >> 32; }
SCALAR_FUN_ATTR uint64_t futrts_umul_hi64(uint64_t a, uint64_t b) { return ((__uint128_t)a) * ((__uint128_t)b) >> 64; }
SCALAR_FUN_ATTR int8_t futrts_smul_hi8(int8_t a, int8_t b) { return ((int16_t)a) * ((int16_t)b) >> 8; }
SCALAR_FUN_ATTR int16_t futrts_smul_hi16(int16_t a, int16_t b) { return ((int32_t)a) * ((int32_t)b) >> 16; }
SCALAR_FUN_ATTR int32_t futrts_smul_hi32(int32_t a, int32_t b) { return ((int64_t)a) * ((int64_t)b) >> 32; }
SCALAR_FUN_ATTR int64_t futrts_smul_hi64(int64_t a, int64_t b) { return ((__int128_t)a) * ((__int128_t)b) >> 64; }
#endif

#if defined(__OPENCL_VERSION__)
SCALAR_FUN_ATTR  uint8_t futrts_umad_hi8 ( uint8_t a,  uint8_t b,  uint8_t c) { return mad_hi(a, b, c); }
SCALAR_FUN_ATTR uint16_t futrts_umad_hi16(uint16_t a, uint16_t b, uint16_t c) { return mad_hi(a, b, c); }
SCALAR_FUN_ATTR uint32_t futrts_umad_hi32(uint32_t a, uint32_t b, uint32_t c) { return mad_hi(a, b, c); }
SCALAR_FUN_ATTR uint64_t futrts_umad_hi64(uint64_t a, uint64_t b, uint64_t c) { return mad_hi(a, b, c); }
SCALAR_FUN_ATTR  uint8_t futrts_smad_hi8( int8_t a,  int8_t b,   int8_t c) { return mad_hi(a, b, c); }
SCALAR_FUN_ATTR uint16_t futrts_smad_hi16(int16_t a, int16_t b, int16_t c) { return mad_hi(a, b, c); }
SCALAR_FUN_ATTR uint32_t futrts_smad_hi32(int32_t a, int32_t b, int32_t c) { return mad_hi(a, b, c); }
SCALAR_FUN_ATTR uint64_t futrts_smad_hi64(int64_t a, int64_t b, int64_t c) { return mad_hi(a, b, c); }
#else  

SCALAR_FUN_ATTR  uint8_t futrts_umad_hi8( uint8_t a,  uint8_t b,  uint8_t c) { return futrts_umul_hi8(a, b) + c; }
SCALAR_FUN_ATTR uint16_t futrts_umad_hi16(uint16_t a, uint16_t b, uint16_t c) { return futrts_umul_hi16(a, b) + c; }
SCALAR_FUN_ATTR uint32_t futrts_umad_hi32(uint32_t a, uint32_t b, uint32_t c) { return futrts_umul_hi32(a, b) + c; }
SCALAR_FUN_ATTR uint64_t futrts_umad_hi64(uint64_t a, uint64_t b, uint64_t c) { return futrts_umul_hi64(a, b) + c; }
SCALAR_FUN_ATTR  uint8_t futrts_smad_hi8 ( int8_t a,  int8_t b,  int8_t c) { return futrts_smul_hi8(a, b) + c; }
SCALAR_FUN_ATTR uint16_t futrts_smad_hi16(int16_t a, int16_t b, int16_t c) { return futrts_smul_hi16(a, b) + c; }
SCALAR_FUN_ATTR uint32_t futrts_smad_hi32(int32_t a, int32_t b, int32_t c) { return futrts_smul_hi32(a, b) + c; }
SCALAR_FUN_ATTR uint64_t futrts_smad_hi64(int64_t a, int64_t b, int64_t c) { return futrts_smul_hi64(a, b) + c; }
#endif

#if defined(__OPENCL_VERSION__)
SCALAR_FUN_ATTR int32_t futrts_clzz8(int8_t x) {
  return clz(x);
}

SCALAR_FUN_ATTR int32_t futrts_clzz16(int16_t x) {
  return clz(x);
}

SCALAR_FUN_ATTR int32_t futrts_clzz32(int32_t x) {
  return clz(x);
}

SCALAR_FUN_ATTR int32_t futrts_clzz64(int64_t x) {
  return clz(x);
}

#elif defined(__CUDA_ARCH__)

SCALAR_FUN_ATTR int32_t futrts_clzz8(int8_t x) {
  return __clz(zext_i8_i32(x)) - 24;
}

SCALAR_FUN_ATTR int32_t futrts_clzz16(int16_t x) {
  return __clz(zext_i16_i32(x)) - 16;
}

SCALAR_FUN_ATTR int32_t futrts_clzz32(int32_t x) {
  return __clz(x);
}

SCALAR_FUN_ATTR int32_t futrts_clzz64(int64_t x) {
  return __clzll(x);
}

#elif defined(ISPC)

SCALAR_FUN_ATTR int32_t futrts_clzz8(int8_t x) {
  return count_leading_zeros((int32_t)(uint8_t)x)-24;
}

SCALAR_FUN_ATTR int32_t futrts_clzz16(int16_t x) {
  return count_leading_zeros((int32_t)(uint16_t)x)-16;
}

SCALAR_FUN_ATTR int32_t futrts_clzz32(int32_t x) {
  return count_leading_zeros(x);
}

SCALAR_FUN_ATTR int32_t futrts_clzz64(int64_t x) {
  return count_leading_zeros(x);
}

#else  

SCALAR_FUN_ATTR int32_t futrts_clzz8(int8_t x) {
  return x == 0 ? 8 : __builtin_clz((uint32_t)zext_i8_i32(x)) - 24;
}

SCALAR_FUN_ATTR int32_t futrts_clzz16(int16_t x) {
  return x == 0 ? 16 : __builtin_clz((uint32_t)zext_i16_i32(x)) - 16;
}

SCALAR_FUN_ATTR int32_t futrts_clzz32(int32_t x) {
  return x == 0 ? 32 : __builtin_clz((uint32_t)x);
}

SCALAR_FUN_ATTR int32_t futrts_clzz64(int64_t x) {
  return x == 0 ? 64 : __builtin_clzll((uint64_t)x);
}
#endif

#if defined(__OPENCL_VERSION__)
SCALAR_FUN_ATTR int32_t futrts_ctzz8(int8_t x) {
  int i = 0;
  for (; i < 8 && (x & 1) == 0; i++, x >>= 1)
    ;
  return i;
}

SCALAR_FUN_ATTR int32_t futrts_ctzz16(int16_t x) {
  int i = 0;
  for (; i < 16 && (x & 1) == 0; i++, x >>= 1)
    ;
  return i;
}

SCALAR_FUN_ATTR int32_t futrts_ctzz32(int32_t x) {
  int i = 0;
  for (; i < 32 && (x & 1) == 0; i++, x >>= 1)
    ;
  return i;
}

SCALAR_FUN_ATTR int32_t futrts_ctzz64(int64_t x) {
  int i = 0;
  for (; i < 64 && (x & 1) == 0; i++, x >>= 1)
    ;
  return i;
}

#elif defined(__CUDA_ARCH__)

SCALAR_FUN_ATTR int32_t futrts_ctzz8(int8_t x) {
  int y = __ffs(x);
  return y == 0 ? 8 : y - 1;
}

SCALAR_FUN_ATTR int32_t futrts_ctzz16(int16_t x) {
  int y = __ffs(x);
  return y == 0 ? 16 : y - 1;
}

SCALAR_FUN_ATTR int32_t futrts_ctzz32(int32_t x) {
  int y = __ffs(x);
  return y == 0 ? 32 : y - 1;
}

SCALAR_FUN_ATTR int32_t futrts_ctzz64(int64_t x) {
  int y = __ffsll(x);
  return y == 0 ? 64 : y - 1;
}

#elif defined(ISPC)

SCALAR_FUN_ATTR int32_t futrts_ctzz8(int8_t x) {
  return x == 0 ? 8 : count_trailing_zeros((int32_t)x);
}

SCALAR_FUN_ATTR int32_t futrts_ctzz16(int16_t x) {
  return x == 0 ? 16 : count_trailing_zeros((int32_t)x);
}

SCALAR_FUN_ATTR int32_t futrts_ctzz32(int32_t x) {
  return count_trailing_zeros(x);
}

SCALAR_FUN_ATTR int32_t futrts_ctzz64(int64_t x) {
  return count_trailing_zeros(x);
}

#else  

SCALAR_FUN_ATTR int32_t futrts_ctzz8(int8_t x) {
  return x == 0 ? 8 : __builtin_ctz((uint32_t)x);
}

SCALAR_FUN_ATTR int32_t futrts_ctzz16(int16_t x) {
  return x == 0 ? 16 : __builtin_ctz((uint32_t)x);
}

SCALAR_FUN_ATTR int32_t futrts_ctzz32(int32_t x) {
  return x == 0 ? 32 : __builtin_ctz((uint32_t)x);
}

SCALAR_FUN_ATTR int32_t futrts_ctzz64(int64_t x) {
  return x == 0 ? 64 : __builtin_ctzll((uint64_t)x);
}
#endif

SCALAR_FUN_ATTR float fdiv32(float x, float y) {
  return x / y;
}

SCALAR_FUN_ATTR float fadd32(float x, float y) {
  return x + y;
}

SCALAR_FUN_ATTR float fsub32(float x, float y) {
  return x - y;
}

SCALAR_FUN_ATTR float fmul32(float x, float y) {
  return x * y;
}

SCALAR_FUN_ATTR bool cmplt32(float x, float y) {
  return x < y;
}

SCALAR_FUN_ATTR bool cmple32(float x, float y) {
  return x <= y;
}

SCALAR_FUN_ATTR float sitofp_i8_f32(int8_t x) {
  return (float) x;
}

SCALAR_FUN_ATTR float sitofp_i16_f32(int16_t x) {
  return (float) x;
}

SCALAR_FUN_ATTR float sitofp_i32_f32(int32_t x) {
  return (float) x;
}

SCALAR_FUN_ATTR float sitofp_i64_f32(int64_t x) {
  return (float) x;
}

SCALAR_FUN_ATTR float uitofp_i8_f32(uint8_t x) {
  return (float) x;
}

SCALAR_FUN_ATTR float uitofp_i16_f32(uint16_t x) {
  return (float) x;
}

SCALAR_FUN_ATTR float uitofp_i32_f32(uint32_t x) {
  return (float) x;
}

SCALAR_FUN_ATTR float uitofp_i64_f32(uint64_t x) {
  return (float) x;
}

#ifdef __OPENCL_VERSION__
SCALAR_FUN_ATTR float fabs32(float x) {
  return fabs(x);
}

SCALAR_FUN_ATTR float fmax32(float x, float y) {
  return fmax(x, y);
}

SCALAR_FUN_ATTR float fmin32(float x, float y) {
  return fmin(x, y);
}

SCALAR_FUN_ATTR float fpow32(float x, float y) {
  return pow(x, y);
}

#elif defined(ISPC)

SCALAR_FUN_ATTR float fabs32(float x) {
  return abs(x);
}

SCALAR_FUN_ATTR float fmax32(float x, float y) {
  return isnan(x) ? y : isnan(y) ? x : max(x, y);
}

SCALAR_FUN_ATTR float fmin32(float x, float y) {
  return isnan(x) ? y : isnan(y) ? x : min(x, y);
}

SCALAR_FUN_ATTR float fpow32(float a, float b) {
  float ret;
  foreach_active (i) {
      uniform float r = pow(extract(a, i), extract(b, i));
      ret = insert(ret, i, r);
  }
  return ret;
}

#else  

SCALAR_FUN_ATTR float fabs32(float x) {
  return fabsf(x);
}

SCALAR_FUN_ATTR float fmax32(float x, float y) {
  return fmaxf(x, y);
}

SCALAR_FUN_ATTR float fmin32(float x, float y) {
  return fminf(x, y);
}

SCALAR_FUN_ATTR float fpow32(float x, float y) {
  return powf(x, y);
}
#endif

SCALAR_FUN_ATTR bool futrts_isnan32(float x) {
  return isnan(x);
}

#if defined(ISPC)

SCALAR_FUN_ATTR bool futrts_isinf32(float x) {
  return !isnan(x) && isnan(x - x);
}

SCALAR_FUN_ATTR bool futrts_isfinite32(float x) {
  return !isnan(x) && !futrts_isinf32(x);
}

#else

SCALAR_FUN_ATTR bool futrts_isinf32(float x) {
  return isinf(x);
}

#endif

SCALAR_FUN_ATTR int8_t fptosi_f32_i8(float x) {
  if (futrts_isnan32(x) || futrts_isinf32(x)) {
    return 0;
  } else {
    return (int8_t) x;
  }
}

SCALAR_FUN_ATTR int16_t fptosi_f32_i16(float x) {
  if (futrts_isnan32(x) || futrts_isinf32(x)) {
    return 0;
  } else {
    return (int16_t) x;
  }
}

SCALAR_FUN_ATTR int32_t fptosi_f32_i32(float x) {
  if (futrts_isnan32(x) || futrts_isinf32(x)) {
    return 0;
  } else {
    return (int32_t) x;
  }
}

SCALAR_FUN_ATTR int64_t fptosi_f32_i64(float x) {
  if (futrts_isnan32(x) || futrts_isinf32(x)) {
    return 0;
  } else {
    return (int64_t) x;
  };
}

SCALAR_FUN_ATTR uint8_t fptoui_f32_i8(float x) {
  if (futrts_isnan32(x) || futrts_isinf32(x)) {
    return 0;
  } else {
    return (uint8_t) (int8_t) x;
  }
}

SCALAR_FUN_ATTR uint16_t fptoui_f32_i16(float x) {
  if (futrts_isnan32(x) || futrts_isinf32(x)) {
    return 0;
  } else {
    return (uint16_t) (int16_t) x;
  }
}

SCALAR_FUN_ATTR uint32_t fptoui_f32_i32(float x) {
  if (futrts_isnan32(x) || futrts_isinf32(x)) {
    return 0;
  } else {
    return (uint32_t) (int32_t) x;
  }
}

SCALAR_FUN_ATTR uint64_t fptoui_f32_i64(float x) {
  if (futrts_isnan32(x) || futrts_isinf32(x)) {
    return 0;
  } else {
    return (uint64_t) (int64_t) x;
  }
}

SCALAR_FUN_ATTR bool ftob_f32_bool(float x) {
  return x != 0;
}

SCALAR_FUN_ATTR float btof_bool_f32(bool x) {
  return x ? 1 : 0;
}

#ifdef __OPENCL_VERSION__
SCALAR_FUN_ATTR float futrts_log32(float x) {
  return log(x);
}

SCALAR_FUN_ATTR float futrts_log2_32(float x) {
  return log2(x);
}

SCALAR_FUN_ATTR float futrts_log10_32(float x) {
  return log10(x);
}

SCALAR_FUN_ATTR float futrts_log1p_32(float x) {
  return log1p(x);
}

SCALAR_FUN_ATTR float futrts_sqrt32(float x) {
  return sqrt(x);
}

SCALAR_FUN_ATTR float futrts_cbrt32(float x) {
  return cbrt(x);
}

SCALAR_FUN_ATTR float futrts_exp32(float x) {
  return exp(x);
}

SCALAR_FUN_ATTR float futrts_cos32(float x) {
  return cos(x);
}

SCALAR_FUN_ATTR float futrts_sin32(float x) {
  return sin(x);
}

SCALAR_FUN_ATTR float futrts_tan32(float x) {
  return tan(x);
}

SCALAR_FUN_ATTR float futrts_acos32(float x) {
  return acos(x);
}

SCALAR_FUN_ATTR float futrts_asin32(float x) {
  return asin(x);
}

SCALAR_FUN_ATTR float futrts_atan32(float x) {
  return atan(x);
}

SCALAR_FUN_ATTR float futrts_cosh32(float x) {
  return cosh(x);
}

SCALAR_FUN_ATTR float futrts_sinh32(float x) {
  return sinh(x);
}

SCALAR_FUN_ATTR float futrts_tanh32(float x) {
  return tanh(x);
}

SCALAR_FUN_ATTR float futrts_acosh32(float x) {
  return acosh(x);
}

SCALAR_FUN_ATTR float futrts_asinh32(float x) {
  return asinh(x);
}

SCALAR_FUN_ATTR float futrts_atanh32(float x) {
  return atanh(x);
}

SCALAR_FUN_ATTR float futrts_atan2_32(float x, float y) {
  return atan2(x, y);
}

SCALAR_FUN_ATTR float futrts_hypot32(float x, float y) {
  return hypot(x, y);
}

SCALAR_FUN_ATTR float futrts_gamma32(float x) {
  return tgamma(x);
}

SCALAR_FUN_ATTR float futrts_lgamma32(float x) {
  return lgamma(x);
}

SCALAR_FUN_ATTR float futrts_erf32(float x) {
  return erf(x);
}

SCALAR_FUN_ATTR float futrts_erfc32(float x) {
  return erfc(x);
}

SCALAR_FUN_ATTR float fmod32(float x, float y) {
  return fmod(x, y);
}

SCALAR_FUN_ATTR float futrts_round32(float x) {
  return rint(x);
}

SCALAR_FUN_ATTR float futrts_floor32(float x) {
  return floor(x);
}

SCALAR_FUN_ATTR float futrts_ceil32(float x) {
  return ceil(x);
}

SCALAR_FUN_ATTR float futrts_nextafter32(float x, float y) {
  return nextafter(x, y);
}

SCALAR_FUN_ATTR float futrts_lerp32(float v0, float v1, float t) {
  return mix(v0, v1, t);
}

SCALAR_FUN_ATTR float futrts_ldexp32(float x, int32_t y) {
  return ldexp(x, y);
}

SCALAR_FUN_ATTR float futrts_copysign32(float x, float y) {
  return copysign(x, y);
}

SCALAR_FUN_ATTR float futrts_mad32(float a, float b, float c) {
  return mad(a, b, c);
}

SCALAR_FUN_ATTR float futrts_fma32(float a, float b, float c) {
  return fma(a, b, c);
}

#elif defined(ISPC)

SCALAR_FUN_ATTR float futrts_log32(float x) {
  return futrts_isfinite32(x) || (futrts_isinf32(x) && x < 0)? log(x) : x;
}

SCALAR_FUN_ATTR float futrts_log2_32(float x) {
  return futrts_log32(x) / log(2.0f);
}

SCALAR_FUN_ATTR float futrts_log10_32(float x) {
  return futrts_log32(x) / log(10.0f);
}

SCALAR_FUN_ATTR float futrts_log1p_32(float x) {
  if(x == -1.0f || (futrts_isinf32(x) && x > 0.0f)) return x / 0.0f;
  float y = 1.0f + x;
  float z = y - 1.0f;
  return log(y) - (z-x)/y;
}

SCALAR_FUN_ATTR float futrts_sqrt32(float x) {
  return sqrt(x);
}

extern "C" unmasked uniform float cbrtf(uniform float);
SCALAR_FUN_ATTR float futrts_cbrt32(float x) {
  float res;
  foreach_active (i) {
    uniform float r = cbrtf(extract(x, i));
    res = insert(res, i, r);
  }
  return res;
}

SCALAR_FUN_ATTR float futrts_exp32(float x) {
  return exp(x);
}

SCALAR_FUN_ATTR float futrts_cos32(float x) {
  return cos(x);
}

SCALAR_FUN_ATTR float futrts_sin32(float x) {
  return sin(x);
}

SCALAR_FUN_ATTR float futrts_tan32(float x) {
  return tan(x);
}

SCALAR_FUN_ATTR float futrts_acos32(float x) {
  return acos(x);
}

SCALAR_FUN_ATTR float futrts_asin32(float x) {
  return asin(x);
}

SCALAR_FUN_ATTR float futrts_atan32(float x) {
  return atan(x);
}

SCALAR_FUN_ATTR float futrts_cosh32(float x) {
  return (exp(x)+exp(-x)) / 2.0f;
}

SCALAR_FUN_ATTR float futrts_sinh32(float x) {
  return (exp(x)-exp(-x)) / 2.0f;
}

SCALAR_FUN_ATTR float futrts_tanh32(float x) {
  return futrts_sinh32(x)/futrts_cosh32(x);
}

SCALAR_FUN_ATTR float futrts_acosh32(float x) {
  float f = x+sqrt(x*x-1);
  if(futrts_isfinite32(f)) return log(f);
  return f;
}

SCALAR_FUN_ATTR float futrts_asinh32(float x) {
  float f = x+sqrt(x*x+1);
  if(futrts_isfinite32(f)) return log(f);
  return f;

}

SCALAR_FUN_ATTR float futrts_atanh32(float x) {
  float f = (1+x)/(1-x);
  if(futrts_isfinite32(f)) return log(f)/2.0f;
  return f;

}

SCALAR_FUN_ATTR float futrts_atan2_32(float x, float y) {
  return (x == 0.0f && y == 0.0f) ? 0.0f : atan2(x, y);
}

SCALAR_FUN_ATTR float futrts_hypot32(float x, float y) {
  if (futrts_isfinite32(x) && futrts_isfinite32(y)) {
    x = abs(x);
    y = abs(y);
    float a;
    float b;
    if (x >= y){
        a = x;
        b = y;
    } else {
        a = y;
        b = x;
    }
    if(b == 0){
      return a;
    }

    int e;
    float an;
    float bn;
    an = frexp (a, &e);
    bn = ldexp (b, - e);
    float cn;
    cn = sqrt (an * an + bn * bn);
    return ldexp (cn, e);
  } else {
    if (futrts_isinf32(x) || futrts_isinf32(y)) return INFINITY;
    else return x + y;
  }

}

extern "C" unmasked uniform float tgammaf(uniform float x);
SCALAR_FUN_ATTR float futrts_gamma32(float x) {
  float res;
  foreach_active (i) {
    uniform float r = tgammaf(extract(x, i));
    res = insert(res, i, r);
  }
  return res;
}

extern "C" unmasked uniform float lgammaf(uniform float x);
SCALAR_FUN_ATTR float futrts_lgamma32(float x) {
  float res;
  foreach_active (i) {
    uniform float r = lgammaf(extract(x, i));
    res = insert(res, i, r);
  }
  return res;
}

extern "C" unmasked uniform float erff(uniform float x);
SCALAR_FUN_ATTR float futrts_erf32(float x) {
  float res;
  foreach_active (i) {
    uniform float r = erff(extract(x, i));
    res = insert(res, i, r);
  }
  return res;
}

extern "C" unmasked uniform float erfcf(uniform float x);
SCALAR_FUN_ATTR float futrts_erfc32(float x) {
  float res;
  foreach_active (i) {
    uniform float r = erfcf(extract(x, i));
    res = insert(res, i, r);
  }
  return res;
}

SCALAR_FUN_ATTR float fmod32(float x, float y) {
  return x - y * trunc(x/y);
}

SCALAR_FUN_ATTR float futrts_round32(float x) {
  return round(x);
}

SCALAR_FUN_ATTR float futrts_floor32(float x) {
  return floor(x);
}

SCALAR_FUN_ATTR float futrts_ceil32(float x) {
  return ceil(x);
}

extern "C" unmasked uniform float nextafterf(uniform float x, uniform float y);
SCALAR_FUN_ATTR float futrts_nextafter32(float x, float y) {
  float res;
  foreach_active (i) {
    uniform float r = nextafterf(extract(x, i), extract(y, i));
    res = insert(res, i, r);
  }
  return res;
}

SCALAR_FUN_ATTR float futrts_lerp32(float v0, float v1, float t) {
  return v0 + (v1 - v0) * t;
}

SCALAR_FUN_ATTR float futrts_ldexp32(float x, int32_t y) {
  return x * pow((uniform float)2.0, (float)y);
}

SCALAR_FUN_ATTR float futrts_copysign32(float x, float y) {
  int32_t xb = futrts_to_bits32(x);
  int32_t yb = futrts_to_bits32(y);
  return futrts_from_bits32((xb & ~(1<<31)) | (yb & (1<<31)));
}

SCALAR_FUN_ATTR float futrts_mad32(float a, float b, float c) {
  return a * b + c;
}

SCALAR_FUN_ATTR float futrts_fma32(float a, float b, float c) {
  return a * b + c;
}

#else  

SCALAR_FUN_ATTR float futrts_log32(float x) {
  return logf(x);
}

SCALAR_FUN_ATTR float futrts_log2_32(float x) {
  return log2f(x);
}

SCALAR_FUN_ATTR float futrts_log10_32(float x) {
  return log10f(x);
}

SCALAR_FUN_ATTR float futrts_log1p_32(float x) {
  return log1pf(x);
}

SCALAR_FUN_ATTR float futrts_sqrt32(float x) {
  return sqrtf(x);
}

SCALAR_FUN_ATTR float futrts_cbrt32(float x) {
  return cbrtf(x);
}

SCALAR_FUN_ATTR float futrts_exp32(float x) {
  return expf(x);
}

SCALAR_FUN_ATTR float futrts_cos32(float x) {
  return cosf(x);
}

SCALAR_FUN_ATTR float futrts_sin32(float x) {
  return sinf(x);
}

SCALAR_FUN_ATTR float futrts_tan32(float x) {
  return tanf(x);
}

SCALAR_FUN_ATTR float futrts_acos32(float x) {
  return acosf(x);
}

SCALAR_FUN_ATTR float futrts_asin32(float x) {
  return asinf(x);
}

SCALAR_FUN_ATTR float futrts_atan32(float x) {
  return atanf(x);
}

SCALAR_FUN_ATTR float futrts_cosh32(float x) {
  return coshf(x);
}

SCALAR_FUN_ATTR float futrts_sinh32(float x) {
  return sinhf(x);
}

SCALAR_FUN_ATTR float futrts_tanh32(float x) {
  return tanhf(x);
}

SCALAR_FUN_ATTR float futrts_acosh32(float x) {
  return acoshf(x);
}

SCALAR_FUN_ATTR float futrts_asinh32(float x) {
  return asinhf(x);
}

SCALAR_FUN_ATTR float futrts_atanh32(float x) {
  return atanhf(x);
}

SCALAR_FUN_ATTR float futrts_atan2_32(float x, float y) {
  return atan2f(x, y);
}

SCALAR_FUN_ATTR float futrts_hypot32(float x, float y) {
  return hypotf(x, y);
}

SCALAR_FUN_ATTR float futrts_gamma32(float x) {
  return tgammaf(x);
}

SCALAR_FUN_ATTR float futrts_lgamma32(float x) {
  return lgammaf(x);
}

SCALAR_FUN_ATTR float futrts_erf32(float x) {
  return erff(x);
}

SCALAR_FUN_ATTR float futrts_erfc32(float x) {
  return erfcf(x);
}

SCALAR_FUN_ATTR float fmod32(float x, float y) {
  return fmodf(x, y);
}

SCALAR_FUN_ATTR float futrts_round32(float x) {
  return rintf(x);
}

SCALAR_FUN_ATTR float futrts_floor32(float x) {
  return floorf(x);
}

SCALAR_FUN_ATTR float futrts_ceil32(float x) {
  return ceilf(x);
}

SCALAR_FUN_ATTR float futrts_nextafter32(float x, float y) {
  return nextafterf(x, y);
}

SCALAR_FUN_ATTR float futrts_lerp32(float v0, float v1, float t) {
  return v0 + (v1 - v0) * t;
}

SCALAR_FUN_ATTR float futrts_ldexp32(float x, int32_t y) {
  return ldexpf(x, y);
}

SCALAR_FUN_ATTR float futrts_copysign32(float x, float y) {
  return copysignf(x, y);
}

SCALAR_FUN_ATTR float futrts_mad32(float a, float b, float c) {
  return a * b + c;
}

SCALAR_FUN_ATTR float futrts_fma32(float a, float b, float c) {
  return fmaf(a, b, c);
}
#endif

#if defined(ISPC)
SCALAR_FUN_ATTR int32_t futrts_to_bits32(float x) {
  return intbits(x);
}

SCALAR_FUN_ATTR float futrts_from_bits32(int32_t x) {
  return floatbits(x);
}
#else
SCALAR_FUN_ATTR int32_t futrts_to_bits32(float x) {
  union {
    float f;
    int32_t t;
  } p;

  p.f = x;
  return p.t;
}

SCALAR_FUN_ATTR float futrts_from_bits32(int32_t x) {
  union {
    int32_t f;
    float t;
  } p;

  p.f = x;
  return p.t;
}
#endif

SCALAR_FUN_ATTR float fsignum32(float x) {
  return futrts_isnan32(x) ? x : (x > 0 ? 1 : 0) - (x < 0 ? 1 : 0);
}

#ifdef FUTHARK_F64_ENABLED

SCALAR_FUN_ATTR double futrts_from_bits64(int64_t x);
SCALAR_FUN_ATTR int64_t futrts_to_bits64(double x);

#if defined(ISPC)
SCALAR_FUN_ATTR bool futrts_isinf64(float x) {
  return !isnan(x) && isnan(x - x);
}

SCALAR_FUN_ATTR bool futrts_isfinite64(float x) {
  return !isnan(x) && !futrts_isinf64(x);
}

SCALAR_FUN_ATTR double fdiv64(double x, double y) {
  return x / y;
}

SCALAR_FUN_ATTR double fadd64(double x, double y) {
  return x + y;
}

SCALAR_FUN_ATTR double fsub64(double x, double y) {
  return x - y;
}

SCALAR_FUN_ATTR double fmul64(double x, double y) {
  return x * y;
}

SCALAR_FUN_ATTR bool cmplt64(double x, double y) {
  return x < y;
}

SCALAR_FUN_ATTR bool cmple64(double x, double y) {
  return x <= y;
}

SCALAR_FUN_ATTR double sitofp_i8_f64(int8_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double sitofp_i16_f64(int16_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double sitofp_i32_f64(int32_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double sitofp_i64_f64(int64_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double uitofp_i8_f64(uint8_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double uitofp_i16_f64(uint16_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double uitofp_i32_f64(uint32_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double uitofp_i64_f64(uint64_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double fabs64(double x) {
  return abs(x);
}

SCALAR_FUN_ATTR double fmax64(double x, double y) {
  return isnan(x) ? y : isnan(y) ? x : max(x, y);
}

SCALAR_FUN_ATTR double fmin64(double x, double y) {
  return isnan(x) ? y : isnan(y) ? x : min(x, y);
}

SCALAR_FUN_ATTR double fpow64(double a, double b) {
  float ret;
  foreach_active (i) {
      uniform float r = pow(extract(a, i), extract(b, i));
      ret = insert(ret, i, r);
  }
  return ret;
}

SCALAR_FUN_ATTR double futrts_log64(double x) {
  return futrts_isfinite64(x) || (futrts_isinf64(x) && x < 0)? log(x) : x;
}

SCALAR_FUN_ATTR double futrts_log2_64(double x) {
  return futrts_log64(x)/log(2.0d);
}

SCALAR_FUN_ATTR double futrts_log10_64(double x) {
  return futrts_log64(x)/log(10.0d);
}

SCALAR_FUN_ATTR double futrts_log1p_64(double x) {
  if(x == -1.0d || (futrts_isinf64(x) && x > 0.0d)) return x / 0.0d;
  double y = 1.0d + x;
  double z = y - 1.0d;
  return log(y) - (z-x)/y;
}

SCALAR_FUN_ATTR double futrts_sqrt64(double x) {
  return sqrt(x);
}

extern "C" unmasked uniform double cbrt(uniform double);
SCALAR_FUN_ATTR double futrts_cbrt64(double x) {
  double res;
  foreach_active (i) {
    uniform double r = cbrtf(extract(x, i));
    res = insert(res, i, r);
  }
  return res;
}

SCALAR_FUN_ATTR double futrts_exp64(double x) {
  return exp(x);
}

SCALAR_FUN_ATTR double futrts_cos64(double x) {
  return cos(x);
}

SCALAR_FUN_ATTR double futrts_sin64(double x) {
  return sin(x);
}

SCALAR_FUN_ATTR double futrts_tan64(double x) {
  return tan(x);
}

SCALAR_FUN_ATTR double futrts_acos64(double x) {
  return acos(x);
}

SCALAR_FUN_ATTR double futrts_asin64(double x) {
  return asin(x);
}

SCALAR_FUN_ATTR double futrts_atan64(double x) {
  return atan(x);
}

SCALAR_FUN_ATTR double futrts_cosh64(double x) {
  return (exp(x)+exp(-x)) / 2.0d;
}

SCALAR_FUN_ATTR double futrts_sinh64(double x) {
  return (exp(x)-exp(-x)) / 2.0d;
}

SCALAR_FUN_ATTR double futrts_tanh64(double x) {
  return futrts_sinh64(x)/futrts_cosh64(x);
}

SCALAR_FUN_ATTR double futrts_acosh64(double x) {
  double f = x+sqrt(x*x-1.0d);
  if(futrts_isfinite64(f)) return log(f);
  return f;
}

SCALAR_FUN_ATTR double futrts_asinh64(double x) {
  double f = x+sqrt(x*x+1.0d);
  if(futrts_isfinite64(f)) return log(f);
  return f;
}

SCALAR_FUN_ATTR double futrts_atanh64(double x) {
  double f = (1.0d+x)/(1.0d-x);
  if(futrts_isfinite64(f)) return log(f)/2.0d;
  return f;

}

SCALAR_FUN_ATTR double futrts_atan2_64(double x, double y) {
  return atan2(x, y);
}

extern "C" unmasked uniform double hypot(uniform double x, uniform double y);
SCALAR_FUN_ATTR double futrts_hypot64(double x, double y) {
  double res;
  foreach_active (i) {
    uniform double r = hypot(extract(x, i), extract(y, i));
    res = insert(res, i, r);
  }
  return res;
}

extern "C" unmasked uniform double tgamma(uniform double x);
SCALAR_FUN_ATTR double futrts_gamma64(double x) {
  double res;
  foreach_active (i) {
    uniform double r = tgamma(extract(x, i));
    res = insert(res, i, r);
  }
  return res;
}

extern "C" unmasked uniform double lgamma(uniform double x);
SCALAR_FUN_ATTR double futrts_lgamma64(double x) {
  double res;
  foreach_active (i) {
    uniform double r = lgamma(extract(x, i));
    res = insert(res, i, r);
  }
  return res;
}

extern "C" unmasked uniform double erf(uniform double x);
SCALAR_FUN_ATTR double futrts_erf64(double x) {
  double res;
  foreach_active (i) {
    uniform double r = erf(extract(x, i));
    res = insert(res, i, r);
  }
  return res;
}

extern "C" unmasked uniform double erfc(uniform double x);
SCALAR_FUN_ATTR double futrts_erfc64(double x) {
  double res;
  foreach_active (i) {
    uniform double r = erfc(extract(x, i));
    res = insert(res, i, r);
  }
  return res;
}

SCALAR_FUN_ATTR double futrts_fma64(double a, double b, double c) {
  return a * b + c;
}

SCALAR_FUN_ATTR double futrts_round64(double x) {
  return round(x);
}

SCALAR_FUN_ATTR double futrts_ceil64(double x) {
  return ceil(x);
}

extern "C" unmasked uniform double nextafter(uniform float x, uniform double y);
SCALAR_FUN_ATTR float futrts_nextafter64(double x, double y) {
  double res;
  foreach_active (i) {
    uniform double r = nextafter(extract(x, i), extract(y, i));
    res = insert(res, i, r);
  }
  return res;
}

SCALAR_FUN_ATTR double futrts_floor64(double x) {
  return floor(x);
}

SCALAR_FUN_ATTR bool futrts_isnan64(double x) {
  return isnan(x);
}

SCALAR_FUN_ATTR int8_t fptosi_f64_i8(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (int8_t) x;
  }
}

SCALAR_FUN_ATTR int16_t fptosi_f64_i16(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (int16_t) x;
  }
}

SCALAR_FUN_ATTR int32_t fptosi_f64_i32(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (int32_t) x;
  }
}

SCALAR_FUN_ATTR int64_t fptosi_f64_i64(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (int64_t) x;
  }
}

SCALAR_FUN_ATTR uint8_t fptoui_f64_i8(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (uint8_t) (int8_t) x;
  }
}

SCALAR_FUN_ATTR uint16_t fptoui_f64_i16(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (uint16_t) (int16_t) x;
  }
}

SCALAR_FUN_ATTR uint32_t fptoui_f64_i32(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (uint32_t) (int32_t) x;
  }
}

SCALAR_FUN_ATTR uint64_t fptoui_f64_i64(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (uint64_t) (int64_t) x;
  }
}

SCALAR_FUN_ATTR bool ftob_f64_bool(double x) {
  return x != 0.0;
}

SCALAR_FUN_ATTR double btof_bool_f64(bool x) {
  return x ? 1.0 : 0.0;
}

SCALAR_FUN_ATTR int64_t futrts_to_bits64(double x) {
  int64_t res;
  foreach_active (i) {
    uniform double tmp = extract(x, i);
    uniform int64_t r = *((uniform int64_t* uniform)&tmp);
    res = insert(res, i, r);
  }
  return res;
}

SCALAR_FUN_ATTR double futrts_from_bits64(int64_t x) {
  double res;
  foreach_active (i) {
    uniform int64_t tmp = extract(x, i);
    uniform double r = *((uniform double* uniform)&tmp);
    res = insert(res, i, r);
  }
  return res;
}

SCALAR_FUN_ATTR double fmod64(double x, double y) {
  return x - y * trunc(x/y);
}

SCALAR_FUN_ATTR double fsignum64(double x) {
  return futrts_isnan64(x) ? x : (x > 0 ? 1.0d : 0.0d) - (x < 0 ? 1.0d : 0.0d);
}

SCALAR_FUN_ATTR double futrts_lerp64(double v0, double v1, double t) {
  return v0 + (v1 - v0) * t;
}

SCALAR_FUN_ATTR double futrts_ldexp64(double x, int32_t y) {
  return x * pow((uniform double)2.0, (double)y);
}

SCALAR_FUN_ATTR double futrts_copysign64(double x, double y) {
  int64_t xb = futrts_to_bits64(x);
  int64_t yb = futrts_to_bits64(y);
  return futrts_from_bits64((xb & ~(((int64_t)1)<<63)) | (yb & (((int64_t)1)<<63)));
}

SCALAR_FUN_ATTR double futrts_mad64(double a, double b, double c) {
  return a * b + c;
}

SCALAR_FUN_ATTR float fpconv_f32_f32(float x) {
  return (float) x;
}

SCALAR_FUN_ATTR double fpconv_f32_f64(float x) {
  return (double) x;
}

SCALAR_FUN_ATTR float fpconv_f64_f32(double x) {
  return (float) x;
}

SCALAR_FUN_ATTR double fpconv_f64_f64(double x) {
  return (double) x;
}

#else

SCALAR_FUN_ATTR double fdiv64(double x, double y) {
  return x / y;
}

SCALAR_FUN_ATTR double fadd64(double x, double y) {
  return x + y;
}

SCALAR_FUN_ATTR double fsub64(double x, double y) {
  return x - y;
}

SCALAR_FUN_ATTR double fmul64(double x, double y) {
  return x * y;
}

SCALAR_FUN_ATTR bool cmplt64(double x, double y) {
  return x < y;
}

SCALAR_FUN_ATTR bool cmple64(double x, double y) {
  return x <= y;
}

SCALAR_FUN_ATTR double sitofp_i8_f64(int8_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double sitofp_i16_f64(int16_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double sitofp_i32_f64(int32_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double sitofp_i64_f64(int64_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double uitofp_i8_f64(uint8_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double uitofp_i16_f64(uint16_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double uitofp_i32_f64(uint32_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double uitofp_i64_f64(uint64_t x) {
  return (double) x;
}

SCALAR_FUN_ATTR double fabs64(double x) {
  return fabs(x);
}

SCALAR_FUN_ATTR double fmax64(double x, double y) {
  return fmax(x, y);
}

SCALAR_FUN_ATTR double fmin64(double x, double y) {
  return fmin(x, y);
}

SCALAR_FUN_ATTR double fpow64(double x, double y) {
  return pow(x, y);
}

SCALAR_FUN_ATTR double futrts_log64(double x) {
  return log(x);
}

SCALAR_FUN_ATTR double futrts_log2_64(double x) {
  return log2(x);
}

SCALAR_FUN_ATTR double futrts_log10_64(double x) {
  return log10(x);
}

SCALAR_FUN_ATTR double futrts_log1p_64(double x) {
  return log1p(x);
}

SCALAR_FUN_ATTR double futrts_sqrt64(double x) {
  return sqrt(x);
}

SCALAR_FUN_ATTR double futrts_cbrt64(double x) {
  return cbrt(x);
}

SCALAR_FUN_ATTR double futrts_exp64(double x) {
  return exp(x);
}

SCALAR_FUN_ATTR double futrts_cos64(double x) {
  return cos(x);
}

SCALAR_FUN_ATTR double futrts_sin64(double x) {
  return sin(x);
}

SCALAR_FUN_ATTR double futrts_tan64(double x) {
  return tan(x);
}

SCALAR_FUN_ATTR double futrts_acos64(double x) {
  return acos(x);
}

SCALAR_FUN_ATTR double futrts_asin64(double x) {
  return asin(x);
}

SCALAR_FUN_ATTR double futrts_atan64(double x) {
  return atan(x);
}

SCALAR_FUN_ATTR double futrts_cosh64(double x) {
  return cosh(x);
}

SCALAR_FUN_ATTR double futrts_sinh64(double x) {
  return sinh(x);
}

SCALAR_FUN_ATTR double futrts_tanh64(double x) {
  return tanh(x);
}

SCALAR_FUN_ATTR double futrts_acosh64(double x) {
  return acosh(x);
}

SCALAR_FUN_ATTR double futrts_asinh64(double x) {
  return asinh(x);
}

SCALAR_FUN_ATTR double futrts_atanh64(double x) {
  return atanh(x);
}

SCALAR_FUN_ATTR double futrts_atan2_64(double x, double y) {
  return atan2(x, y);
}

SCALAR_FUN_ATTR double futrts_hypot64(double x, double y) {
  return hypot(x, y);
}

SCALAR_FUN_ATTR double futrts_gamma64(double x) {
  return tgamma(x);
}

SCALAR_FUN_ATTR double futrts_lgamma64(double x) {
  return lgamma(x);
}

SCALAR_FUN_ATTR double futrts_erf64(double x) {
  return erf(x);
}

SCALAR_FUN_ATTR double futrts_erfc64(double x) {
  return erfc(x);
}

SCALAR_FUN_ATTR double futrts_fma64(double a, double b, double c) {
  return fma(a, b, c);
}

SCALAR_FUN_ATTR double futrts_round64(double x) {
  return rint(x);
}

SCALAR_FUN_ATTR double futrts_ceil64(double x) {
  return ceil(x);
}

SCALAR_FUN_ATTR float futrts_nextafter64(float x, float y) {
  return nextafter(x, y);
}

SCALAR_FUN_ATTR double futrts_floor64(double x) {
  return floor(x);
}

SCALAR_FUN_ATTR bool futrts_isnan64(double x) {
  return isnan(x);
}

SCALAR_FUN_ATTR bool futrts_isinf64(double x) {
  return isinf(x);
}

SCALAR_FUN_ATTR int8_t fptosi_f64_i8(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (int8_t) x;
  }
}

SCALAR_FUN_ATTR int16_t fptosi_f64_i16(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (int16_t) x;
  }
}

SCALAR_FUN_ATTR int32_t fptosi_f64_i32(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (int32_t) x;
  }
}

SCALAR_FUN_ATTR int64_t fptosi_f64_i64(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (int64_t) x;
  }
}

SCALAR_FUN_ATTR uint8_t fptoui_f64_i8(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (uint8_t) (int8_t) x;
  }
}

SCALAR_FUN_ATTR uint16_t fptoui_f64_i16(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (uint16_t) (int16_t) x;
  }
}

SCALAR_FUN_ATTR uint32_t fptoui_f64_i32(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (uint32_t) (int32_t) x;
  }
}

SCALAR_FUN_ATTR uint64_t fptoui_f64_i64(double x) {
  if (futrts_isnan64(x) || futrts_isinf64(x)) {
    return 0;
  } else {
    return (uint64_t) (int64_t) x;
  }
}

SCALAR_FUN_ATTR bool ftob_f64_bool(double x) {
  return x != 0;
}

SCALAR_FUN_ATTR double btof_bool_f64(bool x) {
  return x ? 1 : 0;
}

SCALAR_FUN_ATTR int64_t futrts_to_bits64(double x) {
  union {
    double f;
    int64_t t;
  } p;

  p.f = x;
  return p.t;
}

SCALAR_FUN_ATTR double futrts_from_bits64(int64_t x) {
  union {
    int64_t f;
    double t;
  } p;

  p.f = x;
  return p.t;
}

SCALAR_FUN_ATTR double fmod64(double x, double y) {
  return fmod(x, y);
}

SCALAR_FUN_ATTR double fsignum64(double x) {
  return futrts_isnan64(x) ? x : (x > 0) - (x < 0);
}

SCALAR_FUN_ATTR double futrts_lerp64(double v0, double v1, double t) {
#ifdef __OPENCL_VERSION__
  return mix(v0, v1, t);
#else
  return v0 + (v1 - v0) * t;
#endif
}

SCALAR_FUN_ATTR double futrts_ldexp64(double x, int32_t y) {
  return ldexp(x, y);
}

SCALAR_FUN_ATTR float futrts_copysign64(double x, double y) {
  return copysign(x, y);
}

SCALAR_FUN_ATTR double futrts_mad64(double a, double b, double c) {
#ifdef __OPENCL_VERSION__
  return mad(a, b, c);
#else
  return a * b + c;
#endif
}

SCALAR_FUN_ATTR float fpconv_f32_f32(float x) {
  return (float) x;
}

SCALAR_FUN_ATTR double fpconv_f32_f64(float x) {
  return (double) x;
}

SCALAR_FUN_ATTR float fpconv_f64_f32(double x) {
  return (float) x;
}

SCALAR_FUN_ATTR double fpconv_f64_f64(double x) {
  return (double) x;
}

#endif

#endif

#define futrts_cond_f16(x,y,z) ((x) ? (y) : (z))
#define futrts_cond_f32(x,y,z) ((x) ? (y) : (z))
#define futrts_cond_f64(x,y,z) ((x) ? (y) : (z))

#define futrts_cond_i8(x,y,z) ((x) ? (y) : (z))
#define futrts_cond_i16(x,y,z) ((x) ? (y) : (z))
#define futrts_cond_i32(x,y,z) ((x) ? (y) : (z))
#define futrts_cond_i64(x,y,z) ((x) ? (y) : (z))

#define futrts_cond_bool(x,y,z) ((x) ? (y) : (z))
#define futrts_cond_unit(x,y,z) ((x) ? (y) : (z))

 
 

 
 
 
 
 
 
 
 

#if !defined(cl_khr_fp16) && !(defined(__CUDA_ARCH__) && __CUDA_ARCH__ >= 600) && !(defined(ISPC))
#define EMULATE_F16
#endif

#if !defined(EMULATE_F16) && defined(__OPENCL_VERSION__)
#pragma OPENCL EXTENSION cl_khr_fp16 : enable
#endif

#ifdef EMULATE_F16

 
 
typedef float f16;

#elif defined(ISPC)
typedef float16 f16;

#else

#ifdef __CUDA_ARCH__
#include <cuda_fp16.h>
#endif

typedef half f16;

#endif

 
 

SCALAR_FUN_ATTR f16 fadd16(f16 x, f16 y) {
  return x + y;
}

SCALAR_FUN_ATTR f16 fsub16(f16 x, f16 y) {
  return x - y;
}

SCALAR_FUN_ATTR f16 fmul16(f16 x, f16 y) {
  return x * y;
}

SCALAR_FUN_ATTR bool cmplt16(f16 x, f16 y) {
  return x < y;
}

SCALAR_FUN_ATTR bool cmple16(f16 x, f16 y) {
  return x <= y;
}

SCALAR_FUN_ATTR f16 sitofp_i8_f16(int8_t x) {
  return (f16) x;
}

SCALAR_FUN_ATTR f16 sitofp_i16_f16(int16_t x) {
  return (f16) x;
}

SCALAR_FUN_ATTR f16 sitofp_i32_f16(int32_t x) {
  return (f16) x;
}

SCALAR_FUN_ATTR f16 sitofp_i64_f16(int64_t x) {
  return (f16) x;
}

SCALAR_FUN_ATTR f16 uitofp_i8_f16(uint8_t x) {
  return (f16) x;
}

SCALAR_FUN_ATTR f16 uitofp_i16_f16(uint16_t x) {
  return (f16) x;
}

SCALAR_FUN_ATTR f16 uitofp_i32_f16(uint32_t x) {
  return (f16) x;
}

SCALAR_FUN_ATTR f16 uitofp_i64_f16(uint64_t x) {
  return (f16) x;
}

SCALAR_FUN_ATTR int8_t fptosi_f16_i8(f16 x) {
  return (int8_t) (float) x;
}

SCALAR_FUN_ATTR int16_t fptosi_f16_i16(f16 x) {
  return (int16_t) x;
}

SCALAR_FUN_ATTR int32_t fptosi_f16_i32(f16 x) {
  return (int32_t) x;
}

SCALAR_FUN_ATTR int64_t fptosi_f16_i64(f16 x) {
  return (int64_t) x;
}

SCALAR_FUN_ATTR uint8_t fptoui_f16_i8(f16 x) {
  return (uint8_t) (float) x;
}

SCALAR_FUN_ATTR uint16_t fptoui_f16_i16(f16 x) {
  return (uint16_t) x;
}

SCALAR_FUN_ATTR uint32_t fptoui_f16_i32(f16 x) {
  return (uint32_t) x;
}

SCALAR_FUN_ATTR uint64_t fptoui_f16_i64(f16 x) {
  return (uint64_t) x;
}

SCALAR_FUN_ATTR bool ftob_f16_bool(f16 x) {
  return x != (f16)0;
}

SCALAR_FUN_ATTR f16 btof_bool_f16(bool x) {
  return x ? 1 : 0;
}

#ifndef EMULATE_F16
SCALAR_FUN_ATTR bool futrts_isnan16(f16 x) {
  return isnan((float)x);
}

#ifdef __OPENCL_VERSION__

SCALAR_FUN_ATTR f16 fabs16(f16 x) {
  return fabs(x);
}

SCALAR_FUN_ATTR f16 fmax16(f16 x, f16 y) {
  return fmax(x, y);
}

SCALAR_FUN_ATTR f16 fmin16(f16 x, f16 y) {
  return fmin(x, y);
}

SCALAR_FUN_ATTR f16 fpow16(f16 x, f16 y) {
  return pow(x, y);
}

#elif defined(ISPC)
SCALAR_FUN_ATTR f16 fabs16(f16 x) {
  return abs(x);
}

SCALAR_FUN_ATTR f16 fmax16(f16 x, f16 y) {
  return futrts_isnan16(x) ? y : futrts_isnan16(y) ? x : max(x, y);
}

SCALAR_FUN_ATTR f16 fmin16(f16 x, f16 y) {
  return futrts_isnan16(x) ? y : futrts_isnan16(y) ? x : min(x, y);
}

SCALAR_FUN_ATTR f16 fpow16(f16 x, f16 y) {
  return pow(x, y);
}

#else  

SCALAR_FUN_ATTR f16 fabs16(f16 x) {
  return fabsf(x);
}

SCALAR_FUN_ATTR f16 fmax16(f16 x, f16 y) {
  return fmaxf(x, y);
}

SCALAR_FUN_ATTR f16 fmin16(f16 x, f16 y) {
  return fminf(x, y);
}

SCALAR_FUN_ATTR f16 fpow16(f16 x, f16 y) {
  return powf(x, y);
}
#endif

#if defined(ISPC)
SCALAR_FUN_ATTR bool futrts_isinf16(float x) {
  return !futrts_isnan16(x) && futrts_isnan16(x - x);
}
SCALAR_FUN_ATTR bool futrts_isfinite16(float x) {
  return !futrts_isnan16(x) && !futrts_isinf16(x);
}

#else

SCALAR_FUN_ATTR bool futrts_isinf16(f16 x) {
  return isinf((float)x);
}
#endif

#ifdef __OPENCL_VERSION__
SCALAR_FUN_ATTR f16 futrts_log16(f16 x) {
  return log(x);
}

SCALAR_FUN_ATTR f16 futrts_log2_16(f16 x) {
  return log2(x);
}

SCALAR_FUN_ATTR f16 futrts_log10_16(f16 x) {
  return log10(x);
}

SCALAR_FUN_ATTR f16 futrts_log1p_16(f16 x) {
  return log1p(x);
}

SCALAR_FUN_ATTR f16 futrts_sqrt16(f16 x) {
  return sqrt(x);
}

SCALAR_FUN_ATTR f16 futrts_cbrt16(f16 x) {
  return cbrt(x);
}

SCALAR_FUN_ATTR f16 futrts_exp16(f16 x) {
  return exp(x);
}

SCALAR_FUN_ATTR f16 futrts_cos16(f16 x) {
  return cos(x);
}

SCALAR_FUN_ATTR f16 futrts_sin16(f16 x) {
  return sin(x);
}

SCALAR_FUN_ATTR f16 futrts_tan16(f16 x) {
  return tan(x);
}

SCALAR_FUN_ATTR f16 futrts_acos16(f16 x) {
  return acos(x);
}

SCALAR_FUN_ATTR f16 futrts_asin16(f16 x) {
  return asin(x);
}

SCALAR_FUN_ATTR f16 futrts_atan16(f16 x) {
  return atan(x);
}

SCALAR_FUN_ATTR f16 futrts_cosh16(f16 x) {
  return cosh(x);
}

SCALAR_FUN_ATTR f16 futrts_sinh16(f16 x) {
  return sinh(x);
}

SCALAR_FUN_ATTR f16 futrts_tanh16(f16 x) {
  return tanh(x);
}

SCALAR_FUN_ATTR f16 futrts_acosh16(f16 x) {
  return acosh(x);
}

SCALAR_FUN_ATTR f16 futrts_asinh16(f16 x) {
  return asinh(x);
}

SCALAR_FUN_ATTR f16 futrts_atanh16(f16 x) {
  return atanh(x);
}

SCALAR_FUN_ATTR f16 futrts_atan2_16(f16 x, f16 y) {
  return atan2(x, y);
}

SCALAR_FUN_ATTR f16 futrts_hypot16(f16 x, f16 y) {
  return hypot(x, y);
}

SCALAR_FUN_ATTR f16 futrts_gamma16(f16 x) {
  return tgamma(x);
}

SCALAR_FUN_ATTR f16 futrts_lgamma16(f16 x) {
  return lgamma(x);
}

SCALAR_FUN_ATTR f16 futrts_erf16(f16 x) {
  return erf(x);
}

SCALAR_FUN_ATTR f16 futrts_erfc16(f16 x) {
  return erfc(x);
}

SCALAR_FUN_ATTR f16 fmod16(f16 x, f16 y) {
  return fmod(x, y);
}

SCALAR_FUN_ATTR f16 futrts_round16(f16 x) {
  return rint(x);
}

SCALAR_FUN_ATTR f16 futrts_floor16(f16 x) {
  return floor(x);
}

SCALAR_FUN_ATTR f16 futrts_ceil16(f16 x) {
  return ceil(x);
}

SCALAR_FUN_ATTR f16 futrts_nextafter16(f16 x, f16 y) {
  return nextafter(x, y);
}

SCALAR_FUN_ATTR f16 futrts_lerp16(f16 v0, f16 v1, f16 t) {
  return mix(v0, v1, t);
}

SCALAR_FUN_ATTR f16 futrts_ldexp16(f16 x, int32_t y) {
  return ldexp(x, y);
}

SCALAR_FUN_ATTR f16 futrts_copysign16(f16 x, f16 y) {
  return copysign(x, y);
}

SCALAR_FUN_ATTR f16 futrts_mad16(f16 a, f16 b, f16 c) {
  return mad(a, b, c);
}

SCALAR_FUN_ATTR f16 futrts_fma16(f16 a, f16 b, f16 c) {
  return fma(a, b, c);
}
#elif defined(ISPC)

SCALAR_FUN_ATTR f16 futrts_log16(f16 x) {
  return futrts_isfinite16(x) || (futrts_isinf16(x) && x < 0) ? log(x) : x;
}

SCALAR_FUN_ATTR f16 futrts_log2_16(f16 x) {
  return futrts_log16(x) / log(2.0f16);
}

SCALAR_FUN_ATTR f16 futrts_log10_16(f16 x) {
  return futrts_log16(x) / log(10.0f16);
}

SCALAR_FUN_ATTR f16 futrts_log1p_16(f16 x) {
  if(x == -1.0f16 || (futrts_isinf16(x) && x > 0.0f16)) return x / 0.0f16;
  f16 y = 1.0f16 + x;
  f16 z = y - 1.0f16;
  return log(y) - (z-x)/y;
}

SCALAR_FUN_ATTR f16 futrts_sqrt16(f16 x) {
  return (float16)sqrt((float)x);
}

SCALAR_FUN_ATTR f16 futrts_exp16(f16 x) {
  return exp(x);
}

SCALAR_FUN_ATTR f16 futrts_cos16(f16 x) {
  return (float16)cos((float)x);
}

SCALAR_FUN_ATTR f16 futrts_sin16(f16 x) {
  return (float16)sin((float)x);
}

SCALAR_FUN_ATTR f16 futrts_tan16(f16 x) {
  return (float16)tan((float)x);
}

SCALAR_FUN_ATTR f16 futrts_acos16(f16 x) {
  return (float16)acos((float)x);
}

SCALAR_FUN_ATTR f16 futrts_asin16(f16 x) {
  return (float16)asin((float)x);
}

SCALAR_FUN_ATTR f16 futrts_atan16(f16 x) {
  return (float16)atan((float)x);
}

SCALAR_FUN_ATTR f16 futrts_cosh16(f16 x) {
  return (exp(x)+exp(-x)) / 2.0f16;
}

SCALAR_FUN_ATTR f16 futrts_sinh16(f16 x) {
  return (exp(x)-exp(-x)) / 2.0f16;
}

SCALAR_FUN_ATTR f16 futrts_tanh16(f16 x) {
  return futrts_sinh16(x)/futrts_cosh16(x);
}

SCALAR_FUN_ATTR f16 futrts_acosh16(f16 x) {
  float16 f = x+(float16)sqrt((float)(x*x-1));
  if(futrts_isfinite16(f)) return log(f);
  return f;
}

SCALAR_FUN_ATTR f16 futrts_asinh16(f16 x) {
  float16 f = x+(float16)sqrt((float)(x*x+1));
  if(futrts_isfinite16(f)) return log(f);
  return f;
}

SCALAR_FUN_ATTR f16 futrts_atanh16(f16 x) {
  float16 f = (1+x)/(1-x);
  if(futrts_isfinite16(f)) return log(f)/2.0f16;
  return f;
}

SCALAR_FUN_ATTR f16 futrts_atan2_16(f16 x, f16 y) {
  return (float16)atan2((float)x, (float)y);
}

SCALAR_FUN_ATTR f16 futrts_hypot16(f16 x, f16 y) {
  return (float16)futrts_hypot32((float)x, (float)y);
}

extern "C" unmasked uniform float tgammaf(uniform float x);
SCALAR_FUN_ATTR f16 futrts_gamma16(f16 x) {
  f16 res;
  foreach_active (i) {
    uniform f16 r = (f16)tgammaf(extract((float)x, i));
    res = insert(res, i, r);
  }
  return res;
}

extern "C" unmasked uniform float lgammaf(uniform float x);
SCALAR_FUN_ATTR f16 futrts_lgamma16(f16 x) {
  f16 res;
  foreach_active (i) {
    uniform f16 r = (f16)lgammaf(extract((float)x, i));
    res = insert(res, i, r);
  }
  return res;
}

SCALAR_FUN_ATTR f16 futrts_cbrt16(f16 x) {
  f16 res = (f16)futrts_cbrt32((float)x);
  return res;
}

SCALAR_FUN_ATTR f16 futrts_erf16(f16 x) {
  f16 res = (f16)futrts_erf32((float)x);
  return res;
}

SCALAR_FUN_ATTR f16 futrts_erfc16(f16 x) {
  f16 res = (f16)futrts_erfc32((float)x);
  return res;
}

SCALAR_FUN_ATTR f16 fmod16(f16 x, f16 y) {
  return x - y * (float16)trunc((float) (x/y));
}

SCALAR_FUN_ATTR f16 futrts_round16(f16 x) {
  return (float16)round((float)x);
}

SCALAR_FUN_ATTR f16 futrts_floor16(f16 x) {
  return (float16)floor((float)x);
}

SCALAR_FUN_ATTR f16 futrts_ceil16(f16 x) {
  return (float16)ceil((float)x);
}

SCALAR_FUN_ATTR f16 futrts_nextafter16(f16 x, f16 y) {
  return (float16)futrts_nextafter32((float)x, (float) y);
}

SCALAR_FUN_ATTR f16 futrts_lerp16(f16 v0, f16 v1, f16 t) {
  return v0 + (v1 - v0) * t;
}

SCALAR_FUN_ATTR f16 futrts_ldexp16(f16 x, int32_t y) {
  return futrts_ldexp32((float)x, y);
}

SCALAR_FUN_ATTR f16 futrts_copysign16(f16 x, f16 y) {
  return futrts_copysign32((float)x, y);
}

SCALAR_FUN_ATTR f16 futrts_mad16(f16 a, f16 b, f16 c) {
  return a * b + c;
}

SCALAR_FUN_ATTR f16 futrts_fma16(f16 a, f16 b, f16 c) {
  return a * b + c;
}

#else  

SCALAR_FUN_ATTR f16 futrts_log16(f16 x) {
  return hlog(x);
}

SCALAR_FUN_ATTR f16 futrts_log2_16(f16 x) {
  return hlog2(x);
}

SCALAR_FUN_ATTR f16 futrts_log10_16(f16 x) {
  return hlog10(x);
}

SCALAR_FUN_ATTR f16 futrts_log1p_16(f16 x) {
  return (f16)log1pf((float)x);
}

SCALAR_FUN_ATTR f16 futrts_sqrt16(f16 x) {
  return hsqrt(x);
}

SCALAR_FUN_ATTR f16 futrts_cbrt16(f16 x) {
  return cbrtf(x);
}

SCALAR_FUN_ATTR f16 futrts_exp16(f16 x) {
  return hexp(x);
}

SCALAR_FUN_ATTR f16 futrts_cos16(f16 x) {
  return hcos(x);
}

SCALAR_FUN_ATTR f16 futrts_sin16(f16 x) {
  return hsin(x);
}

SCALAR_FUN_ATTR f16 futrts_tan16(f16 x) {
  return tanf(x);
}

SCALAR_FUN_ATTR f16 futrts_acos16(f16 x) {
  return acosf(x);
}

SCALAR_FUN_ATTR f16 futrts_asin16(f16 x) {
  return asinf(x);
}

SCALAR_FUN_ATTR f16 futrts_atan16(f16 x) {
  return atanf(x);
}

SCALAR_FUN_ATTR f16 futrts_cosh16(f16 x) {
  return coshf(x);
}

SCALAR_FUN_ATTR f16 futrts_sinh16(f16 x) {
  return sinhf(x);
}

SCALAR_FUN_ATTR f16 futrts_tanh16(f16 x) {
  return tanhf(x);
}

SCALAR_FUN_ATTR f16 futrts_acosh16(f16 x) {
  return acoshf(x);
}

SCALAR_FUN_ATTR f16 futrts_asinh16(f16 x) {
  return asinhf(x);
}

SCALAR_FUN_ATTR f16 futrts_atanh16(f16 x) {
  return atanhf(x);
}

SCALAR_FUN_ATTR f16 futrts_atan2_16(f16 x, f16 y) {
  return atan2f(x, y);
}

SCALAR_FUN_ATTR f16 futrts_hypot16(f16 x, f16 y) {
  return hypotf(x, y);
}

SCALAR_FUN_ATTR f16 futrts_gamma16(f16 x) {
  return tgammaf(x);
}

SCALAR_FUN_ATTR f16 futrts_lgamma16(f16 x) {
  return lgammaf(x);
}

SCALAR_FUN_ATTR f16 futrts_erf16(f16 x) {
  return erff(x);
}

SCALAR_FUN_ATTR f16 futrts_erfc16(f16 x) {
  return erfcf(x);
}

SCALAR_FUN_ATTR f16 fmod16(f16 x, f16 y) {
  return fmodf(x, y);
}

SCALAR_FUN_ATTR f16 futrts_round16(f16 x) {
  return rintf(x);
}

SCALAR_FUN_ATTR f16 futrts_floor16(f16 x) {
  return hfloor(x);
}

SCALAR_FUN_ATTR f16 futrts_ceil16(f16 x) {
  return hceil(x);
}

SCALAR_FUN_ATTR f16 futrts_nextafter16(f16 x, f16 y) {
  return __ushort_as_half(halfbitsnextafter(__half_as_ushort(x), __half_as_ushort(y)));
}

SCALAR_FUN_ATTR f16 futrts_lerp16(f16 v0, f16 v1, f16 t) {
  return v0 + (v1 - v0) * t;
}

SCALAR_FUN_ATTR f16 futrts_ldexp16(f16 x, int32_t y) {
  return futrts_ldexp32((float)x, y);
}

SCALAR_FUN_ATTR f16 futrts_copysign16(f16 x, f16 y) {
  return futrts_copysign32((float)x, y);
}

SCALAR_FUN_ATTR f16 futrts_mad16(f16 a, f16 b, f16 c) {
  return a * b + c;
}

SCALAR_FUN_ATTR f16 futrts_fma16(f16 a, f16 b, f16 c) {
  return fmaf(a, b, c);
}

#endif

 
 
#ifdef __CUDA_ARCH__
SCALAR_FUN_ATTR int16_t futrts_to_bits16(f16 x) {
  return __half_as_ushort(x);
}
SCALAR_FUN_ATTR f16 futrts_from_bits16(int16_t x) {
  return __ushort_as_half(x);
}
#elif defined(ISPC)

SCALAR_FUN_ATTR int16_t futrts_to_bits16(f16 x) {
  varying int16_t y = *((varying int16_t * uniform)&x);
  return y;
}

SCALAR_FUN_ATTR f16 futrts_from_bits16(int16_t x) {
  varying f16 y = *((varying f16 * uniform)&x);
  return y;
}
#else
SCALAR_FUN_ATTR int16_t futrts_to_bits16(f16 x) {
  union {
    f16 f;
    int16_t t;
  } p;

  p.f = x;
  return p.t;
}

SCALAR_FUN_ATTR f16 futrts_from_bits16(int16_t x) {
  union {
    int16_t f;
    f16 t;
  } p;

  p.f = x;
  return p.t;
}
#endif

#else  

SCALAR_FUN_ATTR f16 fabs16(f16 x) {
  return fabs32(x);
}

SCALAR_FUN_ATTR f16 fmax16(f16 x, f16 y) {
  return fmax32(x, y);
}

SCALAR_FUN_ATTR f16 fmin16(f16 x, f16 y) {
  return fmin32(x, y);
}

SCALAR_FUN_ATTR f16 fpow16(f16 x, f16 y) {
  return fpow32(x, y);
}

SCALAR_FUN_ATTR bool futrts_isnan16(f16 x) {
  return futrts_isnan32(x);
}

SCALAR_FUN_ATTR bool futrts_isinf16(f16 x) {
  return futrts_isinf32(x);
}

SCALAR_FUN_ATTR f16 futrts_log16(f16 x) {
  return futrts_log32(x);
}

SCALAR_FUN_ATTR f16 futrts_log2_16(f16 x) {
  return futrts_log2_32(x);
}

SCALAR_FUN_ATTR f16 futrts_log10_16(f16 x) {
  return futrts_log10_32(x);
}

SCALAR_FUN_ATTR f16 futrts_log1p_16(f16 x) {
  return futrts_log1p_32(x);
}

SCALAR_FUN_ATTR f16 futrts_sqrt16(f16 x) {
  return futrts_sqrt32(x);
}

SCALAR_FUN_ATTR f16 futrts_cbrt16(f16 x) {
  return futrts_cbrt32(x);
}

SCALAR_FUN_ATTR f16 futrts_exp16(f16 x) {
  return futrts_exp32(x);
}

SCALAR_FUN_ATTR f16 futrts_cos16(f16 x) {
  return futrts_cos32(x);
}

SCALAR_FUN_ATTR f16 futrts_sin16(f16 x) {
  return futrts_sin32(x);
}

SCALAR_FUN_ATTR f16 futrts_tan16(f16 x) {
  return futrts_tan32(x);
}

SCALAR_FUN_ATTR f16 futrts_acos16(f16 x) {
  return futrts_acos32(x);
}

SCALAR_FUN_ATTR f16 futrts_asin16(f16 x) {
  return futrts_asin32(x);
}

SCALAR_FUN_ATTR f16 futrts_atan16(f16 x) {
  return futrts_atan32(x);
}

SCALAR_FUN_ATTR f16 futrts_cosh16(f16 x) {
  return futrts_cosh32(x);
}

SCALAR_FUN_ATTR f16 futrts_sinh16(f16 x) {
  return futrts_sinh32(x);
}

SCALAR_FUN_ATTR f16 futrts_tanh16(f16 x) {
  return futrts_tanh32(x);
}

SCALAR_FUN_ATTR f16 futrts_acosh16(f16 x) {
  return futrts_acosh32(x);
}

SCALAR_FUN_ATTR f16 futrts_asinh16(f16 x) {
  return futrts_asinh32(x);
}

SCALAR_FUN_ATTR f16 futrts_atanh16(f16 x) {
  return futrts_atanh32(x);
}

SCALAR_FUN_ATTR f16 futrts_atan2_16(f16 x, f16 y) {
  return futrts_atan2_32(x, y);
}

SCALAR_FUN_ATTR f16 futrts_hypot16(f16 x, f16 y) {
  return futrts_hypot32(x, y);
}

SCALAR_FUN_ATTR f16 futrts_gamma16(f16 x) {
  return futrts_gamma32(x);
}

SCALAR_FUN_ATTR f16 futrts_lgamma16(f16 x) {
  return futrts_lgamma32(x);
}

SCALAR_FUN_ATTR f16 futrts_erf16(f16 x) {
  return futrts_erf32(x);
}

SCALAR_FUN_ATTR f16 futrts_erfc16(f16 x) {
  return futrts_erfc32(x);
}

SCALAR_FUN_ATTR f16 fmod16(f16 x, f16 y) {
  return fmod32(x, y);
}

SCALAR_FUN_ATTR f16 futrts_round16(f16 x) {
  return futrts_round32(x);
}

SCALAR_FUN_ATTR f16 futrts_floor16(f16 x) {
  return futrts_floor32(x);
}

SCALAR_FUN_ATTR f16 futrts_ceil16(f16 x) {
  return futrts_ceil32(x);
}

SCALAR_FUN_ATTR f16 futrts_nextafter16(f16 x, f16 y) {
  return halfbits2float(halfbitsnextafter(float2halfbits(x), float2halfbits(y)));
}

SCALAR_FUN_ATTR f16 futrts_lerp16(f16 v0, f16 v1, f16 t) {
  return futrts_lerp32(v0, v1, t);
}

SCALAR_FUN_ATTR f16 futrts_ldexp16(f16 x, int32_t y) {
  return futrts_ldexp32(x, y);
}

SCALAR_FUN_ATTR f16 futrts_copysign16(f16 x, f16 y) {
  return futrts_copysign32((float)x, y);
}

SCALAR_FUN_ATTR f16 futrts_mad16(f16 a, f16 b, f16 c) {
  return futrts_mad32(a, b, c);
}

SCALAR_FUN_ATTR f16 futrts_fma16(f16 a, f16 b, f16 c) {
  return futrts_fma32(a, b, c);
}

 
 
 
 
#ifdef __OPENCL_VERSION__

SCALAR_FUN_ATTR int16_t futrts_to_bits16(f16 x) {
  int16_t y;
   
  vstore_half((float)x, 0, (half*)&y);
  return y;
}

SCALAR_FUN_ATTR f16 futrts_from_bits16(int16_t x) {
  return (f16)vload_half(0, (half*)&x);
}

#else

SCALAR_FUN_ATTR int16_t futrts_to_bits16(f16 x) {
  return (int16_t)float2halfbits(x);
}

SCALAR_FUN_ATTR f16 futrts_from_bits16(int16_t x) {
  return halfbits2float((uint16_t)x);
}

SCALAR_FUN_ATTR f16 fsignum16(f16 x) {
  return futrts_isnan16(x) ? x : (x > 0 ? 1 : 0) - (x < 0 ? 1 : 0);
}

#endif

#endif

SCALAR_FUN_ATTR float fpconv_f16_f16(f16 x) {
  return x;
}

SCALAR_FUN_ATTR float fpconv_f16_f32(f16 x) {
  return x;
}

SCALAR_FUN_ATTR f16 fpconv_f32_f16(float x) {
  return (f16) x;
}

#ifdef FUTHARK_F64_ENABLED

SCALAR_FUN_ATTR double fpconv_f16_f64(f16 x) {
  return (double) x;
}

#if defined(ISPC)
SCALAR_FUN_ATTR f16 fpconv_f64_f16(double x) {
  return (f16) ((float)x);
}
#else
SCALAR_FUN_ATTR f16 fpconv_f64_f16(double x) {
  return (f16) x;
}
#endif
#endif


 

 
 
 
 

struct futhark_context_config;
struct futhark_context;

static void set_error(struct futhark_context* ctx, char *error);

 
 
static int init_constants(struct futhark_context*);
static int free_constants(struct futhark_context*);
static void setup_program(struct futhark_context* ctx);
static void teardown_program(struct futhark_context *ctx);

 
static void host_alloc(struct futhark_context* ctx, size_t size, const char* tag, size_t* size_out, void** mem_out);
 
static void host_free(struct futhark_context* ctx, size_t size, const char* tag, void* mem);

 
static void log_copy(struct futhark_context* ctx,
                     const char *kind, int r,
                     int64_t dst_offset, int64_t dst_strides[r],
                     int64_t src_offset, int64_t src_strides[r],
                     int64_t shape[r]);

static void log_transpose(struct futhark_context* ctx,
                          int64_t k, int64_t m, int64_t n);

static bool lmad_map_tr(int64_t *num_arrays_out, int64_t *n_out, int64_t *m_out,
                        int r,
                        const int64_t dst_strides[r],
                        const int64_t src_strides[r],
                        const int64_t shape[r]);

static bool lmad_contiguous(int r, int64_t strides[r], int64_t shape[r]);

static bool lmad_memcpyable(int r,
                            int64_t dst_strides[r], int64_t src_strides[r], int64_t shape[r]);

static void add_event(struct futhark_context* ctx,
                      const char* name,
                      char* description,
                      void* data,
                      event_report_fn f);

 
static void backend_context_config_setup(struct futhark_context_config* cfg);
static void backend_context_config_teardown(struct futhark_context_config* cfg);
static int backend_context_setup(struct futhark_context *ctx);
static void backend_context_teardown(struct futhark_context *ctx);

 

struct memblock {
    int *references;
    unsigned char *mem;
    int64_t size;
    const char *desc;
};
struct constants {
    int dummy;
};
struct tuning_params {
    int dummy;
};
static const int num_tuning_params = 0;
static const char *tuning_param_names[] = {NULL};
static const char *tuning_param_vars[] = {NULL};
static const char *tuning_param_classes[] = {NULL};
static int64_t tuning_param_defaults[] = {0};
 

struct futhark_context_config {
  int in_use;
  int debugging;
  int profiling;
  int logging;
  char *cache_fname;
  int num_tuning_params;
  int64_t *tuning_params;
  const char** tuning_param_names;
  const char** tuning_param_vars;
  const char** tuning_param_classes;
};

static void backend_context_config_setup(struct futhark_context_config* cfg) {
  (void)cfg;
}

static void backend_context_config_teardown(struct futhark_context_config* cfg) {
  (void)cfg;
}

int futhark_context_config_set_tuning_param(struct futhark_context_config* cfg, const char *param_name, size_t param_value) {
  (void)cfg; (void)param_name; (void)param_value;
  return 1;
}

struct futhark_context {
  struct futhark_context_config* cfg;
  int detail_memory;
  int debugging;
  int profiling;
  int profiling_paused;
  int logging;
  lock_t lock;
  char *error;
  lock_t error_lock;
  FILE *log;
  struct constants *constants;
  struct free_list free_list;
  struct event_list event_list;
  int64_t peak_mem_usage_default;
  int64_t cur_mem_usage_default;
  struct program* program;
  bool program_initialised;
};

int backend_context_setup(struct futhark_context* ctx) {
  (void)ctx;
  return 0;
}

void backend_context_teardown(struct futhark_context* ctx) {
  (void)ctx;
}

int futhark_context_sync(struct futhark_context* ctx) {
  (void)ctx;
  return 0;
}

 

struct program {
    int dummy;
};
static void setup_program(struct futhark_context *ctx)
{
    (void) ctx;
    
    int error = 0;
    
    (void) error;
    ctx->program = malloc(sizeof(struct program));
}
static void teardown_program(struct futhark_context *ctx)
{
    (void) ctx;
    
    int error = 0;
    
    (void) error;
    free(ctx->program);
}
static void set_tuning_params(struct futhark_context *ctx)
{
    (void) ctx;
}
int memblock_unref(struct futhark_context *ctx, struct memblock *block, const char *desc)
{
    if (block->references != NULL) {
        *block->references -= 1;
        if (ctx->detail_memory)
            fprintf(ctx->log, "Unreferencing block %s (allocated as %s) in %s: %d references remaining.\n", desc, block->desc, "default space", *block->references);
        if (*block->references == 0) {
            ctx->cur_mem_usage_default -= block->size;
            host_free(ctx, (size_t) block->size, desc, (void *) block->mem);
            free(block->references);
            if (ctx->detail_memory)
                fprintf(ctx->log, "%lld bytes freed (now allocated: %lld bytes)\n", (long long) block->size, (long long) ctx->cur_mem_usage_default);
        }
        block->references = NULL;
    }
    return 0;
}
int memblock_alloc(struct futhark_context *ctx, struct memblock *block, int64_t size, const char *desc)
{
    if (size < 0)
        futhark_panic(1, "Negative allocation of %lld bytes attempted for %s in %s.\n", (long long) size, desc, "default space", ctx->cur_mem_usage_default);
    
    int ret = memblock_unref(ctx, block, desc);
    
    if (ret != FUTHARK_SUCCESS)
        return ret;
    if (ctx->detail_memory)
        fprintf(ctx->log, "Allocating %lld bytes for %s in %s (currently allocated: %lld bytes).\n", (long long) size, desc, "default space", (long long) ctx->cur_mem_usage_default);
    host_alloc(ctx, (size_t) size, desc, (size_t *) &size, (void *) &block->mem);
    if (ctx->error == NULL) {
        block->references = (int *) malloc(sizeof(int));
        *block->references = 1;
        block->size = size;
        block->desc = desc;
        
        long long new_usage = ctx->cur_mem_usage_default + size;
        
        if (ctx->detail_memory)
            fprintf(ctx->log, "Received block of %lld bytes; now allocated: %lld bytes", (long long) block->size, new_usage);
        ctx->cur_mem_usage_default = new_usage;
        if (new_usage > ctx->peak_mem_usage_default) {
            ctx->peak_mem_usage_default = new_usage;
            if (ctx->detail_memory)
                fprintf(ctx->log, " (new peak).\n");
        } else if (ctx->detail_memory)
            fprintf(ctx->log, ".\n");
        return FUTHARK_SUCCESS;
    } else {
         
        lock_lock(&ctx->error_lock);
        
        char *old_error = ctx->error;
        
        ctx->error = msgprintf("Failed to allocate memory in %s.\nAttempted allocation: %12lld bytes\nCurrently allocated:  %12lld bytes\n%s", "default space", (long long) size, (long long) ctx->cur_mem_usage_default, old_error);
        free(old_error);
        lock_unlock(&ctx->error_lock);
        return FUTHARK_OUT_OF_MEMORY;
    }
}
int memblock_set(struct futhark_context *ctx, struct memblock *lhs, struct memblock *rhs, const char *lhs_desc)
{
    int ret = memblock_unref(ctx, lhs, lhs_desc);
    
    if (rhs->references != NULL)
        (*rhs->references)++;
    *lhs = *rhs;
    return ret;
}
char *futhark_context_report(struct futhark_context *ctx)
{
    if (futhark_context_sync(ctx) != 0)
        return NULL;
    
    struct str_builder builder;
    
    str_builder_init(&builder);
    str_builder_char(&builder, '{');
    str_builder_str(&builder, "\"memory\":{");
    str_builder(&builder, "\"default space\": %lld", (long long) ctx->peak_mem_usage_default);
    str_builder_str(&builder, "},\"events\":[");
    if (report_events_in_list(&ctx->event_list, &builder) != 0) {
        free(builder.str);
        return NULL;
    } else {
        str_builder_str(&builder, "]}");
        return builder.str;
    }
}
int futhark_context_clear_caches(struct futhark_context *ctx)
{
    lock_lock(&ctx->lock);
    ctx->peak_mem_usage_default = 0;
    lock_unlock(&ctx->lock);
    return ctx->error != NULL;
}

 

 

static void set_error(struct futhark_context* ctx, char *error) {
  lock_lock(&ctx->error_lock);
  if (ctx->error == NULL) {
    ctx->error = error;
  } else {
    free(error);
  }
  lock_unlock(&ctx->error_lock);
}

 
void lexical_realloc_error(struct futhark_context* ctx, size_t new_size) {
  set_error(ctx,
            msgprintf("Failed to allocate memory.\nAttempted allocation: %12lld bytes\n",
                      (long long) new_size));
}

static int lexical_realloc(struct futhark_context *ctx,
                           unsigned char **ptr,
                           int64_t *old_size,
                           int64_t new_size) {
  unsigned char *new = realloc(*ptr, (size_t)new_size);
  if (new == NULL) {
    lexical_realloc_error(ctx, new_size);
    return FUTHARK_OUT_OF_MEMORY;
  } else {
    *ptr = new;
    *old_size = new_size;
    return FUTHARK_SUCCESS;
  }
}

static void free_all_in_free_list(struct futhark_context* ctx) {
  fl_mem mem;
  free_list_pack(&ctx->free_list);
  while (free_list_first(&ctx->free_list, (fl_mem*)&mem) == 0) {
    free((void*)mem);
  }
}

static int is_small_alloc(size_t size) {
  return size < 1024*1024;
}

static void host_alloc(struct futhark_context* ctx,
                       size_t size, const char* tag, size_t* size_out, void** mem_out) {
  if (is_small_alloc(size) || free_list_find(&ctx->free_list, size, tag, size_out, (fl_mem*)mem_out) != 0) {
    *size_out = size;
    *mem_out = malloc(size);
  }
}

static void host_free(struct futhark_context* ctx,
                      size_t size, const char* tag, void* mem) {
   
   
   
   
   
  if (is_small_alloc(size)) {
    free(mem);
  } else {
    free_list_insert(&ctx->free_list, size, (fl_mem)mem, tag);
  }
}

static void add_event(struct futhark_context* ctx,
                      const char* name,
                      char* description,
                      void* data,
                      event_report_fn f) {
  if (ctx->logging) {
    fprintf(ctx->log, "Event: %s\n%s\n", name, description);
  }
  add_event_to_list(&ctx->event_list, name, description, data, f);
}

char *futhark_context_get_error(struct futhark_context *ctx) {
  char *error = ctx->error;
  ctx->error = NULL;
  return error;
}

void futhark_context_config_set_debugging(struct futhark_context_config *cfg, int flag) {
    cfg->profiling = cfg->logging = cfg->debugging = flag;
}

void futhark_context_config_set_profiling(struct futhark_context_config *cfg, int flag) {
    cfg->profiling = flag;
}

void futhark_context_config_set_logging(struct futhark_context_config *cfg, int flag) {
    cfg->logging = flag;
}

void futhark_context_config_set_cache_file(struct futhark_context_config *cfg, const char *f) {
  cfg->cache_fname = strdup(f);
}

int futhark_get_tuning_param_count(void) {
  return num_tuning_params;
}

const char *futhark_get_tuning_param_name(int i) {
  return tuning_param_names[i];
}

const char *futhark_get_tuning_param_class(int i) {
    return tuning_param_classes[i];
}

void futhark_context_set_logging_file(struct futhark_context *ctx, FILE *f){
  ctx->log = f;
}

void futhark_context_pause_profiling(struct futhark_context *ctx) {
  ctx->profiling_paused = 1;
}

void futhark_context_unpause_profiling(struct futhark_context *ctx) {
  ctx->profiling_paused = 0;
}

struct futhark_context_config* futhark_context_config_new(void) {
  struct futhark_context_config* cfg = malloc(sizeof(struct futhark_context_config));
  if (cfg == NULL) {
    return NULL;
  }
  cfg->in_use = 0;
  cfg->debugging = 0;
  cfg->profiling = 0;
  cfg->logging = 0;
  cfg->cache_fname = NULL;
  cfg->num_tuning_params = num_tuning_params;
  cfg->tuning_params = malloc(cfg->num_tuning_params * sizeof(int64_t));
  memcpy(cfg->tuning_params, tuning_param_defaults,
         cfg->num_tuning_params * sizeof(int64_t));
  cfg->tuning_param_names = tuning_param_names;
  cfg->tuning_param_vars = tuning_param_vars;
  cfg->tuning_param_classes = tuning_param_classes;
  backend_context_config_setup(cfg);
  return cfg;
}

void futhark_context_config_free(struct futhark_context_config* cfg) {
  assert(!cfg->in_use);
  backend_context_config_teardown(cfg);
  free(cfg->cache_fname);
  free(cfg->tuning_params);
  free(cfg);
}

struct futhark_context* futhark_context_new(struct futhark_context_config* cfg) {
  struct futhark_context* ctx = malloc(sizeof(struct futhark_context));
  if (ctx == NULL) {
    return NULL;
  }
  assert(!cfg->in_use);
  ctx->cfg = cfg;
  ctx->cfg->in_use = 1;
  ctx->program_initialised = false;
  create_lock(&ctx->error_lock);
  create_lock(&ctx->lock);
  free_list_init(&ctx->free_list);
  event_list_init(&ctx->event_list);
  ctx->peak_mem_usage_default = 0;
  ctx->cur_mem_usage_default = 0;
  ctx->constants = malloc(sizeof(struct constants));
  ctx->debugging = cfg->debugging;
  ctx->logging = cfg->logging;
  ctx->detail_memory = cfg->logging;
  ctx->profiling = cfg->profiling;
  ctx->profiling_paused = 0;
  ctx->error = NULL;
  ctx->log = stderr;
  set_tuning_params(ctx);
  if (backend_context_setup(ctx) == 0) {
    setup_program(ctx);
    init_constants(ctx);
    ctx->program_initialised = true;
    (void)futhark_context_clear_caches(ctx);
    (void)futhark_context_sync(ctx);
  }
  return ctx;
}

void futhark_context_free(struct futhark_context* ctx) {
  if (ctx->program_initialised) {
    free_constants(ctx);
    teardown_program(ctx);
  }
  backend_context_teardown(ctx);
  free_all_in_free_list(ctx);
  free_list_destroy(&ctx->free_list);
  event_list_free(&ctx->event_list);
  free(ctx->constants);
  free(ctx->error);
  free_lock(&ctx->lock);
  free_lock(&ctx->error_lock);
  ctx->cfg->in_use = 0;
  free(ctx);
}

 

 

 
#define GEN_MAP_TRANSPOSE(NAME, ELEM_TYPE)                              \
  static void map_transpose_##NAME                                      \
  (ELEM_TYPE* dst, ELEM_TYPE* src,                                      \
   int64_t k, int64_t m, int64_t n,                                     \
   int64_t cb, int64_t ce, int64_t rb, int64_t re)                      \
  {                                                                     \
  int32_t r = re - rb;                                                  \
  int32_t c = ce - cb;                                                  \
  if (k == 1) {                                                         \
    if (r <= 64 && c <= 64) {                                           \
      for (int64_t j = 0; j < c; j++) {                                 \
        for (int64_t i = 0; i < r; i++) {                               \
          dst[(j + cb) * n + (i + rb)] = src[(i + rb) * m + (j + cb)];  \
        }                                                               \
      }                                                                 \
    } else if (c <= r) {                                                \
      map_transpose_##NAME(dst, src, k, m, n, cb, ce, rb, rb + r/2);    \
      map_transpose_##NAME(dst, src, k, m, n, cb, ce, rb + r/2, re);    \
    } else {                                                            \
      map_transpose_##NAME(dst, src, k, m, n, cb, cb + c/2, rb, re);    \
      map_transpose_##NAME(dst, src, k, m, n, cb + c/2, ce, rb, re);    \
    }                                                                   \
  } else {                                                              \
  for (int64_t i = 0; i < k; i++) {                                     \
    map_transpose_##NAME(dst + i * m * n, src + i * m * n, 1, m, n, cb, ce, rb, re); \
  }\
} \
}

 
#define GEN_LMAD_COPY_ELEMENTS(NAME, ELEM_TYPE)                         \
  static void lmad_copy_elements_##NAME(int r,                          \
                                        ELEM_TYPE* dst, int64_t dst_strides[r], \
                                        ELEM_TYPE *src, int64_t src_strides[r], \
                                        int64_t shape[r]) {             \
    if (r == 1) {                                                       \
      for (int i = 0; i < shape[0]; i++) {                              \
        dst[i*dst_strides[0]] = src[i*src_strides[0]];                  \
      }                                                                 \
    } else if (r > 1) {                                                 \
      for (int i = 0; i < shape[0]; i++) {                              \
        lmad_copy_elements_##NAME(r-1,                                  \
                                  dst+i*dst_strides[0], dst_strides+1,  \
                                  src+i*src_strides[0], src_strides+1,  \
                                  shape+1);                             \
      }                                                                 \
    }                                                                   \
  }                                                                     \

 
 
static bool lmad_is_tr(int64_t *n_out, int64_t *m_out,
                       int r,
                       const int64_t strides[r],
                       const int64_t shape[r]) {
  for (int i = 1; i < r; i++) {
    int n = 1, m = 1;
    bool ok = true;
    int64_t expected = 1;
     
    for (int j = i-1; j >= 0; j--) {
      ok = ok && strides[j] == expected;
      expected *= shape[j];
      n *= shape[j];
    }
     
    for (int j = r-1; j >= i; j--) {
      ok = ok && strides[j] == expected;
      expected *= shape[j];
      m *= shape[j];
    }
    if (ok) {
      *n_out = n;
      *m_out = m;
      return true;
    }
  }
  return false;
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
static bool lmad_map_tr(int64_t *num_arrays_out, int64_t *n_out, int64_t *m_out,
                        int r,
                        const int64_t dst_strides[r],
                        const int64_t src_strides[r],
                        const int64_t shape[r]) {
  int64_t rowmajor_strides[r];
  rowmajor_strides[r-1] = 1;

  for (int i = r-2; i >= 0; i--) {
    rowmajor_strides[i] = rowmajor_strides[i+1] * shape[i+1];
  }

   
  int map_r = 0;
  int64_t num_arrays = 1;
  for (int i = 0; i < r; i++) {
    if (dst_strides[i] != rowmajor_strides[i] ||
        src_strides[i] != rowmajor_strides[i]) {
      break;
    } else {
      num_arrays *= shape[i];
      map_r++;
    }
  }

  *num_arrays_out = num_arrays;

  if (r==map_r) {
    return false;
  }

  if (memcmp(&rowmajor_strides[map_r],
             &dst_strides[map_r],
             sizeof(int64_t)*(r-map_r)) == 0) {
    return lmad_is_tr(n_out, m_out, r-map_r, src_strides+map_r, shape+map_r);
  } else if (memcmp(&rowmajor_strides[map_r],
                    &src_strides[map_r],
                    sizeof(int64_t)*(r-map_r)) == 0) {
    return lmad_is_tr(m_out, n_out, r-map_r, dst_strides+map_r, shape+map_r);
  }
  return false;
}

 
 
 
 
static bool lmad_contiguous_search(int checked, int64_t expected,
                                   int r,
                                   int64_t strides[r], int64_t shape[r], bool used[r]) {
  for (int i = 0; i < r; i++) {
    for (int j = 0; j < r; j++) {
      if (!used[j] && strides[j] == expected && strides[j] >= 0) {
        used[j] = true;
        if (checked+1 == r ||
            lmad_contiguous_search(checked+1, expected * shape[j], r, strides, shape, used)) {
          return true;
        }
        used[j] = false;
      }
    }
  }
  return false;
}

 
 
static bool lmad_contiguous(int r, int64_t strides[r], int64_t shape[r]) {
  bool used[r];
  for (int i = 0; i < r; i++) {
    used[i] = false;
  }
  return lmad_contiguous_search(0, 1, r, strides, shape, used);
}

 
 
 
static bool lmad_memcpyable(int r,
                            int64_t dst_strides[r], int64_t src_strides[r], int64_t shape[r]) {
  if (!lmad_contiguous(r, dst_strides, shape)) {
    return false;
  }
  for (int i = 0; i < r; i++) {
    if (dst_strides[i] != src_strides[i] && shape[i] != 1) {
      return false;
    }
  }
  return true;
}


static void log_copy(struct futhark_context* ctx,
                     const char *kind, int r,
                     int64_t dst_offset, int64_t dst_strides[r],
                     int64_t src_offset, int64_t src_strides[r],
                     int64_t shape[r]) {
  if (ctx->logging) {
    fprintf(ctx->log, "\n# Copy %s\n", kind);
    fprintf(ctx->log, "Shape: ");
    for (int i = 0; i < r; i++) { fprintf(ctx->log, "[%ld]", (long int)shape[i]); }
    fprintf(ctx->log, "\n");
    fprintf(ctx->log, "Dst offset: %ld\n", (long int)dst_offset);
    fprintf(ctx->log, "Dst strides:");
    for (int i = 0; i < r; i++) { fprintf(ctx->log, " %ld", (long int)dst_strides[i]); }
    fprintf(ctx->log, "\n");
    fprintf(ctx->log, "Src offset: %ld\n", (long int)src_offset);
    fprintf(ctx->log, "Src strides:");
    for (int i = 0; i < r; i++) { fprintf(ctx->log, " %ld", (long int)src_strides[i]); }
    fprintf(ctx->log, "\n");
  }
}

static void log_transpose(struct futhark_context* ctx,
                          int64_t k, int64_t n, int64_t m) {
  if (ctx->logging) {
    fprintf(ctx->log, "## Transpose\n");
    fprintf(ctx->log, "Arrays     : %ld\n", (long int)k);
    fprintf(ctx->log, "X elements : %ld\n", (long int)m);
    fprintf(ctx->log, "Y elements : %ld\n", (long int)n);
    fprintf(ctx->log, "\n");
  }
}

#define GEN_LMAD_COPY(NAME, ELEM_TYPE)                                  \
  static void lmad_copy_##NAME                                          \
  (struct futhark_context *ctx, int r,                                  \
   ELEM_TYPE* dst, int64_t dst_offset, int64_t dst_strides[r],          \
   ELEM_TYPE *src, int64_t src_offset, int64_t src_strides[r],          \
   int64_t shape[r]) {                                                  \
    log_copy(ctx, "CPU to CPU", r, dst_offset, dst_strides,             \
             src_offset, src_strides, shape);                           \
    int64_t size = 1;                                                   \
    for (int i = 0; i < r; i++) { size *= shape[i]; }                   \
    if (size == 0) { return; }                                          \
    int64_t k, n, m;                                                    \
    if (lmad_map_tr(&k, &n, &m,                                         \
                    r, dst_strides, src_strides, shape)) {              \
      log_transpose(ctx, k, n, m);                                      \
      map_transpose_##NAME                                              \
        (dst+dst_offset, src+src_offset, k, n, m, 0, n, 0, m);          \
    } else if (lmad_memcpyable(r, dst_strides, src_strides, shape)) {   \
      if (ctx->logging) {fprintf(ctx->log, "## Flat copy\n\n");}          \
      memcpy(dst+dst_offset, src+src_offset, size*sizeof(*dst));        \
    } else {                                                            \
      if (ctx->logging) {fprintf(ctx->log, "## General copy\n\n");}       \
      lmad_copy_elements_##NAME                                         \
        (r,                                                             \
         dst+dst_offset, dst_strides,                                   \
         src+src_offset, src_strides, shape);                           \
    }                                                                   \
  }

GEN_MAP_TRANSPOSE(1b, uint8_t)
GEN_MAP_TRANSPOSE(2b, uint16_t)
GEN_MAP_TRANSPOSE(4b, uint32_t)
GEN_MAP_TRANSPOSE(8b, uint64_t)

GEN_LMAD_COPY_ELEMENTS(1b, uint8_t)
GEN_LMAD_COPY_ELEMENTS(2b, uint16_t)
GEN_LMAD_COPY_ELEMENTS(4b, uint32_t)
GEN_LMAD_COPY_ELEMENTS(8b, uint64_t)

GEN_LMAD_COPY(1b, uint8_t)
GEN_LMAD_COPY(2b, uint16_t)
GEN_LMAD_COPY(4b, uint32_t)
GEN_LMAD_COPY(8b, uint64_t)

 

#define FUTHARK_FUN_ATTR static

FUTHARK_FUN_ATTR int futrts_entry_all_positive(struct futhark_context *ctx, bool *out_prim_out_10801, struct memblock arr_mem_10744, int64_t n_10161);
FUTHARK_FUN_ATTR int futrts_entry_any_positive(struct futhark_context *ctx, bool *out_prim_out_10802, struct memblock arr_mem_10744, int64_t n_10109);
FUTHARK_FUN_ATTR int futrts_entry_convolve_1d(struct futhark_context *ctx, struct memblock *mem_out_p_10803, int64_t *out_prim_out_10804, struct memblock signal_mem_10744, struct memblock kernel_mem_10745, int64_t n_8287, int64_t k_8288);
FUTHARK_FUN_ATTR int futrts_entry_cosine_similarity(struct futhark_context *ctx, double *out_prim_out_10805, struct memblock a_mem_10744, struct memblock b_mem_10745, int64_t n_9428);
FUTHARK_FUN_ATTR int futrts_entry_exponential_moving_average(struct futhark_context *ctx, struct memblock *mem_out_p_10806, struct memblock arr_mem_10744, int64_t n_9965, double alpha_9967);
FUTHARK_FUN_ATTR int futrts_entry_find_max(struct futhark_context *ctx, bool *out_prim_out_10807, int64_t *out_prim_out_10808, struct memblock arr_mem_10744, int64_t n_8597);
FUTHARK_FUN_ATTR int futrts_entry_find_min(struct futhark_context *ctx, bool *out_prim_out_10809, int64_t *out_prim_out_10810, struct memblock arr_mem_10744, int64_t n_8630);
FUTHARK_FUN_ATTR int futrts_entry_flatten_3d_array(struct futhark_context *ctx, struct memblock *mem_out_p_10811, int64_t *out_prim_out_10812, struct memblock arr_mem_10744, int64_t n_10054, int64_t m_10055, int64_t l_10056);
FUTHARK_FUN_ATTR int futrts_entry_gather(struct futhark_context *ctx, struct memblock *mem_out_p_10813, struct memblock src_mem_10744, struct memblock indices_mem_10745, int64_t n_8345, int64_t m_8346, int64_t fill_8349);
FUTHARK_FUN_ATTR int futrts_entry_histogram(struct futhark_context *ctx, struct memblock *mem_out_p_10814, int64_t *out_prim_out_10815, struct memblock arr_mem_10744, int64_t n_7985, int64_t num_bins_7987);
FUTHARK_FUN_ATTR int futrts_entry_min_max_normalizze(struct futhark_context *ctx, struct memblock *mem_out_p_10816, struct memblock arr_mem_10744, int64_t n_8800);
FUTHARK_FUN_ATTR int futrts_entry_moving_average(struct futhark_context *ctx, struct memblock *mem_out_p_10817, int64_t *out_prim_out_10818, struct memblock arr_mem_10744, int64_t n_8115, int64_t window_8117);
FUTHARK_FUN_ATTR int futrts_entry_partition_array(struct futhark_context *ctx, struct memblock *mem_out_p_10819, struct memblock *mem_out_p_10820, int64_t *out_prim_out_10821, int64_t *out_prim_out_10822, struct memblock arr_mem_10744, int64_t n_9779, int64_t pivot_9781);
FUTHARK_FUN_ATTR int futrts_entry_population_variance_array(struct futhark_context *ctx, double *out_prim_out_10826, struct memblock arr_mem_10744, int64_t n_9516);
FUTHARK_FUN_ATTR int futrts_entry_scatter_array(struct futhark_context *ctx, struct memblock *mem_out_p_10827, struct memblock dest_mem_10744, struct memblock indices_mem_10745, struct memblock values_mem_10746, int64_t n_8562, int64_t m_8563);
FUTHARK_FUN_ATTR int futrts_entry_softmax(struct futhark_context *ctx, struct memblock *mem_out_p_10829, struct memblock arr_mem_10744, int64_t n_9032);
FUTHARK_FUN_ATTR int futrts_entry_std_dev_array(struct futhark_context *ctx, double *out_prim_out_10832, struct memblock arr_mem_10744, int64_t n_9617);
FUTHARK_FUN_ATTR int futrts_entry_sum_matrix(struct futhark_context *ctx, double *out_prim_out_10833, struct memblock mat_mem_10744, int64_t n_10008, int64_t m_10009);
FUTHARK_FUN_ATTR int futrts_entry_update_array(struct futhark_context *ctx, struct memblock *mem_out_p_10834, struct memblock arr_mem_10744, int64_t n_8376, int64_t index_8378, int64_t value_8379);
FUTHARK_FUN_ATTR int futrts_entry_update_matrix(struct futhark_context *ctx, struct memblock *mem_out_p_10835, struct memblock mat_mem_10744, int64_t n_8417, int64_t m_8418, int64_t row_8420, int64_t col_8421, int64_t value_8422);
FUTHARK_FUN_ATTR int futrts_entry_variance_array(struct futhark_context *ctx, double *out_prim_out_10836, struct memblock arr_mem_10744, int64_t n_9605);
FUTHARK_FUN_ATTR int futrts_is_finite_value_4544(struct futhark_context *ctx, bool *out_prim_out_10837, double x_8641);

static int init_constants(struct futhark_context *ctx)
{
    (void) ctx;
    
    int err = 0;
    
    
  cleanup:
    return err;
}
static int free_constants(struct futhark_context *ctx)
{
    (void) ctx;
    return 0;
}
struct futhark_i64_1d {
    struct memblock mem;
    int64_t shape[1];
};
struct futhark_i64_1d *futhark_new_i64_1d(struct futhark_context *ctx, const int64_t *data, int64_t dim0)
{
    int err = 0;
    struct futhark_i64_1d *bad = NULL;
    struct futhark_i64_1d *arr = (struct futhark_i64_1d *) malloc(sizeof(struct futhark_i64_1d));
    
    if (arr == NULL)
        return bad;
    lock_lock(&ctx->lock);
    arr->mem.references = NULL;
    if (memblock_alloc(ctx, &arr->mem, dim0 * 8, "arr->mem"))
        err = 1;
    arr->shape[0] = dim0;
    if ((size_t) dim0 * 8 > 0)
        memmove(arr->mem.mem + 0, (const unsigned char *) data + 0, (size_t) dim0 * 8);
    lock_unlock(&ctx->lock);
    if (err != 0) {
        free(arr);
        return bad;
    }
    return arr;
}
struct futhark_i64_1d *futhark_new_raw_i64_1d(struct futhark_context *ctx, unsigned char *data, int64_t dim0)
{
    int err = 0;
    struct futhark_i64_1d *bad = NULL;
    struct futhark_i64_1d *arr = (struct futhark_i64_1d *) malloc(sizeof(struct futhark_i64_1d));
    
    if (arr == NULL)
        return bad;
    lock_lock(&ctx->lock);
    arr->mem.references = NULL;
    arr->mem.mem = data;
    arr->shape[0] = dim0;
    lock_unlock(&ctx->lock);
    return arr;
}
int futhark_free_i64_1d(struct futhark_context *ctx, struct futhark_i64_1d *arr)
{
    lock_lock(&ctx->lock);
    if (memblock_unref(ctx, &arr->mem, "arr->mem") != 0)
        return 1;
    lock_unlock(&ctx->lock);
    free(arr);
    return 0;
}
int futhark_values_i64_1d(struct futhark_context *ctx, struct futhark_i64_1d *arr, int64_t *data)
{
    int err = 0;
    
    lock_lock(&ctx->lock);
    if ((size_t) arr->shape[0] * 8 > 0)
        memmove((unsigned char *) data + 0, arr->mem.mem + 0, (size_t) arr->shape[0] * 8);
    lock_unlock(&ctx->lock);
    return err;
}
int futhark_index_i64_1d(struct futhark_context *ctx, int64_t *out, struct futhark_i64_1d *arr, int64_t i0)
{
    int err = 0;
    
    if (i0 >= 0 && i0 < arr->shape[0]) {
        lock_lock(&ctx->lock);
        if (8 > 0)
            memmove((unsigned char *) out + 0, arr->mem.mem + 8 * (i0 * 1), 8);
        lock_unlock(&ctx->lock);
    } else {
        err = 1;
        set_error(ctx, strdup("Index out of bounds."));
    }
    return err;
}
unsigned char *futhark_values_raw_i64_1d(struct futhark_context *ctx, struct futhark_i64_1d *arr)
{
    (void) ctx;
    return arr->mem.mem;
}
const int64_t *futhark_shape_i64_1d(struct futhark_context *ctx, struct futhark_i64_1d *arr)
{
    (void) ctx;
    return arr->shape;
}
struct futhark_i64_2d {
    struct memblock mem;
    int64_t shape[2];
};
struct futhark_i64_2d *futhark_new_i64_2d(struct futhark_context *ctx, const int64_t *data, int64_t dim0, int64_t dim1)
{
    int err = 0;
    struct futhark_i64_2d *bad = NULL;
    struct futhark_i64_2d *arr = (struct futhark_i64_2d *) malloc(sizeof(struct futhark_i64_2d));
    
    if (arr == NULL)
        return bad;
    lock_lock(&ctx->lock);
    arr->mem.references = NULL;
    if (memblock_alloc(ctx, &arr->mem, dim0 * dim1 * 8, "arr->mem"))
        err = 1;
    arr->shape[0] = dim0;
    arr->shape[1] = dim1;
    if ((size_t) (dim0 * dim1) * 8 > 0)
        memmove(arr->mem.mem + 0, (const unsigned char *) data + 0, (size_t) (dim0 * dim1) * 8);
    lock_unlock(&ctx->lock);
    if (err != 0) {
        free(arr);
        return bad;
    }
    return arr;
}
struct futhark_i64_2d *futhark_new_raw_i64_2d(struct futhark_context *ctx, unsigned char *data, int64_t dim0, int64_t dim1)
{
    int err = 0;
    struct futhark_i64_2d *bad = NULL;
    struct futhark_i64_2d *arr = (struct futhark_i64_2d *) malloc(sizeof(struct futhark_i64_2d));
    
    if (arr == NULL)
        return bad;
    lock_lock(&ctx->lock);
    arr->mem.references = NULL;
    arr->mem.mem = data;
    arr->shape[0] = dim0;
    arr->shape[1] = dim1;
    lock_unlock(&ctx->lock);
    return arr;
}
int futhark_free_i64_2d(struct futhark_context *ctx, struct futhark_i64_2d *arr)
{
    lock_lock(&ctx->lock);
    if (memblock_unref(ctx, &arr->mem, "arr->mem") != 0)
        return 1;
    lock_unlock(&ctx->lock);
    free(arr);
    return 0;
}
int futhark_values_i64_2d(struct futhark_context *ctx, struct futhark_i64_2d *arr, int64_t *data)
{
    int err = 0;
    
    lock_lock(&ctx->lock);
    if ((size_t) (arr->shape[0] * arr->shape[1]) * 8 > 0)
        memmove((unsigned char *) data + 0, arr->mem.mem + 0, (size_t) (arr->shape[0] * arr->shape[1]) * 8);
    lock_unlock(&ctx->lock);
    return err;
}
int futhark_index_i64_2d(struct futhark_context *ctx, int64_t *out, struct futhark_i64_2d *arr, int64_t i0, int64_t i1)
{
    int err = 0;
    
    if ((i0 >= 0 && i0 < arr->shape[0]) && (i1 >= 0 && i1 < arr->shape[1])) {
        lock_lock(&ctx->lock);
        if (8 > 0)
            memmove((unsigned char *) out + 0, arr->mem.mem + 8 * (i0 * arr->shape[1] + i1 * 1), 8);
        lock_unlock(&ctx->lock);
    } else {
        err = 1;
        set_error(ctx, strdup("Index out of bounds."));
    }
    return err;
}
unsigned char *futhark_values_raw_i64_2d(struct futhark_context *ctx, struct futhark_i64_2d *arr)
{
    (void) ctx;
    return arr->mem.mem;
}
const int64_t *futhark_shape_i64_2d(struct futhark_context *ctx, struct futhark_i64_2d *arr)
{
    (void) ctx;
    return arr->shape;
}
struct futhark_i64_3d {
    struct memblock mem;
    int64_t shape[3];
};
struct futhark_i64_3d *futhark_new_i64_3d(struct futhark_context *ctx, const int64_t *data, int64_t dim0, int64_t dim1, int64_t dim2)
{
    int err = 0;
    struct futhark_i64_3d *bad = NULL;
    struct futhark_i64_3d *arr = (struct futhark_i64_3d *) malloc(sizeof(struct futhark_i64_3d));
    
    if (arr == NULL)
        return bad;
    lock_lock(&ctx->lock);
    arr->mem.references = NULL;
    if (memblock_alloc(ctx, &arr->mem, dim0 * dim1 * dim2 * 8, "arr->mem"))
        err = 1;
    arr->shape[0] = dim0;
    arr->shape[1] = dim1;
    arr->shape[2] = dim2;
    if ((size_t) (dim0 * dim1 * dim2) * 8 > 0)
        memmove(arr->mem.mem + 0, (const unsigned char *) data + 0, (size_t) (dim0 * dim1 * dim2) * 8);
    lock_unlock(&ctx->lock);
    if (err != 0) {
        free(arr);
        return bad;
    }
    return arr;
}
struct futhark_i64_3d *futhark_new_raw_i64_3d(struct futhark_context *ctx, unsigned char *data, int64_t dim0, int64_t dim1, int64_t dim2)
{
    int err = 0;
    struct futhark_i64_3d *bad = NULL;
    struct futhark_i64_3d *arr = (struct futhark_i64_3d *) malloc(sizeof(struct futhark_i64_3d));
    
    if (arr == NULL)
        return bad;
    lock_lock(&ctx->lock);
    arr->mem.references = NULL;
    arr->mem.mem = data;
    arr->shape[0] = dim0;
    arr->shape[1] = dim1;
    arr->shape[2] = dim2;
    lock_unlock(&ctx->lock);
    return arr;
}
int futhark_free_i64_3d(struct futhark_context *ctx, struct futhark_i64_3d *arr)
{
    lock_lock(&ctx->lock);
    if (memblock_unref(ctx, &arr->mem, "arr->mem") != 0)
        return 1;
    lock_unlock(&ctx->lock);
    free(arr);
    return 0;
}
int futhark_values_i64_3d(struct futhark_context *ctx, struct futhark_i64_3d *arr, int64_t *data)
{
    int err = 0;
    
    lock_lock(&ctx->lock);
    if ((size_t) (arr->shape[0] * arr->shape[1] * arr->shape[2]) * 8 > 0)
        memmove((unsigned char *) data + 0, arr->mem.mem + 0, (size_t) (arr->shape[0] * arr->shape[1] * arr->shape[2]) * 8);
    lock_unlock(&ctx->lock);
    return err;
}
int futhark_index_i64_3d(struct futhark_context *ctx, int64_t *out, struct futhark_i64_3d *arr, int64_t i0, int64_t i1, int64_t i2)
{
    int err = 0;
    
    if ((i0 >= 0 && i0 < arr->shape[0]) && ((i1 >= 0 && i1 < arr->shape[1]) && (i2 >= 0 && i2 < arr->shape[2]))) {
        lock_lock(&ctx->lock);
        if (8 > 0)
            memmove((unsigned char *) out + 0, arr->mem.mem + 8 * (i0 * (arr->shape[1] * arr->shape[2]) + i1 * arr->shape[2] + i2 * 1), 8);
        lock_unlock(&ctx->lock);
    } else {
        err = 1;
        set_error(ctx, strdup("Index out of bounds."));
    }
    return err;
}
unsigned char *futhark_values_raw_i64_3d(struct futhark_context *ctx, struct futhark_i64_3d *arr)
{
    (void) ctx;
    return arr->mem.mem;
}
const int64_t *futhark_shape_i64_3d(struct futhark_context *ctx, struct futhark_i64_3d *arr)
{
    (void) ctx;
    return arr->shape;
}
struct futhark_f64_1d {
    struct memblock mem;
    int64_t shape[1];
};
struct futhark_f64_1d *futhark_new_f64_1d(struct futhark_context *ctx, const double *data, int64_t dim0)
{
    int err = 0;
    struct futhark_f64_1d *bad = NULL;
    struct futhark_f64_1d *arr = (struct futhark_f64_1d *) malloc(sizeof(struct futhark_f64_1d));
    
    if (arr == NULL)
        return bad;
    lock_lock(&ctx->lock);
    arr->mem.references = NULL;
    if (memblock_alloc(ctx, &arr->mem, dim0 * 8, "arr->mem"))
        err = 1;
    arr->shape[0] = dim0;
    if ((size_t) dim0 * 8 > 0)
        memmove(arr->mem.mem + 0, (const unsigned char *) data + 0, (size_t) dim0 * 8);
    lock_unlock(&ctx->lock);
    if (err != 0) {
        free(arr);
        return bad;
    }
    return arr;
}
struct futhark_f64_1d *futhark_new_raw_f64_1d(struct futhark_context *ctx, unsigned char *data, int64_t dim0)
{
    int err = 0;
    struct futhark_f64_1d *bad = NULL;
    struct futhark_f64_1d *arr = (struct futhark_f64_1d *) malloc(sizeof(struct futhark_f64_1d));
    
    if (arr == NULL)
        return bad;
    lock_lock(&ctx->lock);
    arr->mem.references = NULL;
    arr->mem.mem = data;
    arr->shape[0] = dim0;
    lock_unlock(&ctx->lock);
    return arr;
}
int futhark_free_f64_1d(struct futhark_context *ctx, struct futhark_f64_1d *arr)
{
    lock_lock(&ctx->lock);
    if (memblock_unref(ctx, &arr->mem, "arr->mem") != 0)
        return 1;
    lock_unlock(&ctx->lock);
    free(arr);
    return 0;
}
int futhark_values_f64_1d(struct futhark_context *ctx, struct futhark_f64_1d *arr, double *data)
{
    int err = 0;
    
    lock_lock(&ctx->lock);
    if ((size_t) arr->shape[0] * 8 > 0)
        memmove((unsigned char *) data + 0, arr->mem.mem + 0, (size_t) arr->shape[0] * 8);
    lock_unlock(&ctx->lock);
    return err;
}
int futhark_index_f64_1d(struct futhark_context *ctx, double *out, struct futhark_f64_1d *arr, int64_t i0)
{
    int err = 0;
    
    if (i0 >= 0 && i0 < arr->shape[0]) {
        lock_lock(&ctx->lock);
        if (8 > 0)
            memmove((unsigned char *) out + 0, arr->mem.mem + 8 * (i0 * 1), 8);
        lock_unlock(&ctx->lock);
    } else {
        err = 1;
        set_error(ctx, strdup("Index out of bounds."));
    }
    return err;
}
unsigned char *futhark_values_raw_f64_1d(struct futhark_context *ctx, struct futhark_f64_1d *arr)
{
    (void) ctx;
    return arr->mem.mem;
}
const int64_t *futhark_shape_f64_1d(struct futhark_context *ctx, struct futhark_f64_1d *arr)
{
    (void) ctx;
    return arr->shape;
}
struct futhark_f64_2d {
    struct memblock mem;
    int64_t shape[2];
};
struct futhark_f64_2d *futhark_new_f64_2d(struct futhark_context *ctx, const double *data, int64_t dim0, int64_t dim1)
{
    int err = 0;
    struct futhark_f64_2d *bad = NULL;
    struct futhark_f64_2d *arr = (struct futhark_f64_2d *) malloc(sizeof(struct futhark_f64_2d));
    
    if (arr == NULL)
        return bad;
    lock_lock(&ctx->lock);
    arr->mem.references = NULL;
    if (memblock_alloc(ctx, &arr->mem, dim0 * dim1 * 8, "arr->mem"))
        err = 1;
    arr->shape[0] = dim0;
    arr->shape[1] = dim1;
    if ((size_t) (dim0 * dim1) * 8 > 0)
        memmove(arr->mem.mem + 0, (const unsigned char *) data + 0, (size_t) (dim0 * dim1) * 8);
    lock_unlock(&ctx->lock);
    if (err != 0) {
        free(arr);
        return bad;
    }
    return arr;
}
struct futhark_f64_2d *futhark_new_raw_f64_2d(struct futhark_context *ctx, unsigned char *data, int64_t dim0, int64_t dim1)
{
    int err = 0;
    struct futhark_f64_2d *bad = NULL;
    struct futhark_f64_2d *arr = (struct futhark_f64_2d *) malloc(sizeof(struct futhark_f64_2d));
    
    if (arr == NULL)
        return bad;
    lock_lock(&ctx->lock);
    arr->mem.references = NULL;
    arr->mem.mem = data;
    arr->shape[0] = dim0;
    arr->shape[1] = dim1;
    lock_unlock(&ctx->lock);
    return arr;
}
int futhark_free_f64_2d(struct futhark_context *ctx, struct futhark_f64_2d *arr)
{
    lock_lock(&ctx->lock);
    if (memblock_unref(ctx, &arr->mem, "arr->mem") != 0)
        return 1;
    lock_unlock(&ctx->lock);
    free(arr);
    return 0;
}
int futhark_values_f64_2d(struct futhark_context *ctx, struct futhark_f64_2d *arr, double *data)
{
    int err = 0;
    
    lock_lock(&ctx->lock);
    if ((size_t) (arr->shape[0] * arr->shape[1]) * 8 > 0)
        memmove((unsigned char *) data + 0, arr->mem.mem + 0, (size_t) (arr->shape[0] * arr->shape[1]) * 8);
    lock_unlock(&ctx->lock);
    return err;
}
int futhark_index_f64_2d(struct futhark_context *ctx, double *out, struct futhark_f64_2d *arr, int64_t i0, int64_t i1)
{
    int err = 0;
    
    if ((i0 >= 0 && i0 < arr->shape[0]) && (i1 >= 0 && i1 < arr->shape[1])) {
        lock_lock(&ctx->lock);
        if (8 > 0)
            memmove((unsigned char *) out + 0, arr->mem.mem + 8 * (i0 * arr->shape[1] + i1 * 1), 8);
        lock_unlock(&ctx->lock);
    } else {
        err = 1;
        set_error(ctx, strdup("Index out of bounds."));
    }
    return err;
}
unsigned char *futhark_values_raw_f64_2d(struct futhark_context *ctx, struct futhark_f64_2d *arr)
{
    (void) ctx;
    return arr->mem.mem;
}
const int64_t *futhark_shape_f64_2d(struct futhark_context *ctx, struct futhark_f64_2d *arr)
{
    (void) ctx;
    return arr->shape;
}
struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 {
    struct futhark_i64_1d *v0;
    struct futhark_i64_1d *v1;
};
int futhark_project_opaque_tup2_arr1d_i64_arr1d_i64_0(struct futhark_context *ctx, struct futhark_i64_1d **out, const struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *obj)
{
    (void) ctx;
    
    struct futhark_i64_1d *v;
    
    lock_lock(&ctx->lock);
    v = malloc(sizeof(struct futhark_i64_1d));
    memcpy(v, obj->v0, sizeof(struct futhark_i64_1d));
    (void) (*v->mem.references)++;
    lock_unlock(&ctx->lock);
    *out = v;
    return 0;
}
int futhark_project_opaque_tup2_arr1d_i64_arr1d_i64_1(struct futhark_context *ctx, struct futhark_i64_1d **out, const struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *obj)
{
    (void) ctx;
    
    struct futhark_i64_1d *v;
    
    lock_lock(&ctx->lock);
    v = malloc(sizeof(struct futhark_i64_1d));
    memcpy(v, obj->v1, sizeof(struct futhark_i64_1d));
    (void) (*v->mem.references)++;
    lock_unlock(&ctx->lock);
    *out = v;
    return 0;
}
int futhark_new_opaque_tup2_arr1d_i64_arr1d_i64(struct futhark_context *ctx, struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 **out, const struct futhark_i64_1d *f_0, const struct futhark_i64_1d *f_1)
{
    struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *v = malloc(sizeof(struct futhark_opaque_tup2_arr1d_i64_arr1d_i64));
    
    lock_lock(&ctx->lock);
    {
        v->v0 = malloc(sizeof(struct futhark_i64_1d));
        *v->v0 = *f_0;
        (void) (*v->v0->mem.references)++;
    }
    {
        v->v1 = malloc(sizeof(struct futhark_i64_1d));
        *v->v1 = *f_1;
        (void) (*v->v1->mem.references)++;
    }
    lock_unlock(&ctx->lock);
    *out = v;
    return FUTHARK_SUCCESS;
}
int futhark_free_opaque_tup2_arr1d_i64_arr1d_i64(struct futhark_context *ctx, struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *obj)
{
    (void) ctx;
    
    int ret = 0, tmp;
    
    if (obj->v0 != NULL && (tmp = futhark_free_i64_1d(ctx, obj->v0)) != 0)
        ret = tmp;
    if (obj->v1 != NULL && (tmp = futhark_free_i64_1d(ctx, obj->v1)) != 0)
        ret = tmp;
    free(obj);
    return ret;
}
int futhark_store_opaque_tup2_arr1d_i64_arr1d_i64(struct futhark_context *ctx, const struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *obj, void **p, size_t *n)
{
    (void) ctx;
    
    int ret = 0;
    int64_t size_0 = 7 + 1 * sizeof(int64_t) + futhark_shape_i64_1d(ctx, obj->v0)[0] * sizeof(int64_t);
    int64_t size_1 = 7 + 1 * sizeof(int64_t) + futhark_shape_i64_1d(ctx, obj->v1)[0] * sizeof(int64_t);
    
    *n = size_0 + size_1;
    if (p != NULL && *p == NULL)
        *p = malloc(*n);
    if (p != NULL) {
        unsigned char *out = *p;
        
        *out++ = 'b';
        *out++ = 2;
        *out++ = 1;
        memcpy(out, " i64", 4);
        out += 4;
        memcpy(out, futhark_shape_i64_1d(ctx, obj->v0), 1 * sizeof(int64_t));
        out += 1 * sizeof(int64_t);
        ret |= futhark_values_i64_1d(ctx, obj->v0, (void *) out);
        out += futhark_shape_i64_1d(ctx, obj->v0)[0] * sizeof(int64_t);
        *out++ = 'b';
        *out++ = 2;
        *out++ = 1;
        memcpy(out, " i64", 4);
        out += 4;
        memcpy(out, futhark_shape_i64_1d(ctx, obj->v1), 1 * sizeof(int64_t));
        out += 1 * sizeof(int64_t);
        ret |= futhark_values_i64_1d(ctx, obj->v1, (void *) out);
        out += futhark_shape_i64_1d(ctx, obj->v1)[0] * sizeof(int64_t);
    }
    return ret;
}
struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *futhark_restore_opaque_tup2_arr1d_i64_arr1d_i64(struct futhark_context *ctx, const void *p)
{
    (void) ctx;
    
    int err = 0;
    const unsigned char *src = p;
    struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *obj = malloc(sizeof(struct futhark_opaque_tup2_arr1d_i64_arr1d_i64));
    int64_t shape_0[1] = {0};
    
    err |= *src++ != 'b';
    err |= *src++ != 2;
    err |= *src++ != 1;
    err |= memcmp(src, " i64", 4) != 0;
    src += 4;
    if (err == 0) {
        memcpy(shape_0, src, 1 * sizeof(int64_t));
        src += 1 * sizeof(int64_t);
    }
    
    const void *data_0 = src;
    
    obj->v0 = NULL;
    src += shape_0[0] * sizeof(int64_t);
    
    int64_t shape_1[1] = {0};
    
    err |= *src++ != 'b';
    err |= *src++ != 2;
    err |= *src++ != 1;
    err |= memcmp(src, " i64", 4) != 0;
    src += 4;
    if (err == 0) {
        memcpy(shape_1, src, 1 * sizeof(int64_t));
        src += 1 * sizeof(int64_t);
    }
    
    const void *data_1 = src;
    
    obj->v1 = NULL;
    src += shape_1[0] * sizeof(int64_t);
    if (err == 0) {
        obj->v0 = futhark_new_i64_1d(ctx, data_0, shape_0[0]);
        if (obj->v0 == NULL)
            err = 1;
        obj->v1 = futhark_new_i64_1d(ctx, data_1, shape_1[0]);
        if (obj->v1 == NULL)
            err = 1;
    }
    if (err != 0) {
        int ret = 0, tmp;
        
        if (obj->v0 != NULL && (tmp = futhark_free_i64_1d(ctx, obj->v0)) != 0)
            ret = tmp;
        if (obj->v1 != NULL && (tmp = futhark_free_i64_1d(ctx, obj->v1)) != 0)
            ret = tmp;
        free(obj);
        obj = NULL;
    }
    return obj;
}

FUTHARK_FUN_ATTR int futrts_entry_all_positive(struct futhark_context *ctx, bool *out_prim_out_10801, struct memblock arr_mem_10744, int64_t n_10161)
{
    (void) ctx;
    
    int err = 0;
    bool prim_out_10791;
    bool defunc_0_reduce_res_10598;
    bool redout_10719 = 1;
    
    for (int64_t i_10720 = 0; i_10720 < n_10161; i_10720++) {
        int64_t eta_p_10595 = ((int64_t *) arr_mem_10744.mem)[i_10720];
        bool lifted_lambda_res_10596 = slt64((int64_t) 0, eta_p_10595);
        bool x_10401 = lifted_lambda_res_10596 && redout_10719;
        bool redout_tmp_10792 = x_10401;
        
        redout_10719 = redout_tmp_10792;
    }
    defunc_0_reduce_res_10598 = redout_10719;
    prim_out_10791 = defunc_0_reduce_res_10598;
    *out_prim_out_10801 = prim_out_10791;
    
  cleanup:
    { }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_any_positive(struct futhark_context *ctx, bool *out_prim_out_10802, struct memblock arr_mem_10744, int64_t n_10109)
{
    (void) ctx;
    
    int err = 0;
    bool prim_out_10791;
    bool defunc_0_reduce_res_10598;
    bool redout_10719 = 0;
    
    for (int64_t i_10720 = 0; i_10720 < n_10109; i_10720++) {
        int64_t eta_p_10595 = ((int64_t *) arr_mem_10744.mem)[i_10720];
        bool lifted_lambda_res_10596 = slt64((int64_t) 0, eta_p_10595);
        bool defunc_0_op_res_10401 = lifted_lambda_res_10596 || redout_10719;
        bool redout_tmp_10792 = defunc_0_op_res_10401;
        
        redout_10719 = redout_tmp_10792;
    }
    defunc_0_reduce_res_10598 = redout_10719;
    prim_out_10791 = defunc_0_reduce_res_10598;
    *out_prim_out_10802 = prim_out_10791;
    
  cleanup:
    { }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_convolve_1d(struct futhark_context *ctx, struct memblock *mem_out_p_10803, int64_t *out_prim_out_10804, struct memblock signal_mem_10744, struct memblock kernel_mem_10745, int64_t n_8287, int64_t k_8288)
{
    (void) ctx;
    
    int err = 0;
    struct memblock mem_10747;
    
    mem_10747.references = NULL;
    
    struct memblock mem_10755;
    
    mem_10755.references = NULL;
    
    struct memblock ext_mem_10758;
    
    ext_mem_10758.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    int64_t prim_out_10792;
    bool cond_10548 = sle64(k_8288, (int64_t) 0);
    bool cond_f_res_10549 = slt64(n_8287, k_8288);
    bool x_10550 = !cond_10548;
    bool y_10551 = cond_f_res_10549 && x_10550;
    bool cond_10552 = cond_10548 || y_10551;
    int64_t zp_lhs_10553 = sub64(n_8287, k_8288);
    int64_t iota_arg0_10554 = add64((int64_t) 1, zp_lhs_10553);
    int64_t convolve_1d_res_10555;
    
    if (cond_10552) {
        convolve_1d_res_10555 = (int64_t) 0;
    } else {
        convolve_1d_res_10555 = iota_arg0_10554;
    }
    
    int64_t bytes_10746 = (int64_t) 8 * iota_arg0_10554;
    int64_t bytes_10754 = (int64_t) 8 * convolve_1d_res_10555;
    
    if (cond_10552) {
        if (memblock_alloc(ctx, &mem_10755, bytes_10754, "mem_10755")) {
            err = 1;
            goto cleanup;
        }
        if (memblock_set(ctx, &ext_mem_10758, &mem_10755, "mem_10755") != 0)
            return 1;
    } else {
        bool bounds_invalid_upwards_10558 = slt64(iota_arg0_10554, (int64_t) 0);
        bool valid_10559 = !bounds_invalid_upwards_10558;
        bool range_valid_c_10560;
        
        if (!valid_10559) {
            set_error(ctx, msgprintf("Error: %s%lld%s%lld%s%lld%s\n\nBacktrace:\n%s", "Range ", (long long) (int64_t) 0, "..", (long long) (int64_t) 1, "..<", (long long) iota_arg0_10554, " is invalid.", "-> #0  /prelude/array.fut:94:3-11\n   #1  main.fut:38:86-104\n   #2  main.fut:35:1-38:106\n"));
            err = FUTHARK_PROGRAM_ERROR;
            goto cleanup;
        }
        if (memblock_alloc(ctx, &mem_10747, bytes_10746, "mem_10747")) {
            err = 1;
            goto cleanup;
        }
        for (int64_t i_10723 = 0; i_10723 < iota_arg0_10554; i_10723++) {
            double defunc_0_reduce_res_10614;
            double redout_10719 = 0.0;
            
            for (int64_t i_10720 = 0; i_10720 < k_8288; i_10720++) {
                int64_t zt_lhs_10597 = add64(i_10720, i_10723);
                bool x_10598 = sle64((int64_t) 0, zt_lhs_10597);
                bool y_10599 = slt64(zt_lhs_10597, n_8287);
                bool bounds_check_10600 = x_10598 && y_10599;
                bool index_certs_10601;
                
                if (!bounds_check_10600) {
                    set_error(ctx, msgprintf("Error: %s%lld%s%lld%s\n\nBacktrace:\n%s", "Index [", (long long) zt_lhs_10597, "] out of bounds for array of shape [", (long long) n_8287, "].", "-> #0  main.fut:38:47-60\n   #1  main.fut:38:75-81\n   #2  main.fut:38:86-105\n   #3  main.fut:35:1-38:106\n"));
                    err = FUTHARK_PROGRAM_ERROR;
                    goto cleanup;
                }
                
                double zt_lhs_10602 = ((double *) signal_mem_10744.mem)[zt_lhs_10597];
                double zt_rhs_10607 = ((double *) kernel_mem_10745.mem)[i_10720];
                double lifted_lambda_res_10608 = zt_lhs_10602 * zt_rhs_10607;
                double defunc_0_op_res_10583 = lifted_lambda_res_10608 + redout_10719;
                double redout_tmp_10794 = defunc_0_op_res_10583;
                
                redout_10719 = redout_tmp_10794;
            }
            defunc_0_reduce_res_10614 = redout_10719;
            ((double *) mem_10747.mem)[i_10723] = defunc_0_reduce_res_10614;
        }
        if (memblock_set(ctx, &ext_mem_10758, &mem_10747, "mem_10747") != 0)
            return 1;
    }
    if (memblock_set(ctx, &mem_out_10791, &ext_mem_10758, "ext_mem_10758") != 0)
        return 1;
    prim_out_10792 = convolve_1d_res_10555;
    if (memblock_set(ctx, &*mem_out_p_10803, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    *out_prim_out_10804 = prim_out_10792;
    
  cleanup:
    {
        if (memblock_unref(ctx, &mem_10747, "mem_10747") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_10755, "mem_10755") != 0)
            return 1;
        if (memblock_unref(ctx, &ext_mem_10758, "ext_mem_10758") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_cosine_similarity(struct futhark_context *ctx, double *out_prim_out_10805, struct memblock a_mem_10744, struct memblock b_mem_10745, int64_t n_9428)
{
    (void) ctx;
    
    int err = 0;
    double prim_out_10791;
    bool defunc_0_reduce_res_10685;
    bool redout_10719 = 0;
    
    for (int64_t i_10720 = 0; i_10720 < n_9428; i_10720++) {
        double eta_p_10595 = ((double *) a_mem_10744.mem)[i_10720];
        bool isnan_res_10596 = futrts_isnan64(eta_p_10595);
        bool defunc_0_op_res_10472 = isnan_res_10596 || redout_10719;
        bool redout_tmp_10792 = defunc_0_op_res_10472;
        
        redout_10719 = redout_tmp_10792;
    }
    defunc_0_reduce_res_10685 = redout_10719;
    
    bool cond_10473;
    
    if (defunc_0_reduce_res_10685) {
        cond_10473 = 1;
    } else {
        bool defunc_0_reduce_res_10679;
        bool redout_10721 = 0;
        
        for (int64_t i_10722 = 0; i_10722 < n_9428; i_10722++) {
            double eta_p_10599 = ((double *) b_mem_10745.mem)[i_10722];
            bool isnan_res_10600 = futrts_isnan64(eta_p_10599);
            bool defunc_0_op_res_10481 = isnan_res_10600 || redout_10721;
            bool redout_tmp_10793 = defunc_0_op_res_10481;
            
            redout_10721 = redout_tmp_10793;
        }
        defunc_0_reduce_res_10679 = redout_10721;
        cond_10473 = defunc_0_reduce_res_10679;
    }
    
    double cosine_similarity_res_10482;
    
    if (cond_10473) {
        cosine_similarity_res_10482 = NAN;
    } else {
        double defunc_0_reduce_res_10683;
        double redout_10723 = 0.0;
        
        for (int64_t i_10724 = 0; i_10724 < n_9428; i_10724++) {
            double eta_p_10608 = ((double *) a_mem_10744.mem)[i_10724];
            double abs_res_10609 = fabs64(eta_p_10608);
            double max_res_10490 = fmax64(abs_res_10609, redout_10723);
            double redout_tmp_10794 = max_res_10490;
            
            redout_10723 = redout_tmp_10794;
        }
        defunc_0_reduce_res_10683 = redout_10723;
        
        double defunc_0_reduce_res_10684;
        double redout_10725 = 0.0;
        
        for (int64_t i_10726 = 0; i_10726 < n_9428; i_10726++) {
            double eta_p_10604 = ((double *) b_mem_10745.mem)[i_10726];
            double abs_res_10605 = fabs64(eta_p_10604);
            double max_res_10498 = fmax64(abs_res_10605, redout_10725);
            double redout_tmp_10795 = max_res_10498;
            
            redout_10725 = redout_tmp_10795;
        }
        defunc_0_reduce_res_10684 = redout_10725;
        
        bool cond_10499 = defunc_0_reduce_res_10683 == 0.0;
        bool cond_f_res_10500 = defunc_0_reduce_res_10684 == 0.0;
        bool x_10501 = !cond_10499;
        bool y_10502 = cond_f_res_10500 && x_10501;
        bool cond_10503 = cond_10499 || y_10502;
        double cosine_similarity_res_f_res_10504;
        
        if (cond_10503) {
            cosine_similarity_res_f_res_10504 = 0.0;
        } else {
            double defunc_0_reduce_res_10680;
            double defunc_0_reduce_res_10681;
            double defunc_0_reduce_res_10682;
            double redout_10727;
            double redout_10728;
            double redout_10729;
            
            redout_10727 = 0.0;
            redout_10728 = 0.0;
            redout_10729 = 0.0;
            for (int64_t i_10730 = 0; i_10730 < n_9428; i_10730++) {
                double eta_p_10657 = ((double *) a_mem_10744.mem)[i_10730];
                double eta_p_10658 = ((double *) b_mem_10745.mem)[i_10730];
                double lifted_lambda_res_10659 = eta_p_10657 / defunc_0_reduce_res_10683;
                double lifted_lambda_res_10661 = eta_p_10658 / defunc_0_reduce_res_10684;
                double defunc_0_f_res_10663 = lifted_lambda_res_10659 * lifted_lambda_res_10661;
                double lifted_lambda_res_10666 = lifted_lambda_res_10661 * lifted_lambda_res_10661;
                double lifted_lambda_res_10669 = lifted_lambda_res_10659 * lifted_lambda_res_10659;
                double defunc_0_op_res_10519 = defunc_0_f_res_10663 + redout_10727;
                double defunc_0_op_res_10536 = lifted_lambda_res_10666 + redout_10728;
                double defunc_0_op_res_10527 = lifted_lambda_res_10669 + redout_10729;
                double redout_tmp_10796 = defunc_0_op_res_10519;
                double redout_tmp_10797 = defunc_0_op_res_10536;
                double redout_tmp_10798 = defunc_0_op_res_10527;
                
                redout_10727 = redout_tmp_10796;
                redout_10728 = redout_tmp_10797;
                redout_10729 = redout_tmp_10798;
            }
            defunc_0_reduce_res_10680 = redout_10727;
            defunc_0_reduce_res_10681 = redout_10728;
            defunc_0_reduce_res_10682 = redout_10729;
            
            double sqrt_res_10528 = futrts_sqrt64(defunc_0_reduce_res_10682);
            double sqrt_res_10537 = futrts_sqrt64(defunc_0_reduce_res_10681);
            double zs_rhs_10538 = sqrt_res_10528 * sqrt_res_10537;
            double r_10539 = defunc_0_reduce_res_10680 / zs_rhs_10538;
            bool isnan_res_10540 = futrts_isnan64(r_10539);
            double cosine_similarity_res_f_res_f_res_10541;
            
            if (isnan_res_10540) {
                cosine_similarity_res_f_res_f_res_10541 = NAN;
            } else {
                double min_res_10542 = fmin64(1.0, r_10539);
                double max_res_10543 = fmax64(-1.0, min_res_10542);
                
                cosine_similarity_res_f_res_f_res_10541 = max_res_10543;
            }
            cosine_similarity_res_f_res_10504 = cosine_similarity_res_f_res_f_res_10541;
        }
        cosine_similarity_res_10482 = cosine_similarity_res_f_res_10504;
    }
    prim_out_10791 = cosine_similarity_res_10482;
    *out_prim_out_10805 = prim_out_10791;
    
  cleanup:
    { }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_exponential_moving_average(struct futhark_context *ctx, struct memblock *mem_out_p_10806, struct memblock arr_mem_10744, int64_t n_9965, double alpha_9967)
{
    (void) ctx;
    
    int err = 0;
    struct memblock mem_10746;
    
    mem_10746.references = NULL;
    
    struct memblock mem_10754;
    
    mem_10754.references = NULL;
    
    struct memblock ext_mem_10757;
    
    ext_mem_10757.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    bool cond_10465 = 0.0 < alpha_9967;
    bool tmp_t_res_10466 = alpha_9967 <= 1.0;
    bool x_10467 = cond_10465 && tmp_t_res_10466;
    bool cond_10468 = !x_10467;
    int64_t bytes_10745 = (int64_t) 8 * n_9965;
    
    if (cond_10468) {
        if (memblock_alloc(ctx, &mem_10754, bytes_10745, "mem_10754")) {
            err = 1;
            goto cleanup;
        }
        for (int64_t nest_i_10792 = 0; nest_i_10792 < n_9965; nest_i_10792++) {
            ((double *) mem_10754.mem)[nest_i_10792] = NAN;
        }
        if (memblock_set(ctx, &ext_mem_10757, &mem_10754, "mem_10754") != 0)
            return 1;
    } else {
        double decay_10471 = 1.0 - alpha_9967;
        
        if (memblock_alloc(ctx, &mem_10746, bytes_10745, "mem_10746")) {
            err = 1;
            goto cleanup;
        }
        
        double discard_10729;
        double scanacc_10722 = 0.0;
        
        for (int64_t i_10725 = 0; i_10725 < n_9965; i_10725++) {
            double eta_p_10598 = ((double *) arr_mem_10744.mem)[i_10725];
            bool cond_10599 = i_10725 == (int64_t) 0;
            double lifted_lambda_res_10600;
            
            if (cond_10599) {
                lifted_lambda_res_10600 = 0.0;
            } else {
                lifted_lambda_res_10600 = decay_10471;
            }
            
            double lifted_lambda_res_10601;
            
            if (cond_10599) {
                lifted_lambda_res_10601 = eta_p_10598;
            } else {
                double tmp_10602 = alpha_9967 * eta_p_10598;
                
                lifted_lambda_res_10601 = tmp_10602;
            }
            
            double zp_lhs_10490 = lifted_lambda_res_10600 * scanacc_10722;
            double tmp_10491 = zp_lhs_10490 + lifted_lambda_res_10601;
            
            ((double *) mem_10746.mem)[i_10725] = tmp_10491;
            
            double scanacc_tmp_10793 = tmp_10491;
            
            scanacc_10722 = scanacc_tmp_10793;
        }
        discard_10729 = scanacc_10722;
        if (memblock_set(ctx, &ext_mem_10757, &mem_10746, "mem_10746") != 0)
            return 1;
    }
    if (memblock_set(ctx, &mem_out_10791, &ext_mem_10757, "ext_mem_10757") != 0)
        return 1;
    if (memblock_set(ctx, &*mem_out_p_10806, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    
  cleanup:
    {
        if (memblock_unref(ctx, &mem_10746, "mem_10746") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_10754, "mem_10754") != 0)
            return 1;
        if (memblock_unref(ctx, &ext_mem_10757, "ext_mem_10757") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_find_max(struct futhark_context *ctx, bool *out_prim_out_10807, int64_t *out_prim_out_10808, struct memblock arr_mem_10744, int64_t n_8597)
{
    (void) ctx;
    
    int err = 0;
    bool prim_out_10791;
    int64_t prim_out_10792;
    bool cond_10323 = slt64((int64_t) 0, n_8597);
    int64_t find_max_res_10324;
    
    if (cond_10323) {
        int64_t defunc_0_reduce_res_10595;
        int64_t redout_10719 = (int64_t) -9223372036854775808;
        
        for (int64_t i_10720 = 0; i_10720 < n_8597; i_10720++) {
            int64_t x_10596 = ((int64_t *) arr_mem_10744.mem)[i_10720];
            int64_t max_res_10599 = smax64(x_10596, redout_10719);
            int64_t redout_tmp_10793 = max_res_10599;
            
            redout_10719 = redout_tmp_10793;
        }
        defunc_0_reduce_res_10595 = redout_10719;
        find_max_res_10324 = defunc_0_reduce_res_10595;
    } else {
        find_max_res_10324 = (int64_t) 0;
    }
    prim_out_10791 = cond_10323;
    prim_out_10792 = find_max_res_10324;
    *out_prim_out_10807 = prim_out_10791;
    *out_prim_out_10808 = prim_out_10792;
    
  cleanup:
    { }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_find_min(struct futhark_context *ctx, bool *out_prim_out_10809, int64_t *out_prim_out_10810, struct memblock arr_mem_10744, int64_t n_8630)
{
    (void) ctx;
    
    int err = 0;
    bool prim_out_10791;
    int64_t prim_out_10792;
    bool cond_10323 = slt64((int64_t) 0, n_8630);
    int64_t find_min_res_10324;
    
    if (cond_10323) {
        int64_t defunc_0_reduce_res_10595;
        int64_t redout_10719 = (int64_t) 9223372036854775807;
        
        for (int64_t i_10720 = 0; i_10720 < n_8630; i_10720++) {
            int64_t x_10596 = ((int64_t *) arr_mem_10744.mem)[i_10720];
            int64_t min_res_10599 = smin64(x_10596, redout_10719);
            int64_t redout_tmp_10793 = min_res_10599;
            
            redout_10719 = redout_tmp_10793;
        }
        defunc_0_reduce_res_10595 = redout_10719;
        find_min_res_10324 = defunc_0_reduce_res_10595;
    } else {
        find_min_res_10324 = (int64_t) 0;
    }
    prim_out_10791 = cond_10323;
    prim_out_10792 = find_min_res_10324;
    *out_prim_out_10809 = prim_out_10791;
    *out_prim_out_10810 = prim_out_10792;
    
  cleanup:
    { }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_flatten_3d_array(struct futhark_context *ctx, struct memblock *mem_out_p_10811, int64_t *out_prim_out_10812, struct memblock arr_mem_10744, int64_t n_10054, int64_t m_10055, int64_t l_10056)
{
    (void) ctx;
    
    int err = 0;
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    int64_t prim_out_10792;
    int64_t flat_dim_10271 = n_10054 * m_10055;
    int64_t flat_dim_10273 = l_10056 * flat_dim_10271;
    
    if (memblock_set(ctx, &mem_out_10791, &arr_mem_10744, "arr_mem_10744") != 0)
        return 1;
    prim_out_10792 = flat_dim_10273;
    if (memblock_set(ctx, &*mem_out_p_10811, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    *out_prim_out_10812 = prim_out_10792;
    
  cleanup:
    {
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_gather(struct futhark_context *ctx, struct memblock *mem_out_p_10813, struct memblock src_mem_10744, struct memblock indices_mem_10745, int64_t n_8345, int64_t m_8346, int64_t fill_8349)
{
    (void) ctx;
    
    int err = 0;
    struct memblock mem_10747;
    
    mem_10747.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    int64_t bytes_10746 = (int64_t) 8 * m_8346;
    
    if (memblock_alloc(ctx, &mem_10747, bytes_10746, "mem_10747")) {
        err = 1;
        goto cleanup;
    }
    for (int64_t i_10721 = 0; i_10721 < m_8346; i_10721++) {
        int64_t eta_p_10327 = ((int64_t *) indices_mem_10745.mem)[i_10721];
        bool cond_10328 = sle64((int64_t) 0, eta_p_10327);
        bool cond_t_res_10329 = slt64(eta_p_10327, n_8345);
        bool x_10330 = cond_10328 && cond_t_res_10329;
        int64_t lifted_lambda_res_10331;
        
        if (x_10330) {
            bool index_certs_10594;
            
            if (!x_10330) {
                set_error(ctx, msgprintf("Error: %s%lld%s%lld%s\n\nBacktrace:\n%s", "Index [", (long long) eta_p_10327, "] out of bounds for array of shape [", (long long) n_8345, "].", "-> #0  main.fut:41:41-47\n   #1  main.fut:41:59-66\n   #2  main.fut:40:1-41:66\n"));
                err = FUTHARK_PROGRAM_ERROR;
                goto cleanup;
            }
            
            int64_t lifted_lambda_res_t_res_10595 = ((int64_t *) src_mem_10744.mem)[eta_p_10327];
            
            lifted_lambda_res_10331 = lifted_lambda_res_t_res_10595;
        } else {
            lifted_lambda_res_10331 = fill_8349;
        }
        ((int64_t *) mem_10747.mem)[i_10721] = lifted_lambda_res_10331;
    }
    if (memblock_set(ctx, &mem_out_10791, &mem_10747, "mem_10747") != 0)
        return 1;
    if (memblock_set(ctx, &*mem_out_p_10813, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    
  cleanup:
    {
        if (memblock_unref(ctx, &mem_10747, "mem_10747") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_histogram(struct futhark_context *ctx, struct memblock *mem_out_p_10814, int64_t *out_prim_out_10815, struct memblock arr_mem_10744, int64_t n_7985, int64_t num_bins_7987)
{
    (void) ctx;
    
    int err = 0;
    struct memblock mem_10746;
    
    mem_10746.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    int64_t prim_out_10792;
    int64_t max_res_10465 = smax64((int64_t) 0, num_bins_7987);
    int64_t max_res_10466 = smax64((int64_t) 1, num_bins_7987);
    int64_t defunc_0_reduce_res_10605;
    int64_t defunc_0_reduce_res_10606;
    int64_t redout_10719;
    int64_t redout_10720;
    
    redout_10719 = (int64_t) 9223372036854775807;
    redout_10720 = (int64_t) -9223372036854775808;
    for (int64_t i_10721 = 0; i_10721 < n_7985; i_10721++) {
        int64_t x_10603 = ((int64_t *) arr_mem_10744.mem)[i_10721];
        int64_t min_res_10471 = smin64(x_10603, redout_10719);
        int64_t max_res_10476 = smax64(x_10603, redout_10720);
        int64_t redout_tmp_10793 = min_res_10471;
        int64_t redout_tmp_10794 = max_res_10476;
        
        redout_10719 = redout_tmp_10793;
        redout_10720 = redout_tmp_10794;
    }
    defunc_0_reduce_res_10605 = redout_10719;
    defunc_0_reduce_res_10606 = redout_10720;
    
    int64_t range_10477 = sub64(defunc_0_reduce_res_10606, defunc_0_reduce_res_10605);
    bool zzero_10478 = max_res_10466 == (int64_t) 0;
    bool nonzzero_10479 = !zzero_10478;
    bool nonzzero_cert_10480;
    
    if (!nonzzero_10479) {
        set_error(ctx, msgprintf("Error: %s\n\nBacktrace:\n%s", "division by zero", "-> #0  main.fut:22:21-40\n   #1  main.fut:16:1-28:88\n"));
        err = FUTHARK_PROGRAM_ERROR;
        goto cleanup;
    }
    
    int64_t zp_lhs_10481 = udiv64(range_10477, max_res_10466);
    int64_t width_10482 = add64((int64_t) 1, zp_lhs_10481);
    bool cond_10484 = max_res_10466 == (int64_t) 1;
    bool zzero_10485 = width_10482 == (int64_t) 0;
    bool nonzzero_10487 = !zzero_10485;
    bool protect_assert_disj_10488 = cond_10484 || nonzzero_10487;
    bool nonzzero_cert_10489;
    
    if (!protect_assert_disj_10488) {
        set_error(ctx, msgprintf("Error: %s\n\nBacktrace:\n%s", "division by zero", "-> #0  main.fut:27:57-64\n   #1  main.fut:16:1-28:88\n"));
        err = FUTHARK_PROGRAM_ERROR;
        goto cleanup;
    }
    
    int64_t bytes_10745 = (int64_t) 8 * max_res_10465;
    int64_t min_arg0_10486 = sub64(max_res_10466, (int64_t) 1);
    
    if (memblock_alloc(ctx, &mem_10746, bytes_10745, "mem_10746")) {
        err = 1;
        goto cleanup;
    }
    for (int64_t nest_i_10795 = 0; nest_i_10795 < max_res_10465; nest_i_10795++) {
        ((int64_t *) mem_10746.mem)[nest_i_10795] = (int64_t) 0;
    }
    for (int64_t iter_10722 = 0; iter_10722 < n_7985; iter_10722++) {
        int64_t pixel_10724 = ((int64_t *) arr_mem_10744.mem)[iter_10722];
        int64_t lifted_bin_of_res_10597;
        
        if (cond_10484) {
            lifted_bin_of_res_10597 = (int64_t) 0;
        } else {
            int64_t offset_10598 = sub64(pixel_10724, defunc_0_reduce_res_10605);
            int64_t u64_arg0_10599 = udiv64(offset_10598, width_10482);
            int64_t min_res_10600 = smin64(min_arg0_10486, u64_arg0_10599);
            
            lifted_bin_of_res_10597 = min_res_10600;
        }
        
        bool less_than_zzero_10726 = slt64(lifted_bin_of_res_10597, (int64_t) 0);
        bool greater_than_sizze_10727 = sle64(max_res_10465, lifted_bin_of_res_10597);
        bool outside_bounds_dim_10728 = less_than_zzero_10726 || greater_than_sizze_10727;
        
        if (!outside_bounds_dim_10728) {
            int64_t read_hist_10730 = ((int64_t *) mem_10746.mem)[lifted_bin_of_res_10597];
            int64_t defunc_0_f_res_10500 = add64((int64_t) 1, read_hist_10730);
            
            ((int64_t *) mem_10746.mem)[lifted_bin_of_res_10597] = defunc_0_f_res_10500;
        }
    }
    if (memblock_set(ctx, &mem_out_10791, &mem_10746, "mem_10746") != 0)
        return 1;
    prim_out_10792 = max_res_10465;
    if (memblock_set(ctx, &*mem_out_p_10814, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    *out_prim_out_10815 = prim_out_10792;
    
  cleanup:
    {
        if (memblock_unref(ctx, &mem_10746, "mem_10746") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_min_max_normalizze(struct futhark_context *ctx, struct memblock *mem_out_p_10816, struct memblock arr_mem_10744, int64_t n_8800)
{
    (void) ctx;
    
    int err = 0;
    struct memblock mem_10746;
    
    mem_10746.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    int64_t bytes_10745 = (int64_t) 8 * n_8800;
    double defunc_0_reduce_res_10617;
    double defunc_0_reduce_res_10618;
    double redout_10719;
    double redout_10720;
    
    redout_10719 = INFINITY;
    redout_10720 = -INFINITY;
    for (int64_t i_10721 = 0; i_10721 < n_8800; i_10721++) {
        double eta_p_10605 = ((double *) arr_mem_10744.mem)[i_10721];
        bool cond_10607;
        
        if (futrts_is_finite_value_4544(ctx, &cond_10607, eta_p_10605) != 0) {
            err = 1;
            goto cleanup;
        }
        
        double lifted_lambda_res_10608;
        
        if (cond_10607) {
            lifted_lambda_res_10608 = eta_p_10605;
        } else {
            lifted_lambda_res_10608 = INFINITY;
        }
        
        double lifted_lambda_res_10611;
        
        if (cond_10607) {
            lifted_lambda_res_10611 = eta_p_10605;
        } else {
            lifted_lambda_res_10611 = -INFINITY;
        }
        
        double min_res_10473 = fmin64(lifted_lambda_res_10608, redout_10719);
        double max_res_10482 = fmax64(lifted_lambda_res_10611, redout_10720);
        double redout_tmp_10792 = min_res_10473;
        double redout_tmp_10793 = max_res_10482;
        
        redout_10719 = redout_tmp_10792;
        redout_10720 = redout_tmp_10793;
    }
    defunc_0_reduce_res_10617 = redout_10719;
    defunc_0_reduce_res_10618 = redout_10720;
    
    double half_min_10483 = defunc_0_reduce_res_10617 / 2.0;
    double zm_lhs_10484 = defunc_0_reduce_res_10618 / 2.0;
    double half_range_10485 = zm_lhs_10484 - half_min_10483;
    
    if (memblock_alloc(ctx, &mem_10746, bytes_10745, "mem_10746")) {
        err = 1;
        goto cleanup;
    }
    for (int64_t i_10724 = 0; i_10724 < n_8800; i_10724++) {
        double eta_p_10487 = ((double *) arr_mem_10744.mem)[i_10724];
        bool isnan_res_10488 = futrts_isnan64(eta_p_10487);
        double lifted_lambda_res_10489;
        
        if (isnan_res_10488) {
            lifted_lambda_res_10489 = eta_p_10487;
        } else {
            bool isinf_res_10490 = futrts_isinf64(eta_p_10487);
            double lifted_lambda_res_f_res_10491;
            
            if (isinf_res_10490) {
                bool cond_10615 = 0.0 < eta_p_10487;
                double lifted_lambda_res_f_res_t_res_10616;
                
                if (cond_10615) {
                    lifted_lambda_res_f_res_t_res_10616 = 1.0;
                } else {
                    lifted_lambda_res_f_res_t_res_10616 = 0.0;
                }
                lifted_lambda_res_f_res_10491 = lifted_lambda_res_f_res_t_res_10616;
            } else {
                bool cond_10494 = half_range_10485 == 0.0;
                double lifted_lambda_res_f_res_f_res_10495;
                
                if (cond_10494) {
                    lifted_lambda_res_f_res_f_res_10495 = 0.5;
                } else {
                    double zm_lhs_10496 = eta_p_10487 / 2.0;
                    double zs_lhs_10497 = zm_lhs_10496 - half_min_10483;
                    double lifted_lambda_res_f_res_f_res_f_res_10498 = zs_lhs_10497 / half_range_10485;
                    
                    lifted_lambda_res_f_res_f_res_10495 = lifted_lambda_res_f_res_f_res_f_res_10498;
                }
                lifted_lambda_res_f_res_10491 = lifted_lambda_res_f_res_f_res_10495;
            }
            lifted_lambda_res_10489 = lifted_lambda_res_f_res_10491;
        }
        ((double *) mem_10746.mem)[i_10724] = lifted_lambda_res_10489;
    }
    if (memblock_set(ctx, &mem_out_10791, &mem_10746, "mem_10746") != 0)
        return 1;
    if (memblock_set(ctx, &*mem_out_p_10816, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    
  cleanup:
    {
        if (memblock_unref(ctx, &mem_10746, "mem_10746") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_moving_average(struct futhark_context *ctx, struct memblock *mem_out_p_10817, int64_t *out_prim_out_10818, struct memblock arr_mem_10744, int64_t n_8115, int64_t window_8117)
{
    (void) ctx;
    
    int err = 0;
    struct memblock mem_10746;
    
    mem_10746.references = NULL;
    
    struct memblock mem_10754;
    
    mem_10754.references = NULL;
    
    struct memblock ext_mem_10757;
    
    ext_mem_10757.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    int64_t prim_out_10792;
    bool cond_10465 = sle64(window_8117, (int64_t) 0);
    bool cond_f_res_10466 = slt64(n_8115, window_8117);
    bool x_10467 = !cond_10465;
    bool y_10468 = cond_f_res_10466 && x_10467;
    bool cond_10469 = cond_10465 || y_10468;
    int64_t zp_lhs_10470 = sub64(n_8115, window_8117);
    int64_t iota_arg0_10471 = add64((int64_t) 1, zp_lhs_10470);
    int64_t moving_average_res_10472;
    
    if (cond_10469) {
        moving_average_res_10472 = (int64_t) 0;
    } else {
        moving_average_res_10472 = iota_arg0_10471;
    }
    
    int64_t bytes_10745 = (int64_t) 8 * iota_arg0_10471;
    int64_t bytes_10753 = (int64_t) 8 * moving_average_res_10472;
    
    if (cond_10469) {
        if (memblock_alloc(ctx, &mem_10754, bytes_10753, "mem_10754")) {
            err = 1;
            goto cleanup;
        }
        if (memblock_set(ctx, &ext_mem_10757, &mem_10754, "mem_10754") != 0)
            return 1;
    } else {
        bool bounds_invalid_upwards_10475 = slt64(iota_arg0_10471, (int64_t) 0);
        bool valid_10476 = !bounds_invalid_upwards_10475;
        bool range_valid_c_10477;
        
        if (!valid_10476) {
            set_error(ctx, msgprintf("Error: %s%lld%s%lld%s%lld%s\n\nBacktrace:\n%s", "Range ", (long long) (int64_t) 0, "..", (long long) (int64_t) 1, "..<", (long long) iota_arg0_10471, " is invalid.", "-> #0  /prelude/array.fut:94:3-11\n   #1  main.fut:33:74-97\n   #2  main.fut:30:1-33:99\n"));
            err = FUTHARK_PROGRAM_ERROR;
            goto cleanup;
        }
        
        bool empty_slice_10479 = window_8117 == (int64_t) 0;
        int64_t m_10480 = sub64(window_8117, (int64_t) 1);
        double i64_res_10481 = sitofp_i64_f64(window_8117);
        
        if (memblock_alloc(ctx, &mem_10746, bytes_10745, "mem_10746")) {
            err = 1;
            goto cleanup;
        }
        for (int64_t i_10723 = 0; i_10723 < iota_arg0_10471; i_10723++) {
            int64_t reduce_arg2_10484 = add64(window_8117, i_10723);
            int64_t i_p_m_t_s_10485 = add64(m_10480, i_10723);
            bool zzero_leq_i_p_m_t_s_10486 = sle64((int64_t) 0, i_p_m_t_s_10485);
            bool i_p_m_t_s_leq_w_10487 = slt64(i_p_m_t_s_10485, n_8115);
            bool i_lte_j_10489 = sle64(i_10723, reduce_arg2_10484);
            bool y_10491 = zzero_leq_i_p_m_t_s_10486 && i_p_m_t_s_leq_w_10487;
            bool forwards_ok_10492 = i_lte_j_10489 && y_10491;
            bool ok_or_empty_10493 = empty_slice_10479 || forwards_ok_10492;
            bool index_certs_10494;
            
            if (!ok_or_empty_10493) {
                set_error(ctx, msgprintf("Error: %s%lld%s%lld%s%lld%s\n\nBacktrace:\n%s", "Index [", (long long) i_10723, ":", (long long) reduce_arg2_10484, "] out of bounds for array of shape [", (long long) n_8115, "].", "-> #0  main.fut:33:36-53\n   #1  main.fut:33:74-98\n   #2  main.fut:30:1-33:99\n"));
                err = FUTHARK_PROGRAM_ERROR;
                goto cleanup;
            }
            
            double defunc_0_reduce_res_10595;
            double redout_10719 = 0.0;
            
            for (int64_t i_10720 = 0; i_10720 < window_8117; i_10720++) {
                int64_t slice_10740 = i_10720 + i_10723;
                double x_10497 = ((double *) arr_mem_10744.mem)[slice_10740];
                double defunc_0_op_res_10500 = x_10497 + redout_10719;
                double redout_tmp_10794 = defunc_0_op_res_10500;
                
                redout_10719 = redout_tmp_10794;
            }
            defunc_0_reduce_res_10595 = redout_10719;
            
            double lifted_lambda_res_10501 = defunc_0_reduce_res_10595 / i64_res_10481;
            
            ((double *) mem_10746.mem)[i_10723] = lifted_lambda_res_10501;
        }
        if (memblock_set(ctx, &ext_mem_10757, &mem_10746, "mem_10746") != 0)
            return 1;
    }
    if (memblock_set(ctx, &mem_out_10791, &ext_mem_10757, "ext_mem_10757") != 0)
        return 1;
    prim_out_10792 = moving_average_res_10472;
    if (memblock_set(ctx, &*mem_out_p_10817, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    *out_prim_out_10818 = prim_out_10792;
    
  cleanup:
    {
        if (memblock_unref(ctx, &mem_10746, "mem_10746") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_10754, "mem_10754") != 0)
            return 1;
        if (memblock_unref(ctx, &ext_mem_10757, "ext_mem_10757") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_partition_array(struct futhark_context *ctx, struct memblock *mem_out_p_10819, struct memblock *mem_out_p_10820, int64_t *out_prim_out_10821, int64_t *out_prim_out_10822, struct memblock arr_mem_10744, int64_t n_9779, int64_t pivot_9781)
{
    (void) ctx;
    
    int err = 0;
    int64_t mem_10746_cached_sizze_10823 = 0;
    unsigned char *mem_10746 = NULL;
    int64_t mem_10748_cached_sizze_10824 = 0;
    unsigned char *mem_10748 = NULL;
    int64_t mem_10750_cached_sizze_10825 = 0;
    unsigned char *mem_10750 = NULL;
    struct memblock mem_10781;
    
    mem_10781.references = NULL;
    
    struct memblock mem_10770;
    
    mem_10770.references = NULL;
    
    struct memblock mem_out_10792;
    
    mem_out_10792.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    int64_t prim_out_10793;
    int64_t prim_out_10794;
    int64_t bytes_10745 = (int64_t) 8 * n_9779;
    
    if (mem_10746_cached_sizze_10823 < bytes_10745) {
        err = lexical_realloc(ctx, &mem_10746, &mem_10746_cached_sizze_10823, bytes_10745);
        if (err != FUTHARK_SUCCESS)
            goto cleanup;
    }
    if (mem_10748_cached_sizze_10824 < bytes_10745) {
        err = lexical_realloc(ctx, &mem_10748, &mem_10748_cached_sizze_10824, bytes_10745);
        if (err != FUTHARK_SUCCESS)
            goto cleanup;
    }
    if (mem_10750_cached_sizze_10825 < bytes_10745) {
        err = lexical_realloc(ctx, &mem_10750, &mem_10750_cached_sizze_10825, bytes_10745);
        if (err != FUTHARK_SUCCESS)
            goto cleanup;
    }
    
    int64_t discard_10731;
    int64_t discard_10732;
    int64_t scanacc_10722;
    int64_t scanacc_10723;
    
    scanacc_10722 = (int64_t) 0;
    scanacc_10723 = (int64_t) 0;
    for (int64_t i_10727 = 0; i_10727 < n_9779; i_10727++) {
        int64_t x_10597 = ((int64_t *) arr_mem_10744.mem)[i_10727];
        bool lifted_lambda_res_10598 = slt64(x_10597, pivot_9781);
        bool cond_neg_10599 = !lifted_lambda_res_10598;
        int64_t defunc_0_lifted_pzq_res_10600 = btoi_bool_i64(cond_neg_10599);
        bool is_i_10601 = defunc_0_lifted_pzq_res_10600 == (int64_t) 0;
        int64_t part_res_10602 = btoi_bool_i64(is_i_10601);
        int64_t part_res_10603;
        int64_t part_res_10604;
        
        if (is_i_10601) {
            part_res_10603 = (int64_t) 0;
            part_res_10604 = (int64_t) 0;
        } else {
            bool is_i_10605 = defunc_0_lifted_pzq_res_10600 == (int64_t) 1;
            int64_t part_res_10606;
            
            if (is_i_10605) {
                part_res_10606 = (int64_t) 1;
            } else {
                part_res_10606 = (int64_t) 2;
            }
            
            int64_t part_res_10607 = btoi_bool_i64(is_i_10605);
            
            part_res_10603 = part_res_10606;
            part_res_10604 = part_res_10607;
        }
        
        int64_t zz_10417 = part_res_10602 + scanacc_10722;
        int64_t zz_10418 = part_res_10604 + scanacc_10723;
        
        ((int64_t *) mem_10746)[i_10727] = zz_10417;
        ((int64_t *) mem_10748)[i_10727] = zz_10418;
        ((int64_t *) mem_10750)[i_10727] = part_res_10603;
        
        int64_t scanacc_tmp_10795 = zz_10417;
        int64_t scanacc_tmp_10796 = zz_10418;
        
        scanacc_10722 = scanacc_tmp_10795;
        scanacc_10723 = scanacc_tmp_10796;
    }
    discard_10731 = scanacc_10722;
    discard_10732 = scanacc_10723;
    
    int64_t last_index_10419 = n_9779 - (int64_t) 1;
    bool is_empty_10420 = n_9779 == (int64_t) 0;
    bool x_10421 = !is_empty_10420;
    int64_t last_offset_10422;
    
    if (x_10421) {
        int64_t x_10612 = ((int64_t *) mem_10746)[last_index_10419];
        
        last_offset_10422 = x_10612;
    } else {
        last_offset_10422 = (int64_t) 0;
    }
    
    int64_t partition_sizze_10424;
    
    if (is_empty_10420) {
        partition_sizze_10424 = (int64_t) 0;
    } else {
        partition_sizze_10424 = last_offset_10422;
    }
    
    bool eq_x_zz_10438 = (int64_t) 0 == last_offset_10422;
    bool p_and_eq_x_y_10439 = x_10421 && eq_x_zz_10438;
    bool empty_slice_10440 = is_empty_10420 || p_and_eq_x_y_10439;
    int64_t m_10441 = sub64(partition_sizze_10424, (int64_t) 1);
    bool zzero_leq_i_p_m_t_s_10442 = sle64((int64_t) 0, m_10441);
    bool i_p_m_t_s_leq_w_10443 = slt64(m_10441, n_9779);
    bool i_lte_j_10444 = sle64((int64_t) 0, partition_sizze_10424);
    bool y_10445 = zzero_leq_i_p_m_t_s_10442 && i_p_m_t_s_leq_w_10443;
    bool forwards_ok_10446 = i_lte_j_10444 && y_10445;
    bool ok_or_empty_10447 = empty_slice_10440 || forwards_ok_10446;
    bool index_certs_10448;
    
    if (!ok_or_empty_10447) {
        set_error(ctx, msgprintf("Error: %s%lld%s%lld%s%lld%s\n\nBacktrace:\n%s", "Index [", (long long) (int64_t) 0, ":", (long long) partition_sizze_10424, "] out of bounds for array of shape [", (long long) n_9779, "].", "-> #0  /prelude/soacs.fut:174:7-19\n   #1  main.fut:138:31-34\n   #2  main.fut:137:1-138:34\n"));
        err = FUTHARK_PROGRAM_ERROR;
        goto cleanup;
    }
    
    int64_t j_m_i_10450 = sub64(n_9779, partition_sizze_10424);
    bool empty_slice_10451 = j_m_i_10450 == (int64_t) 0;
    int64_t m_10452 = sub64(j_m_i_10450, (int64_t) 1);
    int64_t i_p_m_t_s_10453 = add64(partition_sizze_10424, m_10452);
    bool zzero_leq_i_p_m_t_s_10454 = sle64((int64_t) 0, i_p_m_t_s_10453);
    bool i_p_m_t_s_leq_w_10455 = slt64(i_p_m_t_s_10453, n_9779);
    bool i_lte_j_10456 = sle64(partition_sizze_10424, n_9779);
    bool y_10457 = zzero_leq_i_p_m_t_s_10454 && i_p_m_t_s_leq_w_10455;
    bool forwards_ok_10458 = i_lte_j_10456 && y_10457;
    bool ok_or_empty_10459 = empty_slice_10451 || forwards_ok_10458;
    bool index_certs_10460;
    
    if (!ok_or_empty_10459) {
        set_error(ctx, msgprintf("Error: %s%lld%s%lld%s%lld%s\n\nBacktrace:\n%s", "Index [", (long long) partition_sizze_10424, ":", (long long) n_9779, "] out of bounds for array of shape [", (long long) n_9779, "].", "-> #0  /prelude/soacs.fut:174:21-33\n   #1  main.fut:138:31-34\n   #2  main.fut:137:1-138:34\n"));
        err = FUTHARK_PROGRAM_ERROR;
        goto cleanup;
    }
    
    int64_t bytes_10780 = (int64_t) 8 * j_m_i_10450;
    
    if (memblock_alloc(ctx, &mem_10770, bytes_10745, "mem_10770")) {
        err = 1;
        goto cleanup;
    }
    
    int64_t y_10426 = (int64_t) -1 + partition_sizze_10424;
    
    for (int64_t write_iter_10733 = 0; write_iter_10733 < n_9779; write_iter_10733++) {
        int64_t write_iv_10735 = ((int64_t *) mem_10750)[write_iter_10733];
        int64_t write_iv_10736 = ((int64_t *) mem_10746)[write_iter_10733];
        int64_t write_iv_10737 = ((int64_t *) mem_10748)[write_iter_10733];
        int64_t write_iv_10738 = ((int64_t *) arr_mem_10744.mem)[write_iter_10733];
        bool is_this_one_10432 = write_iv_10735 == (int64_t) 0;
        bool is_this_one_10433 = write_iv_10735 == (int64_t) 1;
        int64_t this_offset_10434 = y_10426 + write_iv_10737;
        int64_t total_res_10435;
        
        if (is_this_one_10433) {
            total_res_10435 = this_offset_10434;
        } else {
            total_res_10435 = (int64_t) -1;
        }
        
        int64_t this_offset_10436 = (int64_t) -1 + write_iv_10736;
        int64_t total_res_10437;
        
        if (is_this_one_10432) {
            total_res_10437 = this_offset_10436;
        } else {
            total_res_10437 = total_res_10435;
        }
        if (sle64((int64_t) 0, total_res_10437) && slt64(total_res_10437, n_9779)) {
            ((int64_t *) mem_10770.mem)[total_res_10437] = write_iv_10738;
        }
    }
    if (memblock_alloc(ctx, &mem_10781, bytes_10780, "mem_10781")) {
        err = 1;
        goto cleanup;
    }
    lmad_copy_8b(ctx, 1, (uint64_t *) mem_10781.mem, (int64_t) 0, (int64_t []) {(int64_t) 1}, (uint64_t *) mem_10770.mem, (int64_t) 0 + (int64_t) 1 * partition_sizze_10424, (int64_t []) {(int64_t) 1}, (int64_t []) {j_m_i_10450});
    if (memblock_set(ctx, &mem_out_10791, &mem_10770, "mem_10770") != 0)
        return 1;
    if (memblock_set(ctx, &mem_out_10792, &mem_10781, "mem_10781") != 0)
        return 1;
    prim_out_10793 = partition_sizze_10424;
    prim_out_10794 = j_m_i_10450;
    if (memblock_set(ctx, &*mem_out_p_10819, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    if (memblock_set(ctx, &*mem_out_p_10820, &mem_out_10792, "mem_out_10792") != 0)
        return 1;
    *out_prim_out_10821 = prim_out_10793;
    *out_prim_out_10822 = prim_out_10794;
    
  cleanup:
    {
        free(mem_10746);
        free(mem_10748);
        free(mem_10750);
        if (memblock_unref(ctx, &mem_10781, "mem_10781") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_10770, "mem_10770") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10792, "mem_out_10792") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_population_variance_array(struct futhark_context *ctx, double *out_prim_out_10826, struct memblock arr_mem_10744, int64_t n_9516)
{
    (void) ctx;
    
    int err = 0;
    double prim_out_10791;
    bool cond_10323 = n_9516 == (int64_t) 0;
    double population_variance_array_res_10324;
    
    if (cond_10323) {
        population_variance_array_res_10324 = NAN;
    } else {
        double defunc_0_reduce_res_10601;
        double redout_10719 = 0.0;
        
        for (int64_t i_10720 = 0; i_10720 < n_9516; i_10720++) {
            double x_10326 = ((double *) arr_mem_10744.mem)[i_10720];
            double defunc_0_op_res_10329 = x_10326 + redout_10719;
            double redout_tmp_10792 = defunc_0_op_res_10329;
            
            redout_10719 = redout_tmp_10792;
        }
        defunc_0_reduce_res_10601 = redout_10719;
        
        double i64_res_10330 = sitofp_i64_f64(n_9516);
        double mean_10331 = defunc_0_reduce_res_10601 / i64_res_10330;
        double defunc_0_reduce_res_10602;
        double redout_10721 = 0.0;
        
        for (int64_t i_10722 = 0; i_10722 < n_9516; i_10722++) {
            double eta_p_10595 = ((double *) arr_mem_10744.mem)[i_10722];
            double zt_lhs_10596 = eta_p_10595 - mean_10331;
            double lifted_lambda_res_10597 = zt_lhs_10596 * zt_lhs_10596;
            double defunc_0_op_res_10341 = lifted_lambda_res_10597 + redout_10721;
            double redout_tmp_10793 = defunc_0_op_res_10341;
            
            redout_10721 = redout_tmp_10793;
        }
        defunc_0_reduce_res_10602 = redout_10721;
        
        double population_variance_array_res_f_res_10343 = defunc_0_reduce_res_10602 / i64_res_10330;
        
        population_variance_array_res_10324 = population_variance_array_res_f_res_10343;
    }
    prim_out_10791 = population_variance_array_res_10324;
    *out_prim_out_10826 = prim_out_10791;
    
  cleanup:
    { }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_scatter_array(struct futhark_context *ctx, struct memblock *mem_out_p_10827, struct memblock dest_mem_10744, struct memblock indices_mem_10745, struct memblock values_mem_10746, int64_t n_8562, int64_t m_8563)
{
    (void) ctx;
    
    int err = 0;
    int64_t mem_10748_cached_sizze_10828 = 0;
    unsigned char *mem_10748 = NULL;
    struct memblock mem_10756;
    
    mem_10756.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    int64_t bytes_10747 = (int64_t) 8 * n_8562;
    
    if (mem_10748_cached_sizze_10828 < bytes_10747) {
        err = lexical_realloc(ctx, &mem_10748, &mem_10748_cached_sizze_10828, bytes_10747);
        if (err != FUTHARK_SUCCESS)
            goto cleanup;
    }
    for (int64_t nest_i_10792 = 0; nest_i_10792 < n_8562; nest_i_10792++) {
        ((int64_t *) mem_10748)[nest_i_10792] = (int64_t) -1;
    }
    for (int64_t iter_10719 = 0; iter_10719 < m_8563; iter_10719++) {
        int64_t pixel_10721 = ((int64_t *) indices_mem_10745.mem)[iter_10719];
        bool less_than_zzero_10723 = slt64(pixel_10721, (int64_t) 0);
        bool greater_than_sizze_10724 = sle64(n_8562, pixel_10721);
        bool outside_bounds_dim_10725 = less_than_zzero_10723 || greater_than_sizze_10724;
        
        if (!outside_bounds_dim_10725) {
            int64_t read_hist_10727 = ((int64_t *) mem_10748)[pixel_10721];
            int64_t max_res_10472 = smax64(iter_10719, read_hist_10727);
            
            ((int64_t *) mem_10748)[pixel_10721] = max_res_10472;
        }
    }
    if (memblock_alloc(ctx, &mem_10756, bytes_10747, "mem_10756")) {
        err = 1;
        goto cleanup;
    }
    for (int64_t i_10732 = 0; i_10732 < n_8562; i_10732++) {
        int64_t eta_p_10476 = ((int64_t *) dest_mem_10744.mem)[i_10732];
        int64_t eta_p_10477 = ((int64_t *) mem_10748)[i_10732];
        bool cond_10478 = sle64((int64_t) 0, eta_p_10477);
        int64_t lifted_lambda_res_10479;
        
        if (cond_10478) {
            bool y_10594 = slt64(eta_p_10477, m_8563);
            bool bounds_check_10595 = cond_10478 && y_10594;
            bool index_certs_10596;
            
            if (!bounds_check_10595) {
                set_error(ctx, msgprintf("Error: %s%lld%s%lld%s\n\nBacktrace:\n%s", "Index [", (long long) eta_p_10477, "] out of bounds for array of shape [", (long long) m_8563, "].", "-> #0  main.fut:55:38-47\n   #1  /prelude/soacs.fut:67:23-24\n   #2  /prelude/soacs.fut:67:27-37\n   #3  main.fut:53:1-55:68\n"));
                err = FUTHARK_PROGRAM_ERROR;
                goto cleanup;
            }
            
            int64_t lifted_lambda_res_t_res_10597 = ((int64_t *) values_mem_10746.mem)[eta_p_10477];
            
            lifted_lambda_res_10479 = lifted_lambda_res_t_res_10597;
        } else {
            lifted_lambda_res_10479 = eta_p_10476;
        }
        ((int64_t *) mem_10756.mem)[i_10732] = lifted_lambda_res_10479;
    }
    if (memblock_set(ctx, &mem_out_10791, &mem_10756, "mem_10756") != 0)
        return 1;
    if (memblock_set(ctx, &*mem_out_p_10827, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    
  cleanup:
    {
        free(mem_10748);
        if (memblock_unref(ctx, &mem_10756, "mem_10756") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_softmax(struct futhark_context *ctx, struct memblock *mem_out_p_10829, struct memblock arr_mem_10744, int64_t n_9032)
{
    (void) ctx;
    
    int err = 0;
    int64_t mem_10746_cached_sizze_10830 = 0;
    unsigned char *mem_10746 = NULL;
    int64_t mem_10754_cached_sizze_10831 = 0;
    unsigned char *mem_10754 = NULL;
    struct memblock mem_10762;
    
    mem_10762.references = NULL;
    
    struct memblock mem_10770;
    
    mem_10770.references = NULL;
    
    struct memblock ext_mem_10779;
    
    ext_mem_10779.references = NULL;
    
    struct memblock mem_10781;
    
    mem_10781.references = NULL;
    
    struct memblock ext_mem_10784;
    
    ext_mem_10784.references = NULL;
    
    struct memblock ext_mem_10787;
    
    ext_mem_10787.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    bool cond_10546 = n_9032 == (int64_t) 0;
    int64_t bytes_10745 = (int64_t) 8 * n_9032;
    
    if (cond_10546) {
        if (memblock_set(ctx, &ext_mem_10787, &arr_mem_10744, "arr_mem_10744") != 0)
            return 1;
    } else {
        if (mem_10746_cached_sizze_10830 < bytes_10745) {
            err = lexical_realloc(ctx, &mem_10746, &mem_10746_cached_sizze_10830, bytes_10745);
            if (err != FUTHARK_SUCCESS)
                goto cleanup;
        }
        
        double defunc_0_reduce_res_10717;
        double redout_10720 = -INFINITY;
        
        for (int64_t i_10722 = 0; i_10722 < n_9032; i_10722++) {
            double eta_p_10595 = ((double *) arr_mem_10744.mem)[i_10722];
            bool isnan_res_10596 = futrts_isnan64(eta_p_10595);
            double lifted_lambda_res_10597;
            
            if (isnan_res_10596) {
                lifted_lambda_res_10597 = -INFINITY;
            } else {
                lifted_lambda_res_10597 = eta_p_10595;
            }
            
            double max_res_10556 = fmax64(lifted_lambda_res_10597, redout_10720);
            
            ((double *) mem_10746)[i_10722] = lifted_lambda_res_10597;
            
            double redout_tmp_10792 = max_res_10556;
            
            redout_10720 = redout_tmp_10792;
        }
        defunc_0_reduce_res_10717 = redout_10720;
        
        bool cond_10557 = defunc_0_reduce_res_10717 == -INFINITY;
        bool cond_10562 = defunc_0_reduce_res_10717 == INFINITY;
        
        if (cond_10557) {
            double i64_res_10687 = sitofp_i64_f64(n_9032);
            double replicate_arg1_10688 = 1.0 / i64_res_10687;
            
            if (memblock_alloc(ctx, &mem_10781, bytes_10745, "mem_10781")) {
                err = 1;
                goto cleanup;
            }
            for (int64_t nest_i_10794 = 0; nest_i_10794 < n_9032; nest_i_10794++) {
                ((double *) mem_10781.mem)[nest_i_10794] = replicate_arg1_10688;
            }
            if (memblock_set(ctx, &ext_mem_10784, &mem_10781, "mem_10781") != 0)
                return 1;
        } else {
            if (cond_10562) {
                int64_t defunc_0_reduce_res_10693;
                int64_t redout_10724 = (int64_t) 0;
                
                for (int64_t i_10725 = 0; i_10725 < n_9032; i_10725++) {
                    double eta_p_10694 = ((double *) mem_10746)[i_10725];
                    bool cond_10695 = eta_p_10694 == INFINITY;
                    int64_t lifted_lambda_res_10696 = btoi_bool_i64(cond_10695);
                    int64_t defunc_0_op_res_10699 = add64(lifted_lambda_res_10696, redout_10724);
                    int64_t redout_tmp_10795 = defunc_0_op_res_10699;
                    
                    redout_10724 = redout_tmp_10795;
                }
                defunc_0_reduce_res_10693 = redout_10724;
                
                double i64_res_10704 = sitofp_i64_f64(defunc_0_reduce_res_10693);
                
                if (memblock_alloc(ctx, &mem_10770, bytes_10745, "mem_10770")) {
                    err = 1;
                    goto cleanup;
                }
                for (int64_t i_10728 = 0; i_10728 < n_9032; i_10728++) {
                    double eta_p_10706 = ((double *) mem_10746)[i_10728];
                    bool cond_10707 = eta_p_10706 == INFINITY;
                    double lifted_lambda_res_10708;
                    
                    if (cond_10707) {
                        double lifted_lambda_res_t_res_10709 = 1.0 / i64_res_10704;
                        
                        lifted_lambda_res_10708 = lifted_lambda_res_t_res_10709;
                    } else {
                        lifted_lambda_res_10708 = 0.0;
                    }
                    ((double *) mem_10770.mem)[i_10728] = lifted_lambda_res_10708;
                }
                if (memblock_set(ctx, &ext_mem_10779, &mem_10770, "mem_10770") != 0)
                    return 1;
            } else {
                if (mem_10754_cached_sizze_10831 < bytes_10745) {
                    err = lexical_realloc(ctx, &mem_10754, &mem_10754_cached_sizze_10831, bytes_10745);
                    if (err != FUTHARK_SUCCESS)
                        goto cleanup;
                }
                
                double defunc_0_reduce_res_10714;
                double redout_10731 = 0.0;
                
                for (int64_t i_10733 = 0; i_10733 < n_9032; i_10733++) {
                    double eta_p_10627 = ((double *) mem_10746)[i_10733];
                    double exp_arg0_10628 = eta_p_10627 - defunc_0_reduce_res_10717;
                    double exp_res_10629 = futrts_exp64(exp_arg0_10628);
                    double defunc_0_op_res_10587 = exp_res_10629 + redout_10731;
                    
                    ((double *) mem_10754)[i_10733] = exp_res_10629;
                    
                    double redout_tmp_10797 = defunc_0_op_res_10587;
                    
                    redout_10731 = redout_tmp_10797;
                }
                defunc_0_reduce_res_10714 = redout_10731;
                if (memblock_alloc(ctx, &mem_10762, bytes_10745, "mem_10762")) {
                    err = 1;
                    goto cleanup;
                }
                for (int64_t i_10737 = 0; i_10737 < n_9032; i_10737++) {
                    double eta_p_10589 = ((double *) mem_10754)[i_10737];
                    double lifted_lambda_res_10590 = eta_p_10589 / defunc_0_reduce_res_10714;
                    
                    ((double *) mem_10762.mem)[i_10737] = lifted_lambda_res_10590;
                }
                if (memblock_set(ctx, &ext_mem_10779, &mem_10762, "mem_10762") != 0)
                    return 1;
            }
            if (memblock_set(ctx, &ext_mem_10784, &ext_mem_10779, "ext_mem_10779") != 0)
                return 1;
        }
        if (memblock_set(ctx, &ext_mem_10787, &ext_mem_10784, "ext_mem_10784") != 0)
            return 1;
    }
    if (memblock_set(ctx, &mem_out_10791, &ext_mem_10787, "ext_mem_10787") != 0)
        return 1;
    if (memblock_set(ctx, &*mem_out_p_10829, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    
  cleanup:
    {
        free(mem_10746);
        free(mem_10754);
        if (memblock_unref(ctx, &mem_10762, "mem_10762") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_10770, "mem_10770") != 0)
            return 1;
        if (memblock_unref(ctx, &ext_mem_10779, "ext_mem_10779") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_10781, "mem_10781") != 0)
            return 1;
        if (memblock_unref(ctx, &ext_mem_10784, "ext_mem_10784") != 0)
            return 1;
        if (memblock_unref(ctx, &ext_mem_10787, "ext_mem_10787") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_std_dev_array(struct futhark_context *ctx, double *out_prim_out_10832, struct memblock arr_mem_10744, int64_t n_9617)
{
    (void) ctx;
    
    int err = 0;
    double prim_out_10791;
    bool cond_10394 = slt64(n_9617, (int64_t) 2);
    double variance_array_res_10395;
    
    if (cond_10394) {
        variance_array_res_10395 = NAN;
    } else {
        double defunc_0_reduce_res_10601;
        double redout_10719 = 0.0;
        
        for (int64_t i_10720 = 0; i_10720 < n_9617; i_10720++) {
            double x_10397 = ((double *) arr_mem_10744.mem)[i_10720];
            double defunc_0_op_res_10400 = x_10397 + redout_10719;
            double redout_tmp_10792 = defunc_0_op_res_10400;
            
            redout_10719 = redout_tmp_10792;
        }
        defunc_0_reduce_res_10601 = redout_10719;
        
        double i64_res_10401 = sitofp_i64_f64(n_9617);
        double mean_10402 = defunc_0_reduce_res_10601 / i64_res_10401;
        double defunc_0_reduce_res_10602;
        double redout_10721 = 0.0;
        
        for (int64_t i_10722 = 0; i_10722 < n_9617; i_10722++) {
            double eta_p_10595 = ((double *) arr_mem_10744.mem)[i_10722];
            double zt_lhs_10596 = eta_p_10595 - mean_10402;
            double lifted_lambda_res_10597 = zt_lhs_10596 * zt_lhs_10596;
            double defunc_0_op_res_10411 = lifted_lambda_res_10597 + redout_10721;
            double redout_tmp_10793 = defunc_0_op_res_10411;
            
            redout_10721 = redout_tmp_10793;
        }
        defunc_0_reduce_res_10602 = redout_10721;
        
        int64_t i64_arg0_10412 = sub64(n_9617, (int64_t) 1);
        double i64_res_10413 = sitofp_i64_f64(i64_arg0_10412);
        double variance_array_res_f_res_10414 = defunc_0_reduce_res_10602 / i64_res_10413;
        
        variance_array_res_10395 = variance_array_res_f_res_10414;
    }
    
    bool isnan_res_10415 = futrts_isnan64(variance_array_res_10395);
    double std_dev_array_res_10416;
    
    if (isnan_res_10415) {
        std_dev_array_res_10416 = variance_array_res_10395;
    } else {
        double max_res_10417 = fmax64(0.0, variance_array_res_10395);
        double sqrt_res_10418 = futrts_sqrt64(max_res_10417);
        
        std_dev_array_res_10416 = sqrt_res_10418;
    }
    prim_out_10791 = std_dev_array_res_10416;
    *out_prim_out_10832 = prim_out_10791;
    
  cleanup:
    { }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_sum_matrix(struct futhark_context *ctx, double *out_prim_out_10833, struct memblock mat_mem_10744, int64_t n_10008, int64_t m_10009)
{
    (void) ctx;
    
    int err = 0;
    double prim_out_10791;
    int64_t flat_dim_10270 = n_10008 * m_10009;
    double defunc_0_reduce_res_10594;
    double redout_10719 = 0.0;
    
    for (int64_t i_10720 = 0; i_10720 < flat_dim_10270; i_10720++) {
        int64_t new_index_10740 = squot64(i_10720, m_10009);
        int64_t binop_y_10742 = m_10009 * new_index_10740;
        int64_t new_index_10743 = i_10720 - binop_y_10742;
        double x_10273 = ((double *) mat_mem_10744.mem)[new_index_10740 * m_10009 + new_index_10743];
        double defunc_0_op_res_10276 = x_10273 + redout_10719;
        double redout_tmp_10792 = defunc_0_op_res_10276;
        
        redout_10719 = redout_tmp_10792;
    }
    defunc_0_reduce_res_10594 = redout_10719;
    prim_out_10791 = defunc_0_reduce_res_10594;
    *out_prim_out_10833 = prim_out_10791;
    
  cleanup:
    { }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_update_array(struct futhark_context *ctx, struct memblock *mem_out_p_10834, struct memblock arr_mem_10744, int64_t n_8376, int64_t index_8378, int64_t value_8379)
{
    (void) ctx;
    
    int err = 0;
    struct memblock mem_10746;
    
    mem_10746.references = NULL;
    
    struct memblock ext_mem_10747;
    
    ext_mem_10747.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    bool cond_10238 = slt64(index_8378, (int64_t) 0);
    bool cond_f_res_10239 = sle64(n_8376, index_8378);
    bool x_10240 = !cond_10238;
    bool y_10241 = cond_f_res_10239 && x_10240;
    bool cond_10242 = cond_10238 || y_10241;
    int64_t bytes_10745 = (int64_t) 8 * n_8376;
    
    if (cond_10242) {
        if (memblock_set(ctx, &ext_mem_10747, &arr_mem_10744, "arr_mem_10744") != 0)
            return 1;
    } else {
        bool x_10246 = sle64((int64_t) 0, index_8378);
        bool y_10247 = slt64(index_8378, n_8376);
        bool bounds_check_10248 = x_10246 && y_10247;
        bool index_certs_10249;
        
        if (!bounds_check_10248) {
            set_error(ctx, msgprintf("Error: %s%lld%s%lld%s\n\nBacktrace:\n%s", "Index [", (long long) index_8378, "] out of bounds for array of shape [", (long long) n_8376, "].", "-> #0  main.fut:46:8-39\n   #1  main.fut:43:1-46:39\n"));
            err = FUTHARK_PROGRAM_ERROR;
            goto cleanup;
        }
        if (memblock_alloc(ctx, &mem_10746, bytes_10745, "mem_10746")) {
            err = 1;
            goto cleanup;
        }
        lmad_copy_8b(ctx, 1, (uint64_t *) mem_10746.mem, (int64_t) 0, (int64_t []) {(int64_t) 1}, (uint64_t *) arr_mem_10744.mem, (int64_t) 0, (int64_t []) {(int64_t) 1}, (int64_t []) {n_8376});
        ((int64_t *) mem_10746.mem)[index_8378] = value_8379;
        if (memblock_set(ctx, &ext_mem_10747, &mem_10746, "mem_10746") != 0)
            return 1;
    }
    if (memblock_set(ctx, &mem_out_10791, &ext_mem_10747, "ext_mem_10747") != 0)
        return 1;
    if (memblock_set(ctx, &*mem_out_p_10834, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    
  cleanup:
    {
        if (memblock_unref(ctx, &mem_10746, "mem_10746") != 0)
            return 1;
        if (memblock_unref(ctx, &ext_mem_10747, "ext_mem_10747") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_update_matrix(struct futhark_context *ctx, struct memblock *mem_out_p_10835, struct memblock mat_mem_10744, int64_t n_8417, int64_t m_8418, int64_t row_8420, int64_t col_8421, int64_t value_8422)
{
    (void) ctx;
    
    int err = 0;
    struct memblock mem_10747;
    
    mem_10747.references = NULL;
    
    struct memblock ext_mem_10748;
    
    ext_mem_10748.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    bool cond_10240 = slt64(row_8420, (int64_t) 0);
    bool cond_f_res_10241 = sle64(n_8417, row_8420);
    bool x_10242 = !cond_10240;
    bool y_10243 = cond_f_res_10241 && x_10242;
    bool cond_10244 = cond_10240 || y_10243;
    bool cond_f_res_10245 = slt64(col_8421, (int64_t) 0);
    bool x_10246 = !cond_10244;
    bool y_10247 = cond_f_res_10245 && x_10246;
    bool cond_10248 = cond_10244 || y_10247;
    bool cond_f_res_10249 = sle64(m_8418, col_8421);
    bool x_10250 = !cond_10248;
    bool y_10251 = cond_f_res_10249 && x_10250;
    bool cond_10252 = cond_10248 || y_10251;
    int64_t binop_x_10745 = (int64_t) 8 * n_8417;
    int64_t bytes_10746 = m_8418 * binop_x_10745;
    
    if (cond_10252) {
        if (memblock_set(ctx, &ext_mem_10748, &mat_mem_10744, "mat_mem_10744") != 0)
            return 1;
    } else {
        bool x_10256 = sle64((int64_t) 0, row_8420);
        bool y_10257 = slt64(row_8420, n_8417);
        bool bounds_check_10258 = x_10256 && y_10257;
        bool x_10259 = sle64((int64_t) 0, col_8421);
        bool y_10260 = slt64(col_8421, m_8418);
        bool bounds_check_10261 = x_10259 && y_10260;
        bool index_ok_10262 = bounds_check_10258 && bounds_check_10261;
        bool index_certs_10263;
        
        if (!index_ok_10262) {
            set_error(ctx, msgprintf("Error: %s%lld%s%lld%s%lld%s%lld%s\n\nBacktrace:\n%s", "Index [", (long long) row_8420, ", ", (long long) col_8421, "] out of bounds for array of shape [", (long long) n_8417, "][", (long long) m_8418, "].", "-> #0  main.fut:51:8-42\n   #1  main.fut:48:1-51:42\n"));
            err = FUTHARK_PROGRAM_ERROR;
            goto cleanup;
        }
        if (memblock_alloc(ctx, &mem_10747, bytes_10746, "mem_10747")) {
            err = 1;
            goto cleanup;
        }
        lmad_copy_8b(ctx, 2, (uint64_t *) mem_10747.mem, (int64_t) 0, (int64_t []) {m_8418, (int64_t) 1}, (uint64_t *) mat_mem_10744.mem, (int64_t) 0, (int64_t []) {m_8418, (int64_t) 1}, (int64_t []) {n_8417, m_8418});
        ((int64_t *) mem_10747.mem)[row_8420 * m_8418 + col_8421] = value_8422;
        if (memblock_set(ctx, &ext_mem_10748, &mem_10747, "mem_10747") != 0)
            return 1;
    }
    if (memblock_set(ctx, &mem_out_10791, &ext_mem_10748, "ext_mem_10748") != 0)
        return 1;
    if (memblock_set(ctx, &*mem_out_p_10835, &mem_out_10791, "mem_out_10791") != 0)
        return 1;
    
  cleanup:
    {
        if (memblock_unref(ctx, &mem_10747, "mem_10747") != 0)
            return 1;
        if (memblock_unref(ctx, &ext_mem_10748, "ext_mem_10748") != 0)
            return 1;
        if (memblock_unref(ctx, &mem_out_10791, "mem_out_10791") != 0)
            return 1;
    }
    return err;
}
FUTHARK_FUN_ATTR int futrts_entry_variance_array(struct futhark_context *ctx, double *out_prim_out_10836, struct memblock arr_mem_10744, int64_t n_9605)
{
    (void) ctx;
    
    int err = 0;
    double prim_out_10791;
    bool cond_10323 = slt64(n_9605, (int64_t) 2);
    double variance_array_res_10324;
    
    if (cond_10323) {
        variance_array_res_10324 = NAN;
    } else {
        double defunc_0_reduce_res_10601;
        double redout_10719 = 0.0;
        
        for (int64_t i_10720 = 0; i_10720 < n_9605; i_10720++) {
            double x_10326 = ((double *) arr_mem_10744.mem)[i_10720];
            double defunc_0_op_res_10329 = x_10326 + redout_10719;
            double redout_tmp_10792 = defunc_0_op_res_10329;
            
            redout_10719 = redout_tmp_10792;
        }
        defunc_0_reduce_res_10601 = redout_10719;
        
        double i64_res_10330 = sitofp_i64_f64(n_9605);
        double mean_10331 = defunc_0_reduce_res_10601 / i64_res_10330;
        double defunc_0_reduce_res_10602;
        double redout_10721 = 0.0;
        
        for (int64_t i_10722 = 0; i_10722 < n_9605; i_10722++) {
            double eta_p_10595 = ((double *) arr_mem_10744.mem)[i_10722];
            double zt_lhs_10596 = eta_p_10595 - mean_10331;
            double lifted_lambda_res_10597 = zt_lhs_10596 * zt_lhs_10596;
            double defunc_0_op_res_10341 = lifted_lambda_res_10597 + redout_10721;
            double redout_tmp_10793 = defunc_0_op_res_10341;
            
            redout_10721 = redout_tmp_10793;
        }
        defunc_0_reduce_res_10602 = redout_10721;
        
        int64_t i64_arg0_10342 = sub64(n_9605, (int64_t) 1);
        double i64_res_10343 = sitofp_i64_f64(i64_arg0_10342);
        double variance_array_res_f_res_10344 = defunc_0_reduce_res_10602 / i64_res_10343;
        
        variance_array_res_10324 = variance_array_res_f_res_10344;
    }
    prim_out_10791 = variance_array_res_10324;
    *out_prim_out_10836 = prim_out_10791;
    
  cleanup:
    { }
    return err;
}
FUTHARK_FUN_ATTR int futrts_is_finite_value_4544(struct futhark_context *ctx, bool *out_prim_out_10837, double x_8641)
{
    (void) ctx;
    
    int err = 0;
    bool prim_out_10791;
    bool isnan_res_10235 = futrts_isnan64(x_8641);
    bool cond_8644 = !isnan_res_10235;
    bool isinf_res_10237 = futrts_isinf64(x_8641);
    bool is_finite_value_res_t_res_8648 = !isinf_res_10237;
    bool x_10591 = cond_8644 && is_finite_value_res_t_res_8648;
    
    prim_out_10791 = x_10591;
    *out_prim_out_10837 = prim_out_10791;
    
  cleanup:
    { }
    return err;
}

int futhark_entry_all_positive(struct futhark_context *ctx, bool *out0, const struct futhark_i64_1d *in0)
{
    int64_t n_10161 = (int64_t) 0;
    bool prim_out_10791 = 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_10161 = in0->shape[0];
    if (!(n_10161 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_all_positive(ctx, &prim_out_10791, arr_mem_10744, n_10161);
        if (ret == 0) {
            *out0 = prim_out_10791;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_any_positive(struct futhark_context *ctx, bool *out0, const struct futhark_i64_1d *in0)
{
    int64_t n_10109 = (int64_t) 0;
    bool prim_out_10791 = 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_10109 = in0->shape[0];
    if (!(n_10109 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_any_positive(ctx, &prim_out_10791, arr_mem_10744, n_10109);
        if (ret == 0) {
            *out0 = prim_out_10791;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_convolve_1d(struct futhark_context *ctx, struct futhark_f64_1d **out0, const struct futhark_f64_1d *in0, const struct futhark_f64_1d *in1)
{
    int64_t n_8287 = (int64_t) 0;
    int64_t k_8288 = (int64_t) 0;
    int64_t prim_out_10792 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock kernel_mem_10745;
    
    kernel_mem_10745.references = NULL;
    
    struct memblock signal_mem_10744;
    
    signal_mem_10744.references = NULL;
    signal_mem_10744 = in0->mem;
    n_8287 = in0->shape[0];
    kernel_mem_10745 = in1->mem;
    k_8288 = in1->shape[0];
    if (!(n_8287 == in0->shape[0] && k_8288 == in1->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_convolve_1d(ctx, &mem_out_10791, &prim_out_10792, signal_mem_10744, kernel_mem_10745, n_8287, k_8288);
        if (ret == 0) {
            assert((*out0 = (struct futhark_f64_1d *) malloc(sizeof(struct futhark_f64_1d))) != NULL);
            (*out0)->mem = mem_out_10791;
            (*out0)->shape[0] = prim_out_10792;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_cosine_similarity(struct futhark_context *ctx, double *out0, const struct futhark_f64_1d *in0, const struct futhark_f64_1d *in1)
{
    int64_t n_9428 = (int64_t) 0;
    double prim_out_10791 = 0.0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock b_mem_10745;
    
    b_mem_10745.references = NULL;
    
    struct memblock a_mem_10744;
    
    a_mem_10744.references = NULL;
    a_mem_10744 = in0->mem;
    n_9428 = in0->shape[0];
    b_mem_10745 = in1->mem;
    n_9428 = in1->shape[0];
    if (!(n_9428 == in0->shape[0] && n_9428 == in1->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_cosine_similarity(ctx, &prim_out_10791, a_mem_10744, b_mem_10745, n_9428);
        if (ret == 0) {
            *out0 = prim_out_10791;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_exponential_moving_average(struct futhark_context *ctx, struct futhark_f64_1d **out0, const struct futhark_f64_1d *in0, const double in1)
{
    int64_t n_9965 = (int64_t) 0;
    double alpha_9967 = 0.0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_9965 = in0->shape[0];
    alpha_9967 = in1;
    if (!(n_9965 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_exponential_moving_average(ctx, &mem_out_10791, arr_mem_10744, n_9965, alpha_9967);
        if (ret == 0) {
            assert((*out0 = (struct futhark_f64_1d *) malloc(sizeof(struct futhark_f64_1d))) != NULL);
            (*out0)->mem = mem_out_10791;
            (*out0)->shape[0] = n_9965;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_find_max(struct futhark_context *ctx, bool *out0, int64_t *out1, const struct futhark_i64_1d *in0)
{
    int64_t n_8597 = (int64_t) 0;
    bool prim_out_10791 = 0;
    int64_t prim_out_10792 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_8597 = in0->shape[0];
    if (!(n_8597 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_find_max(ctx, &prim_out_10791, &prim_out_10792, arr_mem_10744, n_8597);
        if (ret == 0) {
            *out0 = prim_out_10791;
            *out1 = prim_out_10792;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_find_min(struct futhark_context *ctx, bool *out0, int64_t *out1, const struct futhark_i64_1d *in0)
{
    int64_t n_8630 = (int64_t) 0;
    bool prim_out_10791 = 0;
    int64_t prim_out_10792 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_8630 = in0->shape[0];
    if (!(n_8630 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_find_min(ctx, &prim_out_10791, &prim_out_10792, arr_mem_10744, n_8630);
        if (ret == 0) {
            *out0 = prim_out_10791;
            *out1 = prim_out_10792;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_flatten_3d_array(struct futhark_context *ctx, struct futhark_i64_1d **out0, const struct futhark_i64_3d *in0)
{
    int64_t n_10054 = (int64_t) 0;
    int64_t m_10055 = (int64_t) 0;
    int64_t l_10056 = (int64_t) 0;
    int64_t prim_out_10792 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_10054 = in0->shape[0];
    m_10055 = in0->shape[1];
    l_10056 = in0->shape[2];
    if (!(n_10054 == in0->shape[0] && (m_10055 == in0->shape[1] && l_10056 == in0->shape[2]))) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_flatten_3d_array(ctx, &mem_out_10791, &prim_out_10792, arr_mem_10744, n_10054, m_10055, l_10056);
        if (ret == 0) {
            assert((*out0 = (struct futhark_i64_1d *) malloc(sizeof(struct futhark_i64_1d))) != NULL);
            (*out0)->mem = mem_out_10791;
            (*out0)->shape[0] = prim_out_10792;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_gather(struct futhark_context *ctx, struct futhark_i64_1d **out0, const struct futhark_i64_1d *in0, const struct futhark_i64_1d *in1, const int64_t in2)
{
    int64_t n_8345 = (int64_t) 0;
    int64_t m_8346 = (int64_t) 0;
    int64_t fill_8349 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock indices_mem_10745;
    
    indices_mem_10745.references = NULL;
    
    struct memblock src_mem_10744;
    
    src_mem_10744.references = NULL;
    src_mem_10744 = in0->mem;
    n_8345 = in0->shape[0];
    indices_mem_10745 = in1->mem;
    m_8346 = in1->shape[0];
    fill_8349 = in2;
    if (!(n_8345 == in0->shape[0] && m_8346 == in1->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_gather(ctx, &mem_out_10791, src_mem_10744, indices_mem_10745, n_8345, m_8346, fill_8349);
        if (ret == 0) {
            assert((*out0 = (struct futhark_i64_1d *) malloc(sizeof(struct futhark_i64_1d))) != NULL);
            (*out0)->mem = mem_out_10791;
            (*out0)->shape[0] = m_8346;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_histogram(struct futhark_context *ctx, struct futhark_i64_1d **out0, const struct futhark_i64_1d *in0, const int64_t in1)
{
    int64_t n_7985 = (int64_t) 0;
    int64_t num_bins_7987 = (int64_t) 0;
    int64_t prim_out_10792 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_7985 = in0->shape[0];
    num_bins_7987 = in1;
    if (!(n_7985 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_histogram(ctx, &mem_out_10791, &prim_out_10792, arr_mem_10744, n_7985, num_bins_7987);
        if (ret == 0) {
            assert((*out0 = (struct futhark_i64_1d *) malloc(sizeof(struct futhark_i64_1d))) != NULL);
            (*out0)->mem = mem_out_10791;
            (*out0)->shape[0] = prim_out_10792;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_min_max_normalize(struct futhark_context *ctx, struct futhark_f64_1d **out0, const struct futhark_f64_1d *in0)
{
    int64_t n_8800 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_8800 = in0->shape[0];
    if (!(n_8800 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_min_max_normalizze(ctx, &mem_out_10791, arr_mem_10744, n_8800);
        if (ret == 0) {
            assert((*out0 = (struct futhark_f64_1d *) malloc(sizeof(struct futhark_f64_1d))) != NULL);
            (*out0)->mem = mem_out_10791;
            (*out0)->shape[0] = n_8800;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_moving_average(struct futhark_context *ctx, struct futhark_f64_1d **out0, const struct futhark_f64_1d *in0, const int64_t in1)
{
    int64_t n_8115 = (int64_t) 0;
    int64_t window_8117 = (int64_t) 0;
    int64_t prim_out_10792 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_8115 = in0->shape[0];
    window_8117 = in1;
    if (!(n_8115 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_moving_average(ctx, &mem_out_10791, &prim_out_10792, arr_mem_10744, n_8115, window_8117);
        if (ret == 0) {
            assert((*out0 = (struct futhark_f64_1d *) malloc(sizeof(struct futhark_f64_1d))) != NULL);
            (*out0)->mem = mem_out_10791;
            (*out0)->shape[0] = prim_out_10792;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_partition_array(struct futhark_context *ctx, struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 **out0, const struct futhark_i64_1d *in0, const int64_t in1)
{
    int64_t n_9779 = (int64_t) 0;
    int64_t pivot_9781 = (int64_t) 0;
    int64_t prim_out_10793 = (int64_t) 0;
    int64_t prim_out_10794 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10792;
    
    mem_out_10792.references = NULL;
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_9779 = in0->shape[0];
    pivot_9781 = in1;
    if (!(n_9779 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_partition_array(ctx, &mem_out_10791, &mem_out_10792, &prim_out_10793, &prim_out_10794, arr_mem_10744, n_9779, pivot_9781);
        if (ret == 0) {
            assert((*out0 = (struct futhark_opaque_tup2_arr1d_i64_arr1d_i64 *) malloc(sizeof(struct futhark_opaque_tup2_arr1d_i64_arr1d_i64))) != NULL);
            assert(((*out0)->v0 = (struct futhark_i64_1d *) malloc(sizeof(struct futhark_i64_1d))) != NULL);
            (*out0)->v0->mem = mem_out_10791;
            (*out0)->v0->shape[0] = prim_out_10793;
            assert(((*out0)->v1 = (struct futhark_i64_1d *) malloc(sizeof(struct futhark_i64_1d))) != NULL);
            (*out0)->v1->mem = mem_out_10792;
            (*out0)->v1->shape[0] = prim_out_10794;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_population_variance_array(struct futhark_context *ctx, double *out0, const struct futhark_f64_1d *in0)
{
    int64_t n_9516 = (int64_t) 0;
    double prim_out_10791 = 0.0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_9516 = in0->shape[0];
    if (!(n_9516 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_population_variance_array(ctx, &prim_out_10791, arr_mem_10744, n_9516);
        if (ret == 0) {
            *out0 = prim_out_10791;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_scatter_array(struct futhark_context *ctx, struct futhark_i64_1d **out0, const struct futhark_i64_1d *in0, const struct futhark_i64_1d *in1, const struct futhark_i64_1d *in2)
{
    int64_t n_8562 = (int64_t) 0;
    int64_t m_8563 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock values_mem_10746;
    
    values_mem_10746.references = NULL;
    
    struct memblock indices_mem_10745;
    
    indices_mem_10745.references = NULL;
    
    struct memblock dest_mem_10744;
    
    dest_mem_10744.references = NULL;
    dest_mem_10744 = in0->mem;
    n_8562 = in0->shape[0];
    indices_mem_10745 = in1->mem;
    m_8563 = in1->shape[0];
    values_mem_10746 = in2->mem;
    m_8563 = in2->shape[0];
    if (!(n_8562 == in0->shape[0] && (m_8563 == in1->shape[0] && m_8563 == in2->shape[0]))) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_scatter_array(ctx, &mem_out_10791, dest_mem_10744, indices_mem_10745, values_mem_10746, n_8562, m_8563);
        if (ret == 0) {
            assert((*out0 = (struct futhark_i64_1d *) malloc(sizeof(struct futhark_i64_1d))) != NULL);
            (*out0)->mem = mem_out_10791;
            (*out0)->shape[0] = n_8562;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_softmax(struct futhark_context *ctx, struct futhark_f64_1d **out0, const struct futhark_f64_1d *in0)
{
    int64_t n_9032 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_9032 = in0->shape[0];
    if (!(n_9032 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_softmax(ctx, &mem_out_10791, arr_mem_10744, n_9032);
        if (ret == 0) {
            assert((*out0 = (struct futhark_f64_1d *) malloc(sizeof(struct futhark_f64_1d))) != NULL);
            (*out0)->mem = mem_out_10791;
            (*out0)->shape[0] = n_9032;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_std_dev_array(struct futhark_context *ctx, double *out0, const struct futhark_f64_1d *in0)
{
    int64_t n_9617 = (int64_t) 0;
    double prim_out_10791 = 0.0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_9617 = in0->shape[0];
    if (!(n_9617 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_std_dev_array(ctx, &prim_out_10791, arr_mem_10744, n_9617);
        if (ret == 0) {
            *out0 = prim_out_10791;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_sum_matrix(struct futhark_context *ctx, double *out0, const struct futhark_f64_2d *in0)
{
    int64_t n_10008 = (int64_t) 0;
    int64_t m_10009 = (int64_t) 0;
    double prim_out_10791 = 0.0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mat_mem_10744;
    
    mat_mem_10744.references = NULL;
    mat_mem_10744 = in0->mem;
    n_10008 = in0->shape[0];
    m_10009 = in0->shape[1];
    if (!(n_10008 == in0->shape[0] && m_10009 == in0->shape[1])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_sum_matrix(ctx, &prim_out_10791, mat_mem_10744, n_10008, m_10009);
        if (ret == 0) {
            *out0 = prim_out_10791;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_update_array(struct futhark_context *ctx, struct futhark_i64_1d **out0, const struct futhark_i64_1d *in0, const int64_t in1, const int64_t in2)
{
    int64_t n_8376 = (int64_t) 0;
    int64_t index_8378 = (int64_t) 0;
    int64_t value_8379 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_8376 = in0->shape[0];
    index_8378 = in1;
    value_8379 = in2;
    if (!(n_8376 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_update_array(ctx, &mem_out_10791, arr_mem_10744, n_8376, index_8378, value_8379);
        if (ret == 0) {
            assert((*out0 = (struct futhark_i64_1d *) malloc(sizeof(struct futhark_i64_1d))) != NULL);
            (*out0)->mem = mem_out_10791;
            (*out0)->shape[0] = n_8376;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_update_matrix(struct futhark_context *ctx, struct futhark_i64_2d **out0, const struct futhark_i64_2d *in0, const int64_t in1, const int64_t in2, const int64_t in3)
{
    int64_t n_8417 = (int64_t) 0;
    int64_t m_8418 = (int64_t) 0;
    int64_t row_8420 = (int64_t) 0;
    int64_t col_8421 = (int64_t) 0;
    int64_t value_8422 = (int64_t) 0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock mem_out_10791;
    
    mem_out_10791.references = NULL;
    
    struct memblock mat_mem_10744;
    
    mat_mem_10744.references = NULL;
    mat_mem_10744 = in0->mem;
    n_8417 = in0->shape[0];
    m_8418 = in0->shape[1];
    row_8420 = in1;
    col_8421 = in2;
    value_8422 = in3;
    if (!(n_8417 == in0->shape[0] && m_8418 == in0->shape[1])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_update_matrix(ctx, &mem_out_10791, mat_mem_10744, n_8417, m_8418, row_8420, col_8421, value_8422);
        if (ret == 0) {
            assert((*out0 = (struct futhark_i64_2d *) malloc(sizeof(struct futhark_i64_2d))) != NULL);
            (*out0)->mem = mem_out_10791;
            (*out0)->shape[0] = n_8417;
            (*out0)->shape[1] = m_8418;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
int futhark_entry_variance_array(struct futhark_context *ctx, double *out0, const struct futhark_f64_1d *in0)
{
    int64_t n_9605 = (int64_t) 0;
    double prim_out_10791 = 0.0;
    int ret = 0;
    
    lock_lock(&ctx->lock);
    
    struct memblock arr_mem_10744;
    
    arr_mem_10744.references = NULL;
    arr_mem_10744 = in0->mem;
    n_9605 = in0->shape[0];
    if (!(n_9605 == in0->shape[0])) {
        ret = 1;
        set_error(ctx, msgprintf("Error: entry point arguments have invalid sizes.\n"));
    }
    if (ret == 0) {
        ret = futrts_entry_variance_array(ctx, &prim_out_10791, arr_mem_10744, n_9605);
        if (ret == 0) {
            *out0 = prim_out_10791;
        }
    }
    lock_unlock(&ctx->lock);
    return ret;
}
  
