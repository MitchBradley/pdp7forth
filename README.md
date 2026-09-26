# PDP-7 Forth

A small Forth for the DEC PDP-7 (18-bit words, 8K of core), assembled
with the `as7` assembler from [pdp7-unix](https://github.com/DoctorWkt/pdp7-unix)
and run under the [SimH](https://opensimh.org/) PDP-7 simulator.
`DESIGN.md` explains how it works and why.

## Setup

You need `git`, `make`, `perl` (for `as7`), Python 3, and SimH's
PDP-7 simulator, `pdp7`.

Clone with the pdp7-unix submodule:

```
git clone --recurse-submodules https://github.com/MitchBradley/pdp7forth
cd pdp7forth
```

(In an existing clone, `git submodule update --init` fetches it.)

### SimH on Linux

Debian and Ubuntu package SimH 3.8, which is what this project is
developed and tested with:

```
sudo apt install simh
```

Other distributions may package it too. Check that the package gives
you a `pdp7` command; if not, build it from source (below).

### SimH on macOS

Install Apple's command-line tools, which provide `make`, `git` and
Python 3 (`perl` is already there), then Open SIMH from Homebrew:

```
xcode-select --install
brew install open-simh
```

### Building SimH from source (Linux or macOS)

If no package works for you:

```
git clone https://github.com/open-simh/simh.git
cd simh
make pdp7
```

That leaves the simulator in `simh/BIN/pdp7`. Either put it on your
`PATH` as `pdp7`, or tell this project where it is:

```
make run PDP7=~/simh/BIN/pdp7
```

(`PDP7` works for every target, and for `test/run_tests.py` as an
environment variable.)

The project is developed with SimH 3.8 on Linux, and `make test` also
passes with Open SIMH 4 (Homebrew's `open-simh`) on macOS. If
something behaves differently under another version, the console
settings in `tools/mkdo.py` and `tools/simh.py` are the first place to
look.

## Building and testing

```
make          # assemble the kernel, then compile src/prelude.fs into it
make test     # run the test suite under SimH
```

`make` runs SimH once to compile the prelude, so SimH is needed even
to build.

## Running

```
make run
```

SimH starts the kernel, which prints

```
PDP-7 FORTH
```

and waits for input. Type Forth and press Return; each line answers
` ok`, or names the word it didn't understand with a `?`:

```
2 3 + . 5  OK
: SQ DUP * ; 7 SQ . 49  OK
FOO FOO ?
```

- **Case.** By default SimH behaves like a Model 33 teletype, which only
  has upper case, so input and output appear in upper case. Forth
  itself doesn't care. For lower case, get to the `sim>` prompt (below),
  type `set tti 7b`, then `c` to continue.
- **Editing.** Backspace or Delete erases the last character. There's no
  other line editing.
- **Looking around.** `WORDS` lists the dictionary. A header keeps only a
  name's length and first three characters, so longer names show as
  those three plus an underscore per missing character (`EXIT` shows as
  `EXI_`). Two names with the same length and first three characters
  are the same word to the dictionary; defining one prints
  `name redefined`.

## Stopping and exiting

- **`BYE`, or ^D**, halts the PDP-7 and drops you to SimH's `sim>`
  prompt.
- At `sim>`, **`exit`** (or `quit`) leaves SimH. **`c`** (continue)
  resumes Forth where it stopped, with everything you defined intact.
  (If you halted with ^D partway through typing a line, that line ends
  there when you continue.)
- **Ctrl-E** gets to `sim>` at any time, even when Forth is busy or
  stuck. It's SimH's interrupt key.
- **Ctrl-C and Ctrl-Z don't work** while the PDP-7 is running. SimH
  passes Ctrl-C to Forth as an ordinary character, and suspend is off.
  Use Ctrl-E.

While the PDP-7 runs, SimH turns off your terminal's echo and line
editing (Forth does its own). It restores them at `sim>` and on exit. If
SimH is killed instead of exiting (for example `kill -9`, or a dropped
ssh session), the terminal stays in that state, with invisible typing
and stair-stepped lines; `stty sane` or `reset` fixes it.

## Loading source from paper tape

The PDP-7's paper-tape reader is a second input source, and SimH reads
its tape from a file on your computer. `TAPE` switches Forth's input to
the reader; each line is echoed as it's read, like an ASR-33 printing
tape. At the end of the tape, input returns to the keyboard.

The tape must end with a marker. Without one, Forth waits at the end of
the file for more tape, because the PDP-7 can't sense an empty reader.
Either:

- end the file with ^D (character 004). `tools/mktape.py` copies a
  text file and appends one:

  ```
  python3 tools/mktape.py mywords.fs mywords.ptr
  ```

- or make the file's last line the word `EOT`.

Ordinary text files with LF or CR LF line endings work.

### Mounting a file at startup

```
make run TAPE=mywords.fs
```

This appends the ^D for you and mounts the file. Then type

```
TAPE
```

### Mounting a file in the middle of a session (the tape trick)

Everything you've defined so far survives:

1. Press ^D (or Ctrl-E) to halt to `sim>`.
2. `attach ptr mywords.ptr` (a file with an end marker, as above).
3. `c` to continue. You're back in Forth.
4. Type `TAPE`.

Each `attach` starts that file from the beginning; attach it again to
reread it.

### When something goes wrong on tape

- An error while reading tape (an undefined word, say) prints the usual
  message and stops tape input, so the rest of the file isn't run with
  a half-built definition. The reader keeps its place, so after fixing
  things by hand, `TAPE` resumes at the next line.
- If Forth is waiting at the end of a tape with no end marker, press
  Ctrl-E, `attach ptr` any file that contains a ^D, and `c`. Forth reads
  the ^D and returns to the keyboard.

## Files

- `src/kernel.s`: the kernel in PDP-7 assembly.
- `src/prelude.fs`: words written in Forth, compiled into the image at
  build time.
- `DESIGN.md`: design decisions, open issues, and implementation notes.
- `test/`: the test suite (`make test`).
- `tools/`: build helpers. `tools/pdp7-unix` is the submodule that
  provides `as7`.
