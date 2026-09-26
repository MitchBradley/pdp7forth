AS7 = tools/pdp7-unix/tools/as7
# The SimH PDP-7 simulator: "make run PDP7=~/simh/BIN/pdp7" if it isn't
# on PATH as pdp7. The Python tools read it from the environment too.
PDP7 ?= pdp7
export PDP7
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
build/forth.img: build/kernel.lst build/kernel.a7out src/prelude.fs tools/prelude.py tools/simh.py tools/mktape.py
	python3 tools/prelude.py build/kernel.lst build/kernel.a7out src/prelude.fs $@ src/kernel.s

build/forth.do: build/kernel.lst build/forth.img tools/mkdo.py
	python3 tools/mkdo.py build/kernel.lst build/forth.img > $@

# See README.md. In "run", BYE or ^D halts to the sim> prompt; type
# "exit" there.
# "make run TAPE=file.fs" mounts file.fs in the paper-tape reader (with
# ^D appended); type TAPE in Forth to read it.
ifdef TAPE
run: build/forth.img tools/mkdo.py tools/mktape.py
	python3 tools/mktape.py $(TAPE) build/run.ptr
	python3 tools/mkdo.py build/kernel.lst build/forth.img build/run.ptr > build/run.do
	$(PDP7) build/run.do
else
run: build/forth.do
	$(PDP7) build/forth.do
endif

test:
	python3 test/run_tests.py

clean:
	rm -rf build

.PHONY: all run test clean
