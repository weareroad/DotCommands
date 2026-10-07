ZXBASM ?= /home/rob/Documents/NextBuildv10/zxbasic1.18.7/zxbasm.py

.PHONY: all clean

all: build/32 build/64 build/85

build:
	mkdir -p build

build/32: src/32.asm src/columns.asm | build
	cd src && $(ZXBASM) -N -o ../$@.full 32.asm
	dd if=$@.full of=$@ bs=1 skip=8192 status=none
	rm -f $@.full

build/64: src/64.asm src/columns.asm | build
	cd src && $(ZXBASM) -N -o ../$@.full 64.asm
	dd if=$@.full of=$@ bs=1 skip=8192 status=none
	rm -f $@.full

build/85: src/85.asm src/columns.asm | build
	cd src && $(ZXBASM) -N -o ../$@.full 85.asm
	dd if=$@.full of=$@ bs=1 skip=8192 status=none
	rm -f $@.full

clean:
	rm -f build/32 build/64 build/85 build/*.full build/test32.bin
