FIRST_GOPATH              := $(firstword $(subst :, ,$(GOPATH)))
PKGS                      := $(shell go list ./... | grep -v /tests | grep -v /xcpb | grep -v /gpb)
PKGSWIN                   := $(shell go list ./... | grep -v /tests | grep -v /xcpb | grep -v /gpb | grep -v "jsonapi")
GOFILES_NOVENDOR          := $(shell find . -name vendor -prune -o -type f -name '*.go' -not -name '*.pb.go' -print)
GOFILES_BUILD             := $(shell find . -type f -name '*.go' -not -name '*_test.go')
PROTOFILES                := $(shell find . -name vendor -prune -o -type f -name '*.proto' -print)
GOPASS_VERSION            ?= $(shell cat VERSION)
GOPASS_OUTPUT             ?= git-credential-gopass
GOPASS_REVISION           := $(shell cat COMMIT 2>/dev/null || git rev-parse --short=8 HEAD)
# Support reproducible builds by embedding date according to SOURCE_DATE_EPOCH if present
DATE                      := $(shell date -u -d "@$(SOURCE_DATE_EPOCH)" '+%FT%T%z' 2>/dev/null || date -u '+%FT%T%z')
BUILDFLAGS_NOPIE          := -trimpath -ldflags="-s -w -X main.version=$(GOPASS_VERSION) -X main.commit=$(GOPASS_REVISION) -X main.date=$(DATE)" -gcflags="-trimpath=$(GOPATH)" -asmflags="-trimpath=$(GOPATH)"
BUILDFLAGS                ?= $(BUILDFLAGS_NOPIE) -buildmode=pie
TESTFLAGS                 ?=
PWD                       := $(shell pwd)
PREFIX                    ?= $(GOPATH)
BINDIR                    ?= $(PREFIX)/bin
GO                        := GO111MODULE=on go
GOOS                      ?= $(shell go version | cut -d' ' -f4 | cut -d'/' -f1)
GOARCH                    ?= $(shell go version | cut -d' ' -f4 | cut -d'/' -f2)
TAGS                      ?= netgo
export GO111MODULE=on

OK := $(shell tput setaf 6; echo ' [OK]'; tput sgr0;)

all: build
build: $(GOPASS_OUTPUT)
travis: sysinfo crosscompile build install test codequality

sysinfo:
	@echo ">> SYSTEM INFORMATION"
	@echo -n "     PLATFORM: $(shell uname -a)"
	@printf '%s\n' '$(OK)'
	@echo -n "     PWD:    : $(shell pwd)"
	@printf '%s\n' '$(OK)'
	@echo -n "     GO      : $(shell go version)"
	@printf '%s\n' '$(OK)'
	@echo -n "     BUILDFLAGS: $(BUILDFLAGS)"
	@printf '%s\n' '$(OK)'
	@echo -n "     GIT     : $(shell git version)"
	@printf '%s\n' '$(OK)'
	@echo -n "     GPG1    : $(shell which gpg) $(shell gpg --version | head -1)"
	@printf '%s\n' '$(OK)'
	@echo -n "     GPG2    : $(shell which gpg2) $(shell gpg2 --version | head -1)"
	@printf '%s\n' '$(OK)'
	@echo -n "     GPG-Agent    : $(shell which gpg-agent) $(shell gpg-agent --version | head -1)"
	@printf '%s\n' '$(OK)'

clean:
	@echo -n ">> CLEAN"
	@$(GO) clean -i ./...
	@rm -f ./coverage-all.html
	@rm -f ./coverage-all.out
	@rm -f ./coverage.out
	@find . -type f -name "coverage.out" -delete
	@rm -f gopass_*.deb
	@rm -f gopass-*.pkg.tar.xz
	@rm -f gopass-*.rpm
	@rm -f gopass-*.tar.bz2
	@rm -f gopass-*.tar.gz
	@rm -f gopass-*-*
	@rm -f tests/tests
	@rm -f *.test
	@rm -rf dist/*
	@rm -f *.completion
	@printf '%s\n' '$(OK)'

$(GOPASS_OUTPUT): $(GOFILES_BUILD)
	@echo -n ">> BUILD, version = $(GOPASS_VERSION)/$(GOPASS_REVISION), output = $@"
	@$(GO) build -o $@ $(BUILDFLAGS)
	@printf '%s\n' '$(OK)'

install: all
	@echo -n ">> INSTALL, version = $(GOPASS_VERSION)"
	@install -m 0755 -d $(DESTDIR)$(BINDIR)
	@install -m 0755 $(GOPASS_OUTPUT) $(DESTDIR)$(BINDIR)/$(GOPASS_OUTPUT)
	@printf '%s\n' '$(OK)'

test: $(GOPASS_OUTPUT)
	@echo ">> TEST, \"fast-mode\": race detector off"
	@$(foreach pkg, $(PKGS),\
	    echo -n "     ";\
		$(GO) test -test.short -run '(Test|Example)' $(BUILDFLAGS) $(TESTFLAGS) $(pkg) || exit 1;)

crosscompile:
	@echo -n ">> CROSSCOMPILE linux/amd64"
	@GOOS=linux GOARCH=amd64 $(GO) build -o $(GOPASS_OUTPUT)-linux-amd64
	@printf '%s\n' '$(OK)'
	@echo -n ">> CROSSCOMPILE darwin/amd64"
	@GOOS=darwin GOARCH=amd64 $(GO) build -o $(GOPASS_OUTPUT)-darwin-amd64
	@printf '%s\n' '$(OK)'
	@echo -n ">> CROSSCOMPILE windows/amd64"
	@GOOS=windows GOARCH=amd64 $(GO) build -o $(GOPASS_OUTPUT)-windows-amd64
	@printf '%s\n' '$(OK)'

full:
	@echo -n ">> COMPILE linux/amd64 xc"
	$(GO) build -o $(GOPASS_OUTPUT)-full

codequality:
	@echo ">> CODE QUALITY"

	@echo -n "     REVIVE    "
	@which revive > /dev/null; if [ $$? -ne 0 ]; then \
		$(GO) get -u github.com/mgechev/revive; \
	fi
	@revive -formatter friendly -exclude vendor/... ./...
	@printf '%s\n' '$(OK)'

	@echo -n "     FMT       "
	@$(foreach gofile, $(GOFILES_NOVENDOR),\
			out=$$(gofmt -s -l -d -e $(gofile) | tee /dev/stderr); if [ -n "$$out" ]; then exit 1; fi;)
	@printf '%s\n' '$(OK)'

	@echo -n "     CLANGFMT  "
	@$(foreach pbfile, $(PROTOFILES),\
			if [ $$(clang-format -output-replacements-xml $(pbfile) | wc -l) -gt 3  ]; then exit 1; fi;)
	@printf '%s\n' '$(OK)'

	@echo -n "     VET       "
	@$(GO) vet ./...
	@printf '%s\n' '$(OK)'

	@echo -n "     CYCLO     "
	@which gocyclo > /dev/null; if [ $$? -ne 0 ]; then \
		$(GO) get -u github.com/fzipp/gocyclo/cmd/gocyclo; \
	fi
	@$(foreach gofile, $(GOFILES_NOVENDOR),\
			gocyclo -over 22 $(gofile) || exit 1;)
	@printf '%s\n' '$(OK)'

	@echo -n "     LINT      "
	@which golint > /dev/null; if [ $$? -ne 0 ]; then \
		$(GO) get -u golang.org/x/lint/golint; \
	fi
	@$(foreach pkg, $(PKGS),\
			golint -set_exit_status $(pkg) || exit 1;)
	@printf '%s\n' '$(OK)'

	@echo -n "     INEFF     "
	@which ineffassign > /dev/null; if [ $$? -ne 0 ]; then \
		$(GO) get -u github.com/gordonklaus/ineffassign; \
	fi
	@ineffassign . || exit 1
	@printf '%s\n' '$(OK)'

	@echo -n "     SPELL     "
	@which misspell > /dev/null; if [ $$? -ne 0 ]; then \
		$(GO) get -u github.com/client9/misspell/cmd/misspell; \
	fi
	@$(foreach gofile, $(GOFILES_NOVENDOR),\
			misspell --error $(gofile) || exit 1;)
	@printf '%s\n' '$(OK)'

	@echo -n "     STATICCHECK "
	@which staticcheck > /dev/null; if [ $$? -ne 0  ]; then \
		$(GO) get -u honnef.co/go/tools/cmd/staticcheck; \
	fi
	@staticcheck $(PKGS) || exit 1
	@printf '%s\n' '$(OK)'

	@echo -n "     UNPARAM "
	@which unparam > /dev/null; if [ $$? -ne 0 ]; then \
		$(GO) get -u mvdan.cc/unparam; \
	fi
	@unparam -exported=false $(PKGS)
	@printf '%s\n' '$(OK)'

gen:
	@go generate ./...

fmt:
	@gofmt -s -l -w $(GOFILES_NOVENDOR)
	@which goimports > /dev/null; if [ $$? -ne 0 ]; then \
		$(GO) get -u golang.org/x/tools/cmd/goimports; \
	fi
	@goimports -l -w $(GOFILES_NOVENDOR)
	@which clang-format > /dev/null; if [ $$? -eq 0 ]; then \
		clang-format -i $(PROTOFILES); \
	fi
	@go mod tidy

.PHONY: clean build completion install sysinfo crosscompile test codequality release goreleaser debsign
