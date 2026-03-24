VERSION := $(shell git describe --tags --always --dirty)
LDFLAGS := -s -w -X github.com/igorsheg/nts/cmd.Version=$(VERSION)

build:
	go build -ldflags="$(LDFLAGS)" -o nts .

install: build
	cp nts $(shell go env GOPATH)/bin/nts

clean:
	rm -f nts nts-*

.PHONY: build install clean
