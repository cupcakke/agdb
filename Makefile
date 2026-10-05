ZIG ?= zig
OPTIMIZE ?= Debug
RELEASE_OPTIMIZE ?= ReleaseSafe
RELEASE_TARGET ?= x86_64-linux-musl

.PHONY: all build release test fmt fmt-check check run-cloud run-wake clean deploy

all: check

build:
	$(ZIG) build -Doptimize=$(OPTIMIZE)

release:
	$(ZIG) build -Doptimize=$(RELEASE_OPTIMIZE) -Dtarget=$(RELEASE_TARGET)

test:
	$(ZIG) build test --summary all

fmt:
	$(ZIG) fmt src build.zig

fmt-check:
	$(ZIG) fmt --check src build.zig

check: fmt-check build test

run-cloud: build
	./zig-out/bin/agdb-cloud

run-wake: build
	./zig-out/bin/agdb-wake-proxy

deploy: fmt-check test release
	./deploy.sh

clean:
	rm -rf .zig-cache zig-out
