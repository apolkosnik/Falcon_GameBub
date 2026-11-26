; Bare test ROM (in place of TOS): reads the Falcon's enhanced joystick
; ports as a Jagpad program does. For each of the eight select lines (one
; bit of $FF9203 low at a time: port A rows 0-3, port B rows 0-3) the
; buttons word $FF9200 and the directions word $FF9202 are stored, two
; words a row, at $1000-$101F; then the paddles $FF9210, $FF9212, $FF9214,
; $FF9216 at $1020-$1027. $FFC: $D0E0600D at the end.
; The pads are held by the bench (sim_main --pad0 / --pad1).
;   vasmm68k_mot -Fbin -quiet -o padtest.rom padtest.s
; SPDX-License-Identifier: GPL-2.0-or-later
	org	$E00000
	dc.l	$00010000
	dc.l	start
start:	move.w	#$2700,sr
	move.l	#20000,d0		; let the inputs settle
.w:	subq.l	#1,d0
	bne.s	.w
	lea	$ffff9200,a0
	lea	$1000.w,a1
	lea	rows(pc),a2
	moveq	#7,d1
.row:	move.b	(a2)+,3(a0)		; the select lines ($FF9203)
	nop
	move.w	(a0),(a1)+		; buttons
	move.w	2(a0),(a1)+		; directions
	dbra	d1,.row
	move.w	$10(a0),(a1)+		; paddles
	move.w	$12(a0),(a1)+
	move.w	$14(a0),(a1)+
	move.w	$16(a0),(a1)+
	move.b	#$ff,3(a0)
	move.l	#$d0e0600d,$ffc.w
.loop:	bra.s	.loop

rows:	dc.b	$fe,$fd,$fb,$f7,$ef,$df,$bf,$7f
