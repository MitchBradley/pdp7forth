" PDP-7 Forth -- kernel
"
" Pieces so far: NEXT, the CAL trap handler (nest), dictionary search
" (find), stack pops, the primitive set, flow-control runtime words,
" console I/O, line input (accept), token parsing (parse) and number
" conversion (number). Not yet: the outer interpreter and the ":"/";"
" compiler.
"
" From the repo root: "make" assembles to build/kernel.lst; "make test"
" runs test/run_tests.py, which assembles this file with test/tests.s
" and checks the results under SimH. tools/hdr.py prints header words.
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
0		" 013: free
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
getc:	0
1:	ksf
	jmp 1b
	krb
	and o177	" 7-bit ASCII
	jmp i getc

putc:	0
	tls
1:	tsf
	jmp 1b
	jmp i putc

" --- find: dictionary search (DESIGN.md, Dictionary/headers) ---
" Call with "jms find" after setting tcnt/tname. Returns AC = body
" address, or AC = -1 if the name isn't in the chain rooted at "latest".
find:	0
	lac latest
1:	dac p
	dac 010
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
2:	lac i 010	" name word at p+1
	sad tname
	jmp 5f
	jmp 3b
4:	lac m1		" not found
	jmp i find
5:	lac p		" found: body = p+2
	tad d2
	jmp i find

p:	0
tcnt:	0		" count field of the name being sought
tname:	0		" packed SIXBIT name word being sought

" --- accept: read a line into tib, echoing ---
" CR ends the line (not stored, not echoed). Rubout and backspace drop
" the last character and echo a backspace. Characters past the 80th are
" ignored. Leaves inp = tib and tend = tib + count.
accept:	0
	lac tibp
	dac inp
	dac tend
1:	jms getc
	sad o15
	jmp i accept
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

" --- scratch and state ---
t2:	0
t3:	0
t4:	0
t5:	0
t6:	0
inp:	0		" next unread character in tib
tend:	0		" tib + line length
wptr:	0		" start of the last parsed token
wlen:	0		" its length
nacc:	0
nneg:	0
qsgn:	0
rsgn:	0
dp:	end		" next free dictionary word
pool:	020000		" lowest literal-pool entry; the pool grows down
tibp:	tib
tibe:	tib+0120

" --- manifest constants ---
m1:	-1
m2:	-2
m3:	-3
dm7:	-7
dm10:	-10
d1:	1
d2:	2
d10:	10
o10:	010
o15:	015
o40:	040
o55:	055
o77:	077
o177:	0177
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

" === Kernel dictionary ===
" Primitive bodies end with "jmp next". Branch-type words take an inline
" cell holding (target - 1), which goes straight into IP.

" EXIT ( -- ) ( R: ip -- )  EXIT is an ordinary primitive, not a spare tag.
h.ex:	0100000 tag.prim 0	" EXIT
	0457051
ex.body:
	jms pop.rp	" AC := the caller's CAL-cell address, pushed by nest
	dac 010		" IP := that address directly -- no "tad m1" here,
			" unlike nest: EXIT resumes the cell *after* the
			" call, nest enters the callee's body
	jmp next

" BRANCH ( -- )  IP := inline cell (target - 1).
h.bran:	0140000 tag.prim h.bran-h.ex-1	" BRANCH
	0426241
bran:	lac i 010
	dac 010
	jmp next

" ?BRANCH ( flag -- )  branch if zero, else step over the inline cell.
h.qbran:	0160000 tag.prim h.qbran-h.bran-1	" ?BRANCH
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
h.xdo:	0100000 tag.prim h.xdo-h.qbran-1	" (DO)
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
h.xloop:	0140000 tag.prim h.xloop-h.xdo-1	" (LOOP)
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
h.xi:	0020000 tag.prim h.xi-h.xloop-1	" I
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
h.dup:	0060000 tag.prim h.dup-h.xi-1	" DUP
	0446560
dup:	jms un
	dac i 012
	jmp next

" DROP ( x -- )
h.drop:	0100000 tag.prim h.drop-h.dup-1	" DROP
	0446257
drop:	lac 012
	tad m1
	dac 012
	jmp next

" SWAP ( a b -- b a )
h.swap:	0100000 tag.prim h.swap-h.drop-1	" SWAP
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
h.over:	0100000 tag.prim h.over-h.swap-1	" OVER
	0576645
over:	lac 012
	tad m1
	dac t3
	lac i t3
	dac i 012
	jmp next

" >R ( x -- ) ( R: -- x )
h.tor:	0040000 tag.prim h.tor-h.over-1	" >R
	0366200
tor:	jms pop.sp
	dac i 011
	jmp next

" R> ( -- x ) ( R: x -- )
h.rfrom:	0040000 tag.prim h.rfrom-h.tor-1	" R>
	0623600
rfrom:	jms pop.rp
	dac i 012
	jmp next

" R@ ( -- x ) ( R: x -- x )
h.rat:	0040000 tag.prim h.rat-h.rfrom-1	" R@
	0624000
rat:	lac 011
	dac t3
	lac i t3
	dac i 012
	jmp next

" @ ( addr -- x )  indirection uses only the low 13 bits, so LAW-form
" (negative) addresses from variables work unchanged.
h.fetch:	0020000 tag.prim h.fetch-h.rat-1	" @
	0400000
fetch:	jms un
	dac t4
	lac i t4
	dac i t3
	jmp next

" ! ( x addr -- )
h.store:	0020000 tag.prim h.store-h.fetch-1	" !
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
h.plus:	0020000 tag.prim h.plus-h.store-1	" +
	0130000
plus:	jms bin
	tad i t3
	dac i t3
	jmp next

" - ( a b -- a-b )
h.minus:	0020000 tag.prim h.minus-h.plus-1	" -
	0150000
minus:	jms bin
	cma		" -b-1
	tad i t3
	tad d1
	dac i t3
	jmp next

" AND ( a b -- a&b )
h.and:	0060000 tag.prim h.and-h.minus-1	" AND
	0415644
and.b:	jms bin
	and i t3
	dac i t3
	jmp next

" OR ( a b -- a|b )  no OR instruction: (a^b) ^ (a&b).
h.or:	0040000 tag.prim h.or-h.and-1	" OR
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
h.xor:	0060000 tag.prim h.xor-h.or-1	" XOR
	0705762
xor.b:	jms bin
	xor i t3
	dac i t3
	jmp next

" INVERT ( x -- ~x )
h.inv:	0140000 tag.prim h.inv-h.xor-1	" INVERT
	0515666
invert:	jms un
	cma
	dac i t3
	jmp next

" NEGATE ( x -- -x )
h.neg:	0140000 tag.prim h.neg-h.inv-1	" NEGATE
	0564547
negate:	jms un
	cma
	tad d1
	dac i t3
	jmp next

" = ( a b -- flag )
h.eq:	0020000 tag.prim h.eq-h.neg-1	" =
	0350000
equal:	jms bin
	sad i t3	" skip if different
	jmp true
	jmp false

" U< ( a b -- flag )  b + ~a carries into the link iff b > a.
h.ult:	0040000 tag.prim h.ult-h.eq-1	" U<
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
h.lt:	0020000 tag.prim h.lt-h.ult-1	" <
	0340000
less:	jms bin
	xor o400k
	dac i t2
	lac i t3
	xor o400k
	dac i t3
	jmp ultc

" 0= ( x -- flag )
h.zeq:	0040000 tag.prim h.zeq-h.lt-1	" 0=
	0203500
zeq:	jms un
	sza
	jmp false
	jmp true

" 0< ( x -- flag )
h.zlt:	0040000 tag.prim h.zlt-h.zeq-1	" 0<
	0203400
zlt:	jms un
	sma
	jmp false
	jmp true

" * ( a b -- a*b )  EAE signed multiply; the operand is the word
" after the instruction, so b is stored there first.
h.star:	0020000 tag.prim h.star-h.zlt-1	" *
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
h.slash:	0020000 tag.prim h.slash-h.star-1	" /
	0170000
slash:	jms sdiv
	lacq
	dac i t3
	jmp next

" MOD ( a b -- a%b )  remainder in AC.
h.mod:	0060000 tag.prim h.mod-h.slash-1	" MOD
	0555744
mod:	jms sdiv
	dac i t3
	jmp next

" EMIT ( c -- )
h.emit:	0100000 tag.prim h.emit-h.mod-1	" EMIT
	0455551
emit:	jms pop.sp
	jms putc
	jmp next

" KEY ( -- c )  7-bit ASCII: a real Model 33 sends bit 8 set.
h.key:	0060000 tag.prim h.key-h.emit-1	" KEY
	0534571
key:	jms getc
	dac i 012
	jmp next

" BASE ( -- addr )
h.base:	0100000 tag.var h.base-h.key-1	" BASE
	0424163
base:	10

latest:	h.base		" head of the dictionary chain

" --- stacks and terminal input buffer (DESIGN.md, Memory) ---
rstack:	.=.+040		" 32 words
dstack:	.=.+040		" 32 words
tib:	.=.+0120	" 80 characters, one per word
