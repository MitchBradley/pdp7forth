" PDP-7 Forth -- kernel
"
" A working interactive Forth: the inner interpreter (NEXT and the CAL
" trap handler "nest"), dictionary search, the primitive set, console
" I/O, the outer interpreter (a thread starting at qthr), and the ":"/";"
" compiler with its control words. Start at "cold". Words written in
" Forth are in src/prelude.fs, compiled into the image at build time.
"
" From the repo root: "make" assembles to build/kernel.lst; "make run"
" boots it in SimH; "make test" runs test/run_tests.py, which assembles
" this file with test/tests.s and checks the results under SimH.
" tools/hdr.py prints header words (join the parts with "+", not spaces:
" as7 ORs space-separated terms).
"
" Register conventions (DESIGN.md, Stacks):
"   IP = auto-index 010, RP = auto-index 011, SP = auto-index 012.
"   Both stacks grow up; push is "dac i 011"/"dac i 012", and each
"   register holds (first slot - 1) when its stack is empty.
"
" NOTE on manifest constants: there is no immediate form of AND/TAD/SAD.
" "and cmask" means AC := AC AND M[cmask], so every constant used as an
" operand is a labelled data cell (misc/asm_syntax.txt's dNNN/oNNN
" convention), never a bare "=" value.
"
" NOTE on number bases: as7 reads a literal with no leading zero as
" DECIMAL. Octal addresses and values are written with a leading zero.
"
" NOTE on names: as7 truncates labels to 8 characters, and its built-in
" symbols (opcodes, Unix system call names such as "exit", "read",
" "divs") shadow labels of the same name.

.=010

" --- low memory: auto-index register cells ---
0		" 010: IP -- set before use
rstack-1	" 011: RP, empty
dstack-1	" 012: SP, empty
0		" 013: scratch pointer (find)
0		" 014: scratch pointer (accept/parse/number)
0		" 015: free
0		" 016: free
0		" 017: free

0		" 020: CAL's return-address slot (hardware-managed)

" --- nest: entered via the hardware CAL trap (JMS 20 -> here) ---
nest:	lac 010		" IP -> the CAL cell just executed
	dac i 011	" push it on the return stack
	dac t
	lac i t		" cell = body address (tag 00, "CAL -- bare address")
	tad m1		" back up one for NEXT's pre-increment
	dac 010
	jmp next

t:	0		" nest's scratch cell

" --- NEXT: the inner interpreter ---
" Only LAC/LAW-tag cells fall through to "dac i 012"; CAL/JMP-tag cells
" transfer control elsewhere and never reach it.
next:	xct i 010	" pre-increment IP, execute the thread cell
	dac i 012	" push AC (only reached by constant/variable cells)
	jmp next

" --- stack helpers (impure JMS convention) ---
" pop.rp / pop.sp: pop a stack; AC = popped value.
pop.rp:	0
	lac 011
	dac t2
	tad m1
	dac 011
	lac i t2
	jmp i pop.rp

pop.sp:	0
	lac 012
	dac t2
	tad m1
	dac 012
	lac i t2
	jmp i pop.sp

" un: t3 -> TOS, AC = TOS. Unary primitives rewrite TOS in place.
un:	0
	lac 012
	dac t3
	lac i t3
	jmp i un

" bin: drop b, leaving t2 -> b's old slot, t3 -> a (the new TOS), AC = b.
" Binary primitives write their result through t3.
bin:	0
	lac 012
	dac t2
	tad m1
	dac 012
	dac t3
	lac i t2
	jmp i bin

" Flag results for primitives that set t3 via un/bin.
true:	lac m1
	dac i t3
	jmp next
false:	dzm i t3
	jmp next

" sdiv: bin, then a/b truncating toward zero: AC = remainder (sign of
" a), MQ = quotient. EAE's signed MULS/IDIVS assume ones'-complement
" signs, so divide the magnitudes with unsigned IDIV and fix the signs
" here. Unsigned MUL/IDIV need the link clear.
sdiv:	0
	jms bin		" AC = b
	dac t4
	xor i t3
	dac qsgn	" sign bit = quotient's sign
	lac t4
	jms absv
	dac 1f
	lac i t3
	dac rsgn	" sign bit = remainder's sign
	jms absv
	cll
	idiv
1:	0
	dac t4		" |remainder|
	lac qsgn
	sma
	jmp 2f
	lacq
	cma
	tad d1
	lmq		" negate the quotient
2:	lac rsgn
	sma
	jmp 3f
	lac t4
	cma
	tad d1
	jmp i sdiv
3:	lac t4
	jmp i sdiv

" absv: AC := |AC|
absv:	0
	sma
	jmp i absv
	cma
	tad d1
	jmp i absv

" --- console (DESIGN.md, I/O): polled, interrupts off ---
" getc: next input character: from the keyboard, or from the paper-tape
" reader after TAPE. The reader only advances when asked, so unlike the
" keyboard it can't overrun. On tape, blank (NUL) leader/trailer and CR
" frames are skipped and LF becomes CR, so host text files work as
" tapes. ^D (EOT) ends the tape, switching back to the keyboard, and is
" returned so accept can end a partial line. The PDP-7 has no reader-empty status, so a tape without ^D
" leaves the kernel waiting for more tape. While waiting for a key, getc
" restarts the Type 340 display on DLIST whenever DISPLAY is set and the
" 340 has stopped (DESIGN.md, Graphics). ^D typed at the keyboard halts,
" like BYE; CONTINUE resumes, and accept then treats it as ^D from tape.
getc:	0
	lac tapein
	sza
	jmp 2f
1:	ksf
	jmp 5f		" no key yet: keep the display refreshed
	krb
	and o177	" 7-bit ASCII
	sad o4
	hlt		" ^D from the keyboard: halt, as BYE does
	jmp i getc
5:	lac display	" DISPLAY on, and the Type 340 has reached the
	sna		" stop at the end of the display list? Start it
	jmp 1b		" over from the top, so the drawing stays lit
	0700601		" 340: skip if stopped
	jmp 1b
	lac dlp
	0700604		" 340: load display address from AC, and start
	jmp 1b
2:	rsa		" read one frame, alphanumeric mode
3:	rsf
	jmp 3b
	rrb
	and o177
	sna
	jmp 2b		" blank tape
	sad o15
	jmp 2b		" CR: the LF ends the line
	sad o12
	jmp 4f
	sad o4
	dzm tapein	" ^D: end of tape (skipped by sad for other characters)
	jmp i getc
4:	lac o15
	jmp i getc

putc:	0
	tls
1:	tsf
	jmp 1b
	jmp i putc

" --- find: dictionary search (DESIGN.md, Dictionary/headers) ---
" Uses auto-index 013, not 010 as in the DESIGN.md sketch: find runs
" inside primitives, where 010 is IP.
" Call with "jms find" after setting tcnt/tname. Returns AC = the header
" address (the xt), or -1 if the name isn't in the chain from "latest".
find:	0
	lac latest
1:	dac p
	dac 013
	lac i p
	and cmask	" count field only
	sad tcnt	" skip if count differs
	jmp 2f
3:	lac i p
	and lmask	" link field only
	sna		" 0 = end of chain
	jmp 4f
	cma		" -(dist-1)-1 = -dist
	tad p
	jmp 1b
2:	lac i 013	" name word at p+1
	sad tname
	jmp 5f
	jmp 3b
4:	lac m1		" not found
	jmp i find
5:	lac p		" found
	jmp i find

p:	0
tcnt:	0		" count field of the name being sought
tname:	0		" packed SIXBIT name word being sought

" --- accept: read a line into tib, echoing ---
" CR ends the line; it isn't stored, and echoes as a space. So does ^D
" (end of tape, see getc) unless the line is empty. Rubout and backspace drop
" the last character and echo a backspace. Characters past the 80th are
" ignored. Leaves inp = tib and tend = tib + count.
accept:	0
	lac tibp
	dac inp
	dac tend
1:	jms getc
	sad o15
	jmp 3f
	sad o4
	jmp 5f
	sad o177
	jmp 2f
	sad o10
	jmp 2f
	dac t5
	lac tend
	sad tibe	" full: ignore
	jmp 1b
	dac t6
	lac t5
	dac i t6
	isz tend
	jms putc	" echo
	jmp 1b
2:	lac tend
	sad tibp	" empty: nothing to drop
	jmp 1b
	tad m1
	dac tend
	lac o10
	jms putc
	jmp 1b
3:	lac o40
	jms putc
	jmp i accept
5:	lac tend	" ^D (end of tape) ends a partial line; on an empty
	sad tibp	" one, just carry on from the keyboard
	jmp 1b
	jmp 3b

" --- parse: take the next blank-delimited token from inp ---
" Returns AC = wlen (0 at end of line). Sets wptr and wlen, plus tcnt and
" tname (count field and case-folded SIXBIT of the first 3 characters,
" space-padded) ready for find. The count field keeps only the low 5
" bits of the length.
parse:	0
	dzm wlen
1:	lac inp		" skip blanks
	sad tend
	jmp 5f
	dac wptr
	isz inp
	lac i wptr
	sad o40
	jmp 1b
2:	isz wlen	" wptr -> token start
	lac inp
	sad tend
	jmp 4f
	dac t4
	lac i t4
	sad o40
	jmp 3f
	isz inp
	jmp 2b
3:	isz inp		" consume the delimiter
4:	lac wlen
	cll
	als 13
	dac tcnt
	lac wptr
	tad m1
	dac 014
	lac wlen
	dac t4		" characters left to pack
	lac m3
	dac t5		" 3 slots
	dzm tname
6:	lac tname
	cll
	als 6
	dac tname
	lac t4
	sna
	jmp 7f		" pad with SIXBIT space (0)
	tad m1
	dac t4
	lac i 014
	jms fold
	tad om40
	and o77
	xor tname
	dac tname
7:	isz t5
	jmp 6b
5:	lac wlen
	jmp i parse

" fold: upper-case AC if it is in 0140-0177.
fold:	0
	dac t6
	tad om140
	sma		" below 0140: leave it
	jmp 1f
	lac t6
	jmp i fold
1:	lac t6
	tad om40
	jmp i fold

" sch: next character of a string being compiled, with a skip; no skip
" at '"' (consumed) or at the end of the line.
sch:	0
	lac inp
	sad tend
	jmp i sch
	dac t4
	isz inp
	lac i t4
	sad o42
	jmp i sch
	isz sch
	jmp i sch

" --- number: convert the token at wptr/wlen in BASE ---
" Optional leading '-'. Digits past 9 are letters, either case. On
" success returns with a skip and AC = value; on failure, no skip.
number:	0
	lac wptr
	tad m1
	dac 014
	lac wlen
	cma
	tad d1
	dac t4		" -wlen, counted up by isz
	dzm nacc
	dzm nneg
	lac i wptr
	sad o55		" '-'
	skp
	jmp 1f
	isz 014
	isz nneg
	isz t4
	jmp 1f
	jmp i number	" a lone '-' is not a number
1:	lac i 014
	jms fold
	tad om60	" - '0'
	spa
	jmp i number	" below '0'
	dac t5
	tad dm10
	spa
	jmp 2f		" 0-9
	tad dm7		" 'A' is '0' + 17
	spa
	jmp i number	" between '9' and 'A'
	tad d10
	dac t5
2:	lac t5
	cma
	tad base	" BASE - digit - 1
	spa
	jmp i number	" digit >= BASE
	lac base
	dac 3f
	lac nacc
	cll
	mul
3:	0
	lacq
	tad t5
	dac nacc
	isz t4
	jmp 1b
	lac nneg
	sna
	jmp 4f
	lac nacc
	cma
	tad d1
	skp
4:	lac nacc
	isz number
	jmp i number

" --- xts and compilation ---
" An xt is a header address (DESIGN.md, Threading). mkcell turns one
" into the thread cell that calls it: optab[tag] | (xt + 2).
mkcell:	0
	dac t5
	lac i t5
	and tmask	" tag field
	cll
	lrs 9
	tad optabp
	dac t6
	lac t5
	tad d2		" body
	tad i t6
	jmp i mkcell

optab:	0		" colon: CAL is opcode 0, so the cell is the bare address
	jmp		" primitive
	lac		" constant
	law		" variable
optabp:	optab

" comp: compile AC at dp. The dictionary is full when dp meets the pool.
comp:	0
	dac cval
	lac dp
	sad pool
	jmp full
	sad tbufe	" the interpretive-structure buffer is full
	jmp full
	dac cptr
	lac cval
	dac i cptr
	isz dp
	jmp i comp

" lit: compile AC as a literal: a LAC of a pool entry holding it. The
" pool grows down from the top of memory, and equal values share an
" entry (DESIGN.md, Memory).
lit:	0
	dac lval
	lac pool
	dac lptr
1:	lac lptr	" search the existing entries
	sad ptop
	jmp 2f
	lac i lptr
	sad lval
	jmp 3f
	isz lptr
	jmp 1b
2:	lac pool	" not found: add one
	sad dp
	jmp full
	tad m1
	dac pool
	dac lptr
	lac lval
	dac i lptr
3:	lac lptr
	tad lacop
	jms comp
	jmp i lit

" mkhdr: parse a name and lay down a header at dp with tag AC. If the
" name (its length and first three characters) is already defined, say
" "<name> redefined" first.
" Returns AC = the header address; the caller decides when to link it.
mkhdr:	0
	dac htag
	jms parse
	sna
	jmp noname
	and nhigh	" longer than 31 characters?
	sza
	jmp noname
	jms find	" warn if this hides an existing word
	sad m1
	jmp 1f
	jms typetok
	lac m.redef
	jms puts
1:	lac dp
	dac hadr
	lac latest
	cma
	tad dp		" link = distance - 1
	dac t5
	and lhigh	" must fit in 9 bits (DESIGN.md, Dictionary/headers)
	sza
	jmp far
	lac t5
	tad tcnt
	tad htag
	jms comp
	lac tname
	jms comp
	lac hadr
	jmp i mkhdr

" --- interpretive control structures ---
" IF, BEGIN and DO used while interpreting start compiling into tbuf;
" nesting is counted in level. When the outermost structure closes (THEN,
" UNTIL, AGAIN, REPEAT, LOOP), the code runs at once and is discarded.
" tbuf is separate from the dictionary so the code can compile or ALLOT
" (e.g. "3 0 DO I , LOOP") without overwriting itself.
lvst:	0
	lac level
	sza
	jmp 1f		" already inside one: count it
	lac state
	sza
	jmp i lvst	" compiling a definition: nothing to do
	lac dp
	dac savdp
	lac tbufp
	dac dp
	lac m1
	dac state
1:	isz level
	jmp i lvst

lvend:	lac level
	sna
	jmp next	" ordinary compilation
	tad m1
	dac level
	sza
	jmp next	" still inside an outer structure
	lac c.exit
	jms comp
	lac savdp
	dac dp
	dzm state
	lac tbufp	" run tbuf (a CAL cell is its bare address), as
	jmp xrun	" EXECUTE would

" --- errors: print the last token and a message, then abort ---
full:	lac m.full
	jmp error
noname:	lac m.name
	jmp error
far:	lac m.far
	jmp error
undef:	lac m.undef
error:	dac msgp
	jms typetok
	lac msgp
	jms puts
	jms crlf

" abort: stop reading tape, abandon any definition in progress, empty both
" stacks, and restart the interpreter. quit leaves the data stack alone.
abort:	dzm tapein	" an error while loading tape: back to the keyboard
	lac level	" abandon an interpretive control structure
	sna
	jmp 2f
	lac savdp
	dac dp
	dzm level
2:	lac cdp
	sna
	jmp 1f
	dac dp		" discard the partial definition
	dzm cdp
1:	lac ds0
	dac 012
quit:	lac rs0
	dac 011
	dzm state
	lac qip
	dac 010
	jmp next

" cold: start here.
cold:	lac dlp	" run the 340 once over the (initially empty) display
	0700604		" list, so that it reports "stopped" from now on
	lac m.hello
	jms puts
	jms crlf
	jmp abort

" The outer interpreter, as a thread.
qthr:	jmp xquery
1:	jmp xparse
	jmp qbran
	3f-1		" end of line
	jmp xfind
	jmp dup
	jmp qbran
	4f-1		" not a word
	law state	" compile iff STATE and not immediate:
	jmp fetch	" STATE @ AND 0<
	jmp and.b
	jmp zlt
	jmp qbran
	5f-1
	jmp compc
	jmp bran
	1b-1
5:	jmp execute
	jmp bran
	1b-1
4:	jmp drop
	jmp xnumber
	jmp qbran
	6f-1		" not a number either
	law state
	jmp fetch
	jmp qbran
	1b-1		" interpreting: leave it on the stack
	jmp literal
	jmp bran
	1b-1
6:	jmp xerr
3:	jmp xok
	jmp bran
	qthr-1

" --- output helpers ---
" typetok: print the last parsed token.
typetok:	0
	lac wlen
	sna
	jmp i typetok
	cma
	tad d1
	dac ttc
	lac wptr
	tad m1
	dac 016
1:	lac i 016
	jms putc
	isz ttc
	jmp 1b
	jmp i typetok

" puts: print the string at AC: two 9-bit characters per word (as7's
" <a>b syntax: <a is the high character, >b the low), ended by a zero
" word. Zero halves are skipped.
puts:	0
	dac pstr
1:	lac i pstr
	sna
	jmp i puts
	cll
	lrs 9
	sza
	jms putc
	lac i pstr
	and o777
	sza
	jms putc
	isz pstr
	jmp 1b

crlf:	0
	lac o15
	jms putc
	lac o12
	jms putc
	jmp i crlf

" Messages. Errors print after the offending token.
m.hello:	1f
1:	<P>D; <P>-; <7> ; <F>O; <R>T; <H; 0
m.ok:	1f
1:	< >o; <k; 0
m.undef:	1f
1:	< >?; 0
m.stack:	1f
1:	< >s; <t>a; <c>k; <?; 0
m.full:	1f
1:	< >f; <u>l; <l>?; 0
m.name:	1f
1:	< >n; <a>m; <e>?; 0
m.far:	1f
1:	< >f; <a>r; <?; 0
m.redef:	1f
1:	< >r; <e>d; <e>f; <i>n; <e>d; 0

" --- scratch and state ---
t2:	0
t3:	0
t4:	0
t5:	0
t6:	0
tapein:	0		" nonzero: getc reads the paper-tape reader
inp:	0		" next unread character in tib
tend:	0		" tib + line length
wptr:	0		" start of the last parsed token
wlen:	0		" its length
nacc:	0
nneg:	0
qsgn:	0
sdc:	0		" */
cval:	0		" comp
cptr:	0
lval:	0		" lit
lptr:	0
htag:	0		" mkhdr
hadr:	0
cdp:	0		" header of the definition being compiled, else 0
level:	0		" interpretive control structure nesting
savdp:	0		" dp while compiling into tbuf
sqp:	0		" S"
msgp:	0
pstr:	0
ttc:	0
wp:	0		" WORDS
wcnt:	0
wr:	0
wk:	0
wcol:	0
rsgn:	0
dp:	end		" next free dictionary word
pool:	020000		" lowest literal-pool entry; the pool grows down
tibp:	tib
tibe:	tib+0120
dlp:	dlbuf
tbufp:	tbuf
tbufe:	tbuf+0144
sbufp:	sbuf
ds0:	dstack-1	" SP when empty
dstop:	dstack+040	" one past the top slot
rs0:	rstack-1	" RP when empty
qip:	qthr-1
ptop:	020000		" top of memory + 1
nbufp:	nbuf-1

" --- manifest constants ---
m1:	-1
m2:	-2
m3:	-3
dm7:	-7
dm10:	-10
dm60:	-60
d1:	1
d2:	2
d10:	10
o4:	04
o10:	010
o12:	012
o15:	015
o40:	040
o42:	042
o55:	055
o77:	077
o51:	051
o101:	0101
o137:	0137
o177:	0177
o777:	0777
o2000:	02000
o3000:	03000
o10000:	010000
o767777:	0767777
lhigh:	0777000
nhigh:	0777740
tmask:	0007000
lacop:	lac
c.exit:	jmp ex.body
c.bran:	jmp bran
c.qbran:	jmp qbran
c.xdo:	jmp xdo
c.xloop:	jmp xloop
c.xdotq:	jmp xdotq
c.xsq:	jmp xsq
o400k:	0400000
om40:	-040
om60:	-060
om140:	-0140
cmask:	0760000		" header count field
lmask:	0000777		" header link field

" --- header tag field values (DESIGN.md) ---
" Used only in header-word arithmetic, so plain assembler variables.
tag.colon=	0
tag.prim=	001000
tag.const=	002000
tag.var=	003000

" --- Type 340 display list (DLIST) ---
" 1024 words, below 4K as the 340's 12-bit address counter requires. It
" sits here, before the dictionary, because a header can't link across
" it (the 512-word span). It starts as just a stop.
dlbuf:	02000
	.=.+01777

" Interpretive control structures compile here (see lvst).
tbuf:	.=.+0144	" 100 words

" S" while interpreting leaves its string here. A line holds at most 80
" characters, so the string can't overflow it.
sbuf:	.=.+0120

" === Kernel dictionary ===
" Primitive bodies end with "jmp next". Branch-type words take an inline
" cell holding (target - 1), which goes straight into IP.

" EXIT ( -- ) ( R: ip -- )  EXIT is an ordinary primitive, not a spare tag.
h.ex:	0100000+tag.prim	" EXIT
	0457051
ex.body:
	jms pop.rp	" AC := the caller's CAL-cell address, pushed by nest
	dac 010		" IP := that address directly -- no "tad m1" here,
			" unlike nest: EXIT resumes the cell *after* the
			" call, nest enters the callee's body
	jmp next

" BRANCH ( -- )  IP := inline cell (target - 1).
h.bran:	0140000+tag.prim+h.bran-h.ex-1	" BRANCH
	0426241
bran:	lac i 010
	dac 010
	jmp next

" ?BRANCH ( flag -- )  branch if zero, else step over the inline cell.
h.qbran:	0160000+tag.prim+h.qbran-h.bran-1	" ?BRANCH
	0374262
qbran:	lac 012		" inline pop
	dac t2
	tad m1
	dac 012
	lac i t2
	sna		" nonzero (true): fall through
	jmp bran	" zero: take the branch
	isz 010		" step over the inline cell (IP is never 0: no skip)
	jmp next

" (DO) ( limit index -- ) ( R: -- limit index-limit )
" The top return-stack cell is a counter that (LOOP) ISZes up to 0.
h.xdo:	0100000+tag.prim+h.xdo-h.qbran-1	" (DO)
	0104457
xdo:	jms pop.sp	" index
	dac t4
	jms pop.sp	" limit
	dac i 011	" R: limit
	cma		" -limit-1
	tad t4
	tad d1		" index - limit
	dac i 011	" R: counter
	jmp next

" (LOOP) ( -- ) ( R: limit counter -- | limit counter+1 )
" Bump the counter in place; branch back until it reaches 0, then drop
" both return-stack cells and step over the inline cell.
h.xloop:	0140000+tag.prim+h.xloop-h.xdo-1	" (LOOP)
	0105457
xloop:	lac 011
	dac t2
	isz i t2	" counter++; skips when it reaches 0
	jmp bran	" not done: loop back
	lac 011
	tad m2
	dac 011		" drop limit and counter
	isz 010		" step over the inline cell
	jmp next

" I ( -- index )  limit + counter.
h.xi:	0020000+tag.prim+h.xi-h.xloop-1	" I
	0510000
xi:	lac 011		" RP -> counter
	dac t2
	tad m1
	dac t4		" -> limit
	lac i t2
	tad i t4
	dac i 012
	jmp next

" DUP ( x -- x x )
h.dup:	0060000+tag.prim+h.dup-h.xi-1	" DUP
	0446560
dup:	jms un
	dac i 012
	jmp next

" DROP ( x -- )
h.drop:	0100000+tag.prim+h.drop-h.dup-1	" DROP
	0446257
drop:	lac 012
	tad m1
	dac 012
	jmp next

" SWAP ( a b -- b a )
h.swap:	0100000+tag.prim+h.swap-h.drop-1	" SWAP
	0636741
swap:	jms bin
	dac t4		" b
	lac i t3	" a
	dac i t2	" into b's slot
	lac t4
	dac i t3	" b into a's slot
	isz 012		" undo bin's drop (SP is never 0: no skip)
	jmp next

" OVER ( a b -- a b a )
h.over:	0100000+tag.prim+h.over-h.swap-1	" OVER
	0576645
over:	lac 012
	tad m1
	dac t3
	lac i t3
	dac i 012
	jmp next

" >R ( x -- ) ( R: -- x )
h.tor:	0040000+tag.prim+h.tor-h.over-1	" >R
	0366200
tor:	jms pop.sp
	dac i 011
	jmp next

" R> ( -- x ) ( R: x -- )
h.rfrom:	0040000+tag.prim+h.rfrom-h.tor-1	" R>
	0623600
rfrom:	jms pop.rp
	dac i 012
	jmp next

" R@ ( -- x ) ( R: x -- x )
h.rat:	0040000+tag.prim+h.rat-h.rfrom-1	" R@
	0624000
rat:	lac 011
	dac t3
	lac i t3
	dac i 012
	jmp next

" @ ( addr -- x )  indirection uses only the low 13 bits, so LAW-form
" (negative) addresses from variables work unchanged.
h.fetch:	0020000+tag.prim+h.fetch-h.rat-1	" @
	0400000
fetch:	jms un
	dac t4
	lac i t4
	dac i t3
	jmp next

" ! ( x addr -- )
h.store:	0020000+tag.prim+h.store-h.fetch-1	" !
	0010000
store:	jms bin
	dac t4		" addr
	lac i t3	" x
	dac i t4
	lac 012		" drop x
	tad m1
	dac 012
	jmp next

" + ( a b -- a+b )
h.plus:	0020000+tag.prim+h.plus-h.store-1	" +
	0130000
plus:	jms bin
	tad i t3
	dac i t3
	jmp next

" - ( a b -- a-b )
h.minus:	0020000+tag.prim+h.minus-h.plus-1	" -
	0150000
minus:	jms bin
	cma		" -b-1
	tad i t3
	tad d1
	dac i t3
	jmp next

" AND ( a b -- a&b )
h.and:	0060000+tag.prim+h.and-h.minus-1	" AND
	0415644
and.b:	jms bin
	and i t3
	dac i t3
	jmp next

" OR ( a b -- a|b )  no OR instruction: (a^b) ^ (a&b).
h.or:	0040000+tag.prim+h.or-h.and-1	" OR
	0576200
or.b:	jms bin
	and i t3
	dac t4
	lac i t2
	xor i t3
	xor t4
	dac i t3
	jmp next

" XOR ( a b -- a^b )
h.xor:	0060000+tag.prim+h.xor-h.or-1	" XOR
	0705762
xor.b:	jms bin
	xor i t3
	dac i t3
	jmp next

" INVERT ( x -- ~x )
h.inv:	0140000+tag.prim+h.inv-h.xor-1	" INVERT
	0515666
invert:	jms un
	cma
	dac i t3
	jmp next

" NEGATE ( x -- -x )
h.neg:	0140000+tag.prim+h.neg-h.inv-1	" NEGATE
	0564547
negate:	jms un
	cma
	tad d1
	dac i t3
	jmp next

" = ( a b -- flag )
h.eq:	0020000+tag.prim+h.eq-h.neg-1	" =
	0350000
equal:	jms bin
	sad i t3	" skip if different
	jmp true
	jmp false

" U< ( a b -- flag )  b + ~a carries into the link iff b > a.
h.ult:	0040000+tag.prim+h.ult-h.eq-1	" U<
	0653400
ult:	jms bin
ultc:	lac i t3
	cma
	cll
	tad i t2
	snl
	jmp false
	jmp true

" < ( a b -- flag )  flip both sign bits, then compare unsigned.
h.lt:	0020000+tag.prim+h.lt-h.ult-1	" <
	0340000
less:	jms bin
	xor o400k
	dac i t2
	lac i t3
	xor o400k
	dac i t3
	jmp ultc

" 0= ( x -- flag )
h.zeq:	0040000+tag.prim+h.zeq-h.lt-1	" 0=
	0203500
zeq:	jms un
	sza
	jmp false
	jmp true

" 0< ( x -- flag )
h.zlt:	0040000+tag.prim+h.zlt-h.zeq-1	" 0<
	0203400
zlt:	jms un
	sma
	jmp false
	jmp true

" * ( a b -- a*b )  EAE signed multiply; the operand is the word
" after the instruction, so b is stored there first.
h.star:	0020000+tag.prim+h.star-h.zlt-1	" *
	0120000
star:	jms bin
	dac 1f
	lac i t3
	cll
	mul
1:	0
	lacq		" low half of the product
	dac i t3
	jmp next

" / ( a b -- a/b )  EAE signed divide, quotient in MQ.
h.slash:	0020000+tag.prim+h.slash-h.star-1	" /
	0170000
slash:	jms sdiv
	lacq
	dac i t3
	jmp next

" MOD ( a b -- a%b )  remainder in AC.
h.mod:	0060000+tag.prim+h.mod-h.slash-1	" MOD
	0555744
mod:	jms sdiv
	dac i t3
	jmp next

" EMIT ( c -- )
h.emit:	0100000+tag.prim+h.emit-h.mod-1	" EMIT
	0455551
emit:	jms pop.sp
	jms putc
	jmp next

" KEY ( -- c )  7-bit ASCII: a real Model 33 sends bit 8 set.
h.key:	0060000+tag.prim+h.key-h.emit-1	" KEY
	0534571
key:	jms getc
	dac i 012
	jmp next

" BASE ( -- addr )
h.base:	0100000+tag.var+h.base-h.key-1	" BASE
	0424163
base:	10

" (QUERY) ( -- )  read a line into the TIB.
h.xqry:	0160000+tag.prim+h.xqry-h.base-1	" (QUERY)
	0106165
xquery:	jms accept
	jmp next

" (PARSE) ( -- len )  next token; 0 at end of line.
h.xpar:	0160000+tag.prim+h.xpar-h.xqry-1	" (PARSE)
	0106041
xparse:	jms parse
	dac i 012
	jmp next

" (FIND) ( -- xt 1 | xt -1 | 0 )  look up the last parsed token;
" 1 if immediate, -1 if not.
h.xfnd:	0140000+tag.prim+h.xfnd-h.xpar-1	" (FIND)
	0104651
xfind:	jms find
	sad m1
	jmp 2f
	dac i 012	" xt
	dac t5
	lac i t5
	and o10000	" immediate bit
	sza
	jmp 1f
	lac m1
	dac i 012
	jmp next
1:	lac d1
	dac i 012
	jmp next
2:	cla
	dac i 012
	jmp next

" (NUMBER) ( -- n -1 | 0 )  convert the last parsed token.
h.xnum:	0200000+tag.prim+h.xnum-h.xfnd-1	" (NUMBER)
	0105665
xnumber:	jms number
	jmp 1f
	dac i 012
	lac m1
	dac i 012
	jmp next
1:	cla
	dac i 012
	jmp next

" (OK) ( -- )  end of line: check stack depth, then say ok.
h.xok:	0100000+tag.prim+h.xok-h.xnum-1	" (OK)
	0105753
xok:	lac 012
	cma
	tad ds0		" ds0 - SP - 1 >= 0: underflow
	sma
	jmp sterr
	lac 012
	cma
	tad dstop	" dstop - SP - 1 < 0: overflow
	spa
	jmp sterr
	lac m.ok
	jms puts
	jms crlf
	jmp next
sterr:	lac m.stack
	jmp error

" (ERR) ( -- )  the last token is neither a word nor a number.
h.xerr:	0120000+tag.prim+h.xerr-h.xok-1	" (ERR)
	0104562
xerr:	jmp undef

" EXECUTE ( xt -- )  DESIGN.md, Threading: run the xt's cell from a scratch
" slot followed by an EXIT cell, with IP pushed. Works for every tag.
h.exec:	0160000+tag.prim+h.exec-h.xerr-1	" EXECUTE
	0457045
execute:	jms pop.sp
	jms mkcell
xrun:	dac xcell	" (also entered from lvend with a cell to run)
	lac 010
	dac i 011	" push IP; the EXIT cell after xcell pops it
	lac xcellp
	dac 010		" IP -> xcell - 1
	jmp next
xcell:	0
	jmp ex.body
xcellp:	xcell-1

" COMPILE, ( xt -- )
h.compc:	0200000+tag.prim+h.compc-h.exec-1	" COMPILE,
	0435755
compc:	jms pop.sp
	jms mkcell
	jms comp
	jmp next

" LITERAL ( x -- )  compile x as a pooled literal.
h.lit:	0170000+tag.prim+h.lit-h.compc-1	" LITERAL
	0545164
literal:	jms pop.sp
	jms lit
	jmp next

" , ( x -- )
h.comma:	0020000+tag.prim+h.comma-h.lit-1	" ,
	0140000
comma:	jms pop.sp
	jms comp
	jmp next

" HERE ( -- addr )
h.here:	0100000+tag.prim+h.here-h.comma-1	" HERE
	0504562
here:	lac dp
	dac i 012
	jmp next

" ALLOT ( n -- )
h.allot:	0120000+tag.prim+h.allot-h.here-1	" ALLOT
	0415454
allot:	jms pop.sp
	tad dp
	dac t5
	cma
	tad pool	" pool - newdp - 1 < 0: no room
	spa
	jmp full
	lac t5
	dac dp
	jmp next

" STATE ( -- addr )  0 interpreting, -1 compiling.
h.state:	0120000+tag.var+h.state-h.allot-1	" STATE
	0636441
state:	0

" [ ( -- )
h.lbrac:	0030000+tag.prim+h.lbrac-h.state-1	" [
	0730000
lbrac:	dzm state
	jmp next

" ] ( -- )
h.rbrac:	0020000+tag.prim+h.rbrac-h.lbrac-1	" ]
	0750000
rbrac:	lac m1
	dac state
	jmp next

" ' ( "name" -- xt )
h.tick:	0020000+tag.prim+h.tick-h.rbrac-1	" '
	0070000
tick:	jms parse
	sna
	jmp noname
	jms find
	sad m1
	jmp undef
	dac i 012
	jmp next

" : ( "name" -- )  the header isn't linked until ; (no smudge bit).
h.colon:	0020000+tag.prim+h.colon-h.tick-1	" :
	0320000
colon:	cla		" tag.colon
	jms mkhdr
	dac cdp
	lac m1
	dac state
	jmp next

" ; ( -- )
h.semi:	0030000+tag.prim+h.semi-h.colon-1	" ;
	0330000
semi:	lac cdp
	sna
	jmp undef	" not compiling a definition
	lac c.exit
	jms comp
	lac cdp
	dac latest
	dzm cdp
	dzm state
	jmp next

" IMMEDIATE ( -- )  mark the latest word immediate.
h.immed:	0220000+tag.prim+h.immed-h.semi-1	" IMMEDIATE
	0515555
immed:	lac latest
	dac t5
	lac i t5
	and o767777
	tad o10000
	dac i t5
	jmp next

" CONSTANT ( x "name" -- )
h.const:	0200000+tag.prim+h.const-h.immed-1	" CONSTANT
	0435756
const:	lac o2000	" tag.const
	jms mkhdr
	dac latest
	jms pop.sp
	jms comp
	jmp next

" VARIABLE ( "name" -- )
h.var:	0200000+tag.prim+h.var-h.const-1	" VARIABLE
	0664162
var:	lac o3000	" tag.var
	jms mkhdr
	dac latest
	cla
	jms comp
	jmp next

" CREATE ( "name" -- )  a variable-tag word with no body yet.
h.create:	0140000+tag.prim+h.create-h.var-1	" CREATE
	0436245
create:	lac o3000	" tag.var
	jms mkhdr
	dac latest
	jmp next

" IF ( -- orig )
h.if:	0050000+tag.prim+h.if-h.create-1	" IF
	0514600
if:	jms lvst
	lac c.qbran
	jms comp
	lac dp
	dac i 012
	cla
	jms comp	" placeholder for (target - 1)
	jmp next

" THEN ( orig -- )
h.then:	0110000+tag.prim+h.then-h.if-1	" THEN
	0645045
then:	jms pop.sp
	dac t5
	lac dp
	tad m1
	dac i t5
	jmp lvend

" ELSE ( orig1 -- orig2 )
h.else:	0110000+tag.prim+h.else-h.then-1	" ELSE
	0455463
else:	lac c.bran
	jms comp
	lac dp
	dac t4
	cla
	jms comp
	jms pop.sp
	dac t5
	lac dp
	tad m1
	dac i t5
	lac t4
	dac i 012
	jmp next

" BEGIN ( -- dest )
h.begin:	0130000+tag.prim+h.begin-h.else-1	" BEGIN
	0424547
begin:	jms lvst
	lac dp
	dac i 012
	jmp next

" UNTIL ( dest -- )
h.until:	0130000+tag.prim+h.until-h.begin-1	" UNTIL
	0655664
until:	lac c.qbran
	jmp cbr

" AGAIN ( dest -- )
h.again:	0130000+tag.prim+h.again-h.until-1	" AGAIN
	0414741
again:	lac c.bran
cbr:	jms comp	" compile the branch cell, then (dest - 1)
	jms pop.sp
	tad m1
	jms comp
	jmp lvend

" WHILE ( dest -- orig dest )
h.while:	0130000+tag.prim+h.while-h.again-1	" WHILE
	0675051
while:	lac c.qbran
	jms comp
	jms pop.sp
	dac t4
	lac dp
	dac i 012
	cla
	jms comp
	lac t4
	dac i 012
	jmp next

" REPEAT ( orig dest -- )
h.repeat:	0150000+tag.prim+h.repeat-h.while-1	" REPEAT
	0624560
repeat:	lac c.bran
	jms comp
	jms pop.sp
	tad m1
	jms comp
	jmp then

" DO ( -- dest )
h.do:	0050000+tag.prim+h.do-h.repeat-1	" DO
	0445700
do:	jms lvst
	lac c.xdo
	jms comp
	lac dp
	dac i 012
	jmp next

" LOOP ( dest -- )
h.loop:	0110000+tag.prim+h.loop-h.do-1	" LOOP
	0545757
loop:	lac c.xloop
	jmp cbr

" . ( n -- )  signed, in BASE, followed by a space.
h.dot:	0020000+tag.prim+h.dot-h.loop-1	" .
	0160000
dot:	jms pop.sp
	sma
	jmp 1f
	cma
	tad d1
	dac t5
	lac o55		" '-'
	jms putc
	lac t5
1:	dac t5		" magnitude
	lac nbufp
	dac t6		" digits go into nbuf, least significant first
2:	lac base
	dac 3f
	lac t5
	cll
	idiv
3:	0
	isz t6
	dac i t6	" remainder = next digit
	lacq
	dac t5
	sza
	jmp 2b
4:	lac i t6	" print them back out, most significant first
	tad dm10
	spa
	tad dm7		" 0-9: d - 10 - 7 + 0101 = d + 060
	tad o101	" 10-35: d - 10 + 0101
	jms putc
	lac t6
	tad m1
	dac t6
	sad nbufp
	skp
	jmp 4b
	lac o40
	jms putc
	jmp next

" CR ( -- )
h.cr:	0040000+tag.prim+h.cr-h.dot-1	" CR
	0436200
cr:	jms crlf
	jmp next

" ( ( -- )  comment to the next ')' on the line.
h.paren:	0030000+tag.prim+h.paren-h.cr-1	" (
	0100000
paren:	lac inp
	sad tend
	jmp next
	dac t4
	isz inp
	lac i t4
	sad o51		" ')'
	jmp next
	jmp paren

" \ ( -- )  comment to the end of the line.
h.bslash:	0030000+tag.prim+h.bslash-h.paren-1	" \
	0740000
bslash:	lac tend
	dac inp
	jmp next

" QUIT ( -- ) ( R: i*x -- )  back to the interpreter.
h.quit:	0100000+tag.prim+h.quit-h.bslash-1	" QUIT
	0616551
xquit:	jmp quit

" BYE ( -- )  halt; CONTINUE resumes.
h.bye:	0060000+tag.prim+h.bye-h.quit-1	" BYE
	0427145
bye:	hlt
	jmp next

" J ( -- index )  the enclosing loop's index: R: ... limit counter
" [inner limit] [inner counter].
h.xj:	0020000+tag.prim+h.xj-h.bye-1	" J
	0520000
xj:	lac 011
	tad m2
	dac t2		" -> outer counter
	tad m1
	dac t4		" -> outer limit
	lac i t2
	tad i t4
	dac i 012
	jmp next

" (.") ( -- )  print the packed string that follows inline (two 9-bit
" characters per word, ended by a zero word), and resume after it.
h.xdotq:	0100000+tag.prim+h.xdotq-h.xj-1	" (.")
	0101602
xdotq:	lac 010
	tad d1
	jms puts	" leaves pstr at the terminating zero word
	lac pstr
	dac 010		" NEXT's pre-increment steps past it
	jmp next

" ." ( -- )  compile (.") and the string up to the next '"'.
h.dotq:	0050000+tag.prim+h.dotq-h.xdotq-1	" ."
	0160200
dotq:	lac c.xdotq
	jms comp
1:	jms sch
	jmp 2f		" end of string
	cll
	als 9
	dac t5		" high character
	jms sch
	jmp 3f		" odd length
	tad t5
	jms comp
	jmp 1b
3:	lac t5
	jms comp
2:	cla		" terminating zero word
	jms comp
	jmp next

" WORDS ( -- )  list the dictionary, newest first. A header keeps only
" the first three characters, so a longer name prints as those followed
" by one underscore per missing character (EXIT -> EXI_). Breaks lines
" at about 60 columns: a Model 33 doesn't wrap.
h.words:	0120000+tag.prim+h.words-h.dotq-1	" WORDS
	0675762
words:	jms crlf
	dzm wcol
	lac latest
1:	dac wp		" header
	lac i wp
	cll
	lrs 13
	dac wcnt	" name length
	cma
	tad d1
	dac wr		" -(characters left to print)
	lac m3
	dac wk		" stored characters left
	lac wp
	tad d1
	dac t6
	lac i t6	" packed name word
	lmq
2:	cla
	cll
	lls 6		" next SIXBIT character
	tad o40
	jms putc
	isz wr
	skp
	jmp 3f		" whole name printed
	isz wk
	jmp 2b
4:	lac o137	" '_' for each character not stored
	jms putc
	isz wr
	jmp 4b
3:	lac o40
	jms putc
	lac wcnt
	tad d1
	tad wcol
	dac wcol
	tad dm60
	spa
	jmp 5f
	jms crlf
	dzm wcol
5:	lac i wp	" next header
	and lmask
	sna
	jmp next
	cma
	tad wp
	jmp 1b

" TAPE ( -- )  take input lines from the paper-tape reader until ^D.
h.tape:	0100000+tag.prim+h.tape-h.words-1	" TAPE
	0644160
tape:	lac m1
	dac tapein
	jmp next

" EOT ( -- )  end tape input, like ^D: back to the keyboard, and the rest
" of this line is ignored. A visible alternative to ^D in source files.
h.eot:	0060000+tag.prim+h.eot-h.tape-1	" EOT
	0455764
eot:	dzm tapein
	lac tend
	dac inp
	jmp next

" */ ( a b c -- a*b/c )  the product is 36 bits (EAE MUL into AC:MQ), so
" it can't overflow before the divide (EAE DIV). Truncates toward zero.
h.stsl:	0040000+tag.prim+h.stsl-h.eot-1	" */
	0121700
stsl:	jms pop.sp	" c
	dac sdc
	jms bin		" AC = b, t3 -> a
	dac t4
	xor i t3
	xor sdc
	dac qsgn	" sign bit: the result's sign
	lac t4
	jms absv
	dac 1f
	lac i t3
	jms absv
	cll
	mul		" AC:MQ = |a| * |b|
1:	0
	dac t4		" high half
	lac sdc
	jms absv
	dac 2f
	lac t4
	cll
	div		" MQ = AC:MQ / |c|
2:	0
	lacq
	dac t4
	lac qsgn
	sma
	jmp 3f
	lac t4
	cma
	tad d1
	skp
3:	lac t4
	dac i t3
	jmp next

" DLIST ( -- addr )  the 1024-word Type 340 display list (below 4K, as the
" 340's 12-bit address counter requires). The 340 runs it from the top.
h.dlist:	0120000+tag.const+h.dlist-h.stsl-1	" DLIST
	0445451
	dlbuf

" DISPLAY ( -- addr )  nonzero: keep the 340 refreshing DLIST.
h.dsply:	0160000+tag.var+h.dsply-h.dlist-1	" DISPLAY
	0445163
display:	0

" (S") ( -- c-addr u )  the string that follows inline: a count, then one
" character per word. Resume after it.
h.xsq:	0060000+tag.prim+h.xsq-h.dsply-1	" (S"
	0106302
xsq:	lac 010
	tad d1
	dac t5		" -> count
	tad d1
	dac i 012	" c-addr
	lac i t5
	dac i 012	" u
	tad t5
	dac 010		" the last character; NEXT steps past it
	jmp next

" S" ( "ccc<quote>" -- c-addr u )  compiling (a definition or an
" interpretive control structure): compile (S") and the string inline.
" Interpreting: copy it to sbuf, which the next interpreted S" reuses.
h.sq:	0050000+tag.prim+h.sq-h.xsq-1	" S"
	0630200
sq:	lac state
	sna
	jmp 3f
	lac c.xsq
	jms comp
	lac dp
	dac sqp		" -> the count, filled in at the end
	jms comp
1:	jms sch
	jmp 2f
	jms comp
	jmp 1b
2:	lac sqp
	cma
	tad dp		" dp - sqp - 1
	dac i sqp
	jmp next
3:	lac sbufp
	dac sqp
	dac i 012	" c-addr
4:	jms sch
	jmp 5f
	dac i sqp
	isz sqp
	jmp 4b
5:	lac sbufp
	cma
	tad sqp
	tad d1		" sqp - sbuf
	dac i 012	" u
	jmp next

" CHAR ( "name" -- char )  the first character of the next token.
h.char:	0100000+tag.prim+h.char-h.sq-1	" CHAR
	0435041
char:	jms parse
	sna
	jmp noname
	lac i wptr
	dac i 012
	jmp next

" .( ( "ccc<paren>" -- )  print up to the next ')' on the line, at once,
" compiling or not.
h.dotp:	0050000+tag.prim+h.dotp-h.char-1	" .(
	0161000
dotp:	lac inp
	sad tend
	jmp next
	dac t4
	isz inp
	lac i t4
	sad o51		" ')'
	jmp next
	jms putc
	jmp dotp

latest:	h.dotp		" head of the dictionary chain

" --- stacks and terminal input buffer (DESIGN.md, Memory) ---
rstack:	.=.+040		" 32 words
dstack:	.=.+040		" 32 words
tib:	.=.+0120	" 80 characters, one per word
nbuf:	.=.+022		" digits for "." (18 in base 2)
