PREFIX ?= /usr/local

build:
	swift build -c release 2>&1 | xcsift

install: build
	install -d $(PREFIX)/bin
	install .build/arm64-apple-macosx/release/ladder $(PREFIX)/bin/ladder

uninstall:
	rm -f $(PREFIX)/bin/ladder

test:
	swift test 2>&1 | xcsift

.PHONY: build install uninstall test
