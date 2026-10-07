SJASMPLUS ?= .tools/bin/sjasmplus

.PHONY: all clean toolchain

all: build/32 build/64 build/85

toolchain:
	@if [ "$(SJASMPLUS)" = ".tools/bin/sjasmplus" ]; then \
		./tools/bootstrap-sjasmplus.sh; \
	else \
		test -x "$(SJASMPLUS)" || { echo "Assembler is not executable: $(SJASMPLUS)" >&2; exit 1; }; \
	fi

build:
	mkdir -p build

build/32: src/32.asm src/columns.asm | build toolchain
	$(SJASMPLUS) --nologo --cleanonerror --inc=src --raw=$@ $<

build/64: src/64.asm src/columns.asm | build toolchain
	$(SJASMPLUS) --nologo --cleanonerror --inc=src --raw=$@ $<

build/85: src/85.asm src/columns.asm | build toolchain
	$(SJASMPLUS) --nologo --cleanonerror --inc=src --raw=$@ $<

clean:
	rm -f build/32 build/64 build/85
