\ PDP-7 Forth prelude: compiled into the image at build time by
\ tools/prelude.py, which runs the kernel under SimH. Lines must fit the
\ 80-character TIB. A cell is one 18-bit word.

-1 constant true   0 constant false   32 constant bl
: decimal 10 base ! ;   : hex 16 base ! ;   : octal 8 base ! ;

: 1+ 1 + ;   : 1- 1 - ;   : cell+ 1+ ;
\ No CELLS: a cell is one word, and CELLS would collide with CELL+ (same
\ length, same first three characters).
: ?dup dup if dup then ;
: nip swap drop ;   : tuck swap over ;
: rot >r swap r> swap ;   : -rot rot rot ;
: 2dup over over ;   : 2drop drop drop ;

: > swap < ;   : <> = 0= ;   : 0> 0 swap < ;   : 0<> 0= 0= ;
: abs dup 0< if negate then ;
: min 2dup > if swap then drop ;
: max 2dup < if swap then drop ;
: +! dup @ rot + swap ! ;

: space bl emit ;
: spaces begin dup 0> while space 1- repeat drop ;
: ['] ' [ ' literal compile, ] ; immediate

\ Strings: one character per word, so a character address is a cell
\ address. No CHARS: it would collide with CHAR+ (and it's a no-op).
: c@ @ ;   : c! ! ;   : c, , ;   : char+ 1+ ;
: count dup 1+ swap c@ ;
: type begin dup 0> while over c@ emit 1- swap 1+ swap repeat 2drop ;
: [char] char [ ' literal compile, ] ; immediate
