" Test-only code, assembled after src/kernel.s and before src/end.s by
" test/run_tests.py. Nothing here is in the dictionary chain.

" --- call/return: a CAL cell into GO, whose thread is BYE EXIT ---
bye.body:
	lac byemark
	dac i 012
	jmp next
byemark:
	0123456

go.body:
	jmp bye.body
	jmp ex.body

cboot:	go.body
halt1:	hlt
bootip:	cboot-1

start:	lac bootip
	dac 010
	jmp next

" --- find: the runner deposits tcnt/tname, then starts here ---
ftest:	jms find
	hlt

" --- thread runner: the runner deposits (thread - 1) into tip ---
tip:	0
trun:	lac tip
	dac 010
	jmp next

" One-cell thread for single-primitive tests: the runner deposits the
" data stack, SP, and the cell to run into tcell.
tcell:	0
	hlt

" Constants for hand-built threads (LAC-tag cells push them).
d0:	0
d3:	3
d5:	5
d7:	7
o111:	0111
o222:	0222

" ?BRANCH on false: branches over the 111 push.   Expected stack: 222
tqf:	lac d0
	jmp qbran
	1f-1
	lac o111
1:	lac o222
	hlt

" ?BRANCH on true: falls through.   Expected stack: 111 222
tqt:	lac d1
	jmp qbran
	1f-1
	lac o111
1:	lac o222
	hlt

" BRANCH: unconditional.   Expected stack: 222
tbr:	jmp bran
	1f-1
	lac o111
1:	lac o222
	hlt

" 5 0 DO I LOOP   Expected stack: 0 1 2 3 4
tlp0:	lac d5
	lac d0
	jmp xdo
1:	jmp xi
	jmp xloop
	1b-1
	hlt

" 7 3 DO I LOOP   Expected stack: 3 4 5 6
tlp3:	lac d7
	lac d3
	jmp xdo
1:	jmp xi
	jmp xloop
	1b-1
	hlt

" --- input: results go to res[] through auto-index 015 ---
resp:	res-1
tval:	0

" accept one line, then parse every token: (wlen, tcnt, tname) each,
" then a 0 word.
tpar:	lac resp
	dac 015
	jms accept
1:	jms parse
	dac i 015
	sna
	hlt
	lac tcnt
	dac i 015
	lac tname
	dac i 015
	jmp 1b

" accept one line, then convert every token: (1, value) on success,
" (0, 0) on failure.
tnum:	lac resp
	dac 015
	jms accept
1:	jms parse
	sna
	hlt
	jms number
	jmp 2f
	dac tval
	lac d1
	dac i 015
	lac tval
	dac i 015
	jmp 1b
2:	cla
	dac i 015
	dac i 015
	jmp 1b

res:	.=.+040
