AS7 = tools/pdp7-unix/tools/as7
SOP = tools/pdp7-unix/src/sys/sop.s
SRCS = $(SOP) src/kernel.s src/end.s

all: build/kernel.lst build/forth.do

build:
	mkdir -p build

build/kernel.lst: $(SRCS) | build
	$(AS7) -f list -o $@ $(SRCS)

build/kernel.a7out: $(SRCS) | build
	$(AS7) -o $@ $(SRCS)

# The prelude is compiled by running the kernel under SimH (needs pdp7).
build/forth.img: build/kernel.lst build/kernel.a7out src/prelude.fs tools/prelude.py tools/simh.py
	python3 tools/prelude.py build/kernel.lst build/kernel.a7out src/prelude.fs $@ src/kernel.s

build/forth.do: build/kernel.lst build/forth.img tools/mkdo.py
	python3 tools/mkdo.py build/kernel.lst build/forth.img > $@

# SimH's pdp7 must be on PATH (Debian/Ubuntu: apt install simh). In
# "run", BYE halts back to the sim> prompt; type "exit" there.
run: build/forth.do
	pdp7 build/forth.do

test:
	python3 test/run_tests.py

clean:
	rm -rf build

.PHONY: all run test clean
