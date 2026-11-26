; Bare test ROM (in place of TOS): reads the MC146818's time as TOS and
; EmuTOS do ($FF8961 index, $FF8963 data): registers 0-13 are stored at
; $1000-$100D (as read, register B's DM left as the core set it), then
; again after DM is set (binary, as EmuTOS sets it) at $1010-$101D, and
; once more when the seconds register has changed at $1020-$102D ($1030:
; $FFFFFFFF if it did not change within the wait).
; $FFC: $D0E0600D at the end.
;   vasmm68k_mot -Fbin -quiet -o rtctest.rom rtctest.s
; SPDX-License-Identifier: GPL-2.0-or-later
	org	$E00000
	dc.l	$00010000
	dc.l	start
start:	move.w	#$2700,sr
	lea	$ffff8961,a0
	lea	$1000.w,a1
	bsr.s	dump
	move.b	#11,(a0)		; register B: DM (binary), 24 h
	move.b	2(a0),d0
	or.b	#$06,d0
	move.b	d0,2(a0)
	lea	$1010.w,a1
	bsr.s	dump
	move.b	$1010.w,d3		; the seconds read last
	move.l	#2000000,d1
.w:	move.b	#10,(a0)
.wu:	btst	#7,2(a0)
	bne.s	.wu
	clr.b	(a0)
	cmp.b	2(a0),d3
	bne.s	.tick
	subq.l	#1,d1
	bne.s	.w
	move.l	#$ffffffff,$1030.w
.tick:
	lea	$1020.w,a1
	bsr.s	dump
	move.l	#$d0e0600d,$ffc.w
.loop:	bra.s	.loop

; registers 0-13 to (a1), each once UIP is clear
dump:	moveq	#0,d2
.r:	move.b	#10,(a0)
.u:	btst	#7,2(a0)
	bne.s	.u
	move.b	d2,(a0)
	move.b	2(a0),(a1)+
	addq.b	#1,d2
	cmp.b	#14,d2
	bne.s	.r
	rts
