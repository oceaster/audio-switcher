PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
MANDIR  ?= $(PREFIX)/share/man/man1
SCRIPT  := audio-switcher

.PHONY: all install uninstall lint test check clean

all: lint test

install:
	install -Dm755 $(SCRIPT) $(DESTDIR)$(BINDIR)/$(SCRIPT)
	@echo "Installed $(SCRIPT) to $(DESTDIR)$(BINDIR)/$(SCRIPT)"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(SCRIPT)
	@echo "Removed $(DESTDIR)$(BINDIR)/$(SCRIPT)"

lint: check
check:
	shellcheck $(SCRIPT)
	shfmt -d $(SCRIPT) || true

test:
	./tests/run-tests.sh

clean:
	rm -f ./tests/tmp/*
