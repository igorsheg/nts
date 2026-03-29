VERSION := $(shell git describe --tags --always --dirty)

build:
	zig build

release:
	zig build -Doptimize=ReleaseSafe

install: release
	cp zig-out/bin/nts $$(which nts 2>/dev/null || echo /usr/local/bin/nts)

cross: dist/nts-darwin-arm64 dist/nts-darwin-x64 dist/nts-linux-arm64 dist/nts-linux-x64

dist/nts-darwin-arm64:
	zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos
	mkdir -p dist
	cp zig-out/bin/nts dist/nts-darwin-arm64

dist/nts-darwin-x64:
	zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-macos
	mkdir -p dist
	cp zig-out/bin/nts dist/nts-darwin-x64

dist/nts-linux-arm64:
	zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-linux
	mkdir -p dist
	cp zig-out/bin/nts dist/nts-linux-arm64

dist/nts-linux-x64:
	zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux
	mkdir -p dist
	cp zig-out/bin/nts dist/nts-linux-x64

npm-stage: cross
	mkdir -p npm/nts-darwin-arm64/bin && cp dist/nts-darwin-arm64 npm/nts-darwin-arm64/bin/nts
	mkdir -p npm/nts-darwin-x64/bin   && cp dist/nts-darwin-x64   npm/nts-darwin-x64/bin/nts
	mkdir -p npm/nts-linux-arm64/bin  && cp dist/nts-linux-arm64  npm/nts-linux-arm64/bin/nts
	mkdir -p npm/nts-linux-x64/bin    && cp dist/nts-linux-x64    npm/nts-linux-x64/bin/nts

npm-publish: npm-stage
	cd npm/nts-darwin-arm64 && npm publish --access public
	cd npm/nts-darwin-x64   && npm publish --access public
	cd npm/nts-linux-arm64  && npm publish --access public
	cd npm/nts-linux-x64    && npm publish --access public
	cd npm/nts              && npm publish --access public

clean:
	rm -rf zig-out .zig-cache dist npm/nts-*/bin

.PHONY: build release install cross npm-stage npm-publish clean
