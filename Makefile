PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DEV_BINDIR ?= $(HOME)/.local/bin

install:
	mkdir -p $(DESTDIR)$(BINDIR)
	install -m755 claude-spaces-agents $(DESTDIR)$(BINDIR)/claude-spaces-agents

dev:
	ln -sf $(CURDIR)/claude-spaces-agents $(DEV_BINDIR)/claude-spaces-agents

test:
	./run_tests

breaks:
	./run_breaks

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/claude-spaces-agents
