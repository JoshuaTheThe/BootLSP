override MAKEFLAGS += -rR
override AS := nasm -f bin
override OUTPUT := bootlsp.boot

.PHONY: all
all: bin/$(OUTPUT)

bin/$(OUTPUT): src/start.S
	@mkdir -p $$(dirname $@)
	$(AS) src/start.S -o bin/$(OUTPUT)

.PHONY: run
run:
	@qemu-system-i386 -fda bin/$(OUTPUT)

