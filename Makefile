ZIG := ./zig

.PHONY: all build release clean deploy

all: build

build:
	$(ZIG) build -Doptimize=Debug

release:
	$(ZIG) build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl

clean:
	rm -rf .zig-cache zig-out

deploy:
	$(ZIG) build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl
	./deploy.sh

serve:
	$(ZIG) build -Doptimize=Debug
	./zig-out/bin/agdb-cloud
