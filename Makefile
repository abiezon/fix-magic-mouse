# magicmousefix — build, check, install.
#
# Install/uninstall need root; they shell out to scripts/ so that what runs as root is a
# small script you can read, rather than a make recipe.

CC      ?= clang
CFLAGS  ?= -O2 -Wall -Wextra -Werror -std=c11
LDFLAGS := -framework IOKit -framework CoreFoundation

BIN := magicmousefix
SRC := src/magicmousefix.c

.PHONY: all build lint test doctor dry-run install uninstall clean

all: build

build: $(BIN)

$(BIN): $(SRC)
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDFLAGS)

# Static analysis — no extra tooling, clang ships with macOS.
lint:
	$(CC) $(CFLAGS) -fsyntax-only $(SRC)
	$(CC) --analyze -Xclang -analyzer-output=text $(CFLAGS) $(SRC) -o /dev/null

# The test suite is behavioural and does not touch the mouse.
test: $(BIN)
	./tests/run.sh

# Report the state of the machine, the mouse and the daemon. Changes nothing.
doctor:
	./scripts/doctor.sh

# Enumerate the interfaces that would be written to, without writing.
dry-run: $(BIN)
	sudo ./$(BIN) --dry-run

install: $(BIN)
	sudo ./scripts/install.sh

uninstall:
	sudo ./scripts/uninstall.sh

clean:
	rm -f $(BIN)
	rm -rf *.dSYM
