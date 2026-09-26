AS7 = tools/pdp7-unix/tools/as7
SOP = tools/pdp7-unix/src/sys/sop.s

all: build/kernel.lst

build:
	mkdir -p build

build/kernel.lst: src/kernel.s $(SOP) | build
	$(AS7) -f list -o $@ $(SOP) src/kernel.s

# Needs SimH's pdp7 on PATH (Debian/Ubuntu: apt install simh).
test:
	python3 test/run_tests.py

clean:
	rm -rf build

.PHONY: all test clean
