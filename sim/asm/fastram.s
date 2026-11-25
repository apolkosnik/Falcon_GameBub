; Bare test ROM (in place of TOS) for the 68060 variant: CT60 mode's 48 MB
; of Fast RAM at $01000000 (chip 0's upper half, then chip 1). Longs
; (address-derived), then words and bytes over them, in 256 KB at each end
; of both chips' parts; everything read back. The address after the Fast RAM
; must bus error. $1000: words wrong, $1004: 1 if $04000000 bus errored,
; $FFC: $D0E0600D at the end.
;   vasmm68k_mot -m68060 -Fbin -quiet -o fastram.rom fastram.s
; SPDX-License-Identifier: GPL-2.0-or-later
	org	$E00000
	dc.l	$00010000
	dc.l	start
start:	move.w	#$2700,sr
	clr.l	$1000.w
	clr.l	$1004.w
	lea	region1,a4
	bsr	test
	lea	region2,a4
	bsr	test
	lea	region3,a4
	bsr	test
	lea	region4,a4
	bsr	test
	; the end of the Fast RAM bus errors
	move.l	#berr,$8.w
	move.l	sp,a6
	move.l	$04000000,d0
	bra.s	done
berr:	move.l	a6,sp
	move.l	#1,$1004.w
done:	move.l	#$d0e0600d,$ffc.w
.loop:	bra.s	.loop

; (a4): start, length in bytes
test:	move.l	(a4),a0
	move.l	4(a4),d7
	lsr.l	#2,d7
	subq.l	#1,d7
	move.l	a0,a1
.wl:	move.l	a1,d0
	eor.l	#$5a5aa5a5,d0
	move.l	d0,(a1)+
	subq.l	#1,d7
	bpl.s	.wl
	; a word and a byte into every 64-byte block
	move.l	a0,a1
	move.l	4(a4),d7
	lsr.l	#6,d7
	subq.l	#1,d7
.ww:	move.w	#$1234,10(a1)
	move.b	#$77,37(a1)
	lea	64(a1),a1
	subq.l	#1,d7
	bpl.s	.ww
	; read back
	move.l	a0,a1
	move.l	4(a4),d7
	lsr.l	#2,d7
	subq.l	#1,d7
.rl:	move.l	a1,d0
	eor.l	#$5a5aa5a5,d0
	move.l	a1,d1
	and.w	#63,d1
	cmp.w	#8,d1
	bne.s	.n1
	and.l	#$ffff0000,d0		; bytes 10, 11: $1234
	or.w	#$1234,d0
.n1:	cmp.w	#36,d1
	bne.s	.n2
	move.l	a1,d2
	eor.l	#$5a5aa5a5,d2
	and.l	#$ff00ffff,d2
	or.l	#$00770000,d2
	move.l	d2,d0
.n2:	cmp.l	(a1)+,d0
	beq.s	.ok
	addq.l	#1,$1000.w
.ok:	subq.l	#1,d7
	bpl.s	.rl
	rts

region1: dc.l	$01000000,$00040000
region2: dc.l	$01fc0000,$00040000
region3: dc.l	$02000000,$00040000
region4: dc.l	$03fc0000,$00040000
