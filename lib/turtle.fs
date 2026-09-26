\ Turtle graphics on the Type 340 display. Load it with TAPE (see the
\ README): needs Open SIMH with "set dpy enabled". The screen is 1024 x 1024
\ with the origin at the bottom left; the turtle starts in the middle,
\ heading 0 is up, and RIGHT turns clockwise, as in Logo.
decimal

\ sin(0..90 degrees) * 16384
create sines
0 , 286 , 572 , 857 , 1143 , 1428 , 1713 , 1997 , 2280 , 2563 , 2845 ,
3126 , 3406 , 3686 , 3964 , 4240 , 4516 , 4790 , 5063 , 5334 , 5604 ,
5872 , 6138 , 6402 , 6664 , 6924 , 7182 , 7438 , 7692 , 7943 , 8192 ,
8438 , 8682 , 8923 , 9162 , 9397 , 9630 , 9860 , 10087 , 10311 ,
10531 , 10749 , 10963 , 11174 , 11381 , 11585 , 11786 , 11982 , 12176 ,
12365 , 12551 , 12733 , 12911 , 13085 , 13255 , 13421 , 13583 , 13741 ,
13894 , 14044 , 14189 , 14330 , 14466 , 14598 , 14726 , 14849 , 14968 ,
15082 , 15191 , 15296 , 15396 , 15491 , 15582 , 15668 , 15749 , 15826 ,
15897 , 15964 , 16026 , 16083 , 16135 , 16182 , 16225 , 16262 , 16294 ,
16322 , 16344 , 16362 , 16374 , 16382 , 16384 ,
: s180 ( 0..179 -- n ) dup 90 > if 180 swap - then sines + @ ;
: sin ( degrees -- 16384*sin )
  360 mod dup 0< if 360 + then
  dup 180 < if s180 else 180 - s180 negate then ;
: cos ( degrees -- 16384*cos ) 90 + sin ;

\ Turtle state. The position is kept in 1/64 pixel so rounding doesn't
\ accumulate; PX rounds it to a pixel.
variable tx   variable ty   variable th   variable pen
: px ( fixed -- pixel ) 32 + 64 / ;

\ The display list (DLIST, in the kernel): a header that positions the
\ beam, then one vector word per step of at most 127 pixels, then an
\ escape and a stop. The 340 may be running the list while we append, so
\ the new terminator is written before the word that replaces the old one.
variable dl>
dlist 1022 + constant dlend
: dl, ( w -- )
  dl> @ dlend = if ." display list full?" cr quit then
  131072 dl> @ 1+ !   1024 dl> @ 2 + !   dl> @ !   1 dl> +! ;
: vword ( dx dy -- w ) \ |dx| and |dy| at most 127
  dup 0< if negate 256 * 32768 + else 256 * then
  swap dup 0< if negate 128 + then +
  pen @ if 65536 + then ;

\ A move of any length becomes N steps whose sizes add up exactly.
variable vdx   variable vdy   variable vn
: part ( k -- x y ) dup vdx @ * vn @ /  swap vdy @ * vn @ / ;
: vec ( dx dy -- )
  vdy ! vdx !  vdx @ abs vdy @ abs max 126 + 127 / vn !
  vn @ if vn @ 0 do i 1+ part i part rot swap - >r - r> vword dl, loop then ;

\ Moves that would leave the screen are refused.
: onscreen? ( fixed -- flag ) px dup 0< 0= swap 1024 < and ;
: moveto ( x y -- ) \ fixed-point destination
  over onscreen? over onscreen? and 0= if 2drop ." off screen?" cr quit then
  2dup px ty @ px - >r px tx @ px - r> vec  ty ! tx ! ;

\ Start a new display list with the beam at the turtle.
: newlist ( -- )
  0 display !
  8271 dlist !                  \ parameters: point mode, scale 1, bright
  tx @ px 8192 + dlist 1+ !     \ point: x
  ty @ px 98304 + dlist 2 + !   \ point: y, then vector mode
  dlist 3 + dl> !
  131072 dl> @ !   1024 dl> @ 1+ !
  -1 display ! ;

: forward ( n -- )
  dup th @ sin 256 */ tx @ +
  swap th @ cos 256 */ ty @ +
  moveto ;
: back ( n -- ) negate forward ;
: right ( degrees -- ) th +! ;
: left ( degrees -- ) negate right ;
: penup ( -- ) 0 pen ! ;
: pendown ( -- ) -1 pen ! ;
: home ( -- ) 32768 32768 moveto  0 th ! ;
: clearscreen ( -- ) 32768 tx !  32768 ty !  0 th !  newlist ;

: fd forward ;   : bk back ;   : rt right ;   : lt left ;
: pu penup ;   : pd pendown ;   : cs clearscreen ;

pendown clearscreen
