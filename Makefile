AS7 = tools/pdp7-unix/tools/as7
SOP = tools/pdp7-unix/src/sys/sop.s

all: build/kernel.lst

build:
	mkdir -p build

build/kernel.lst: src/kernel.s $(SOP) | build
	$(AS7) -f list -o $@ $(SOP) src/kernel.s

build/kernel.rim: src/kernel.s $(SOP) | build
	$(AS7) -f rim -o $@ $(SOP) src/kernel.s

clean:
	rm -rf build

.PHONY: all clean
