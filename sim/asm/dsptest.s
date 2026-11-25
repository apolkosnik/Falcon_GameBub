; Bare test ROM (in place of TOS): the DSP through its host port as TOS's
; Dsp_ExecBoot does it. The 512-word bootstrap (a host echo program, then
; zeros) is sent through TXH/TXM/TXL at $FFA205-7, waiting for TXDE; then 16
; words are sent and each must come back plus one (RXDF). The program is
; Falcon_MiSTer's tb/dsp echo program (tb_host.cpp), encoded by its tb_gen.h.
; $1000: words right, $1004: words wrong or not answered, $FFC: $D0E0600D at
; the end.
;   vasmm68k_mot -Fbin -quiet -o dsptest.rom dsptest.s
; SPDX-License-Identifier: GPL-2.0-or-later
	org	$E00000
	dc.l	$00010000
	dc.l	start
start:	move.w	#$2700,sr
	clr.l	$1000.w
	clr.l	$1004.w
	; the DSP's reset line, PSG port A bit 4, as Dsp_ExecBoot: port A an
	; output, the bit high, then low (the DSP waits for its bootstrap)
	lea	$ffff8800,a2
	move.b	#7,(a2)
	move.b	#$c0,2(a2)
	move.b	#14,(a2)
	move.b	#$ff,2(a2)
	moveq	#50,d0
.rst:	dbf	d0,.rst
	move.b	#$ef,2(a2)
	lea	$ffffa200,a0
	lea	prog(pc),a1
	move.w	#511,d7
.boot:	moveq	#0,d0
	cmp.l	#progend,a1
	bhs.s	.zero
	move.l	(a1)+,d0
.zero:	bsr	txword
	dbf	d7,.boot
	; the echo
	move.l	#$123456,d5
	moveq	#15,d7
.echo:	move.l	d5,d0
	bsr	txword
	move.l	#200000,d2
.wrx:	btst	#0,2(a0)		; RXDF
	bne.s	.got
	subq.l	#1,d2
	bne.s	.wrx
	addq.l	#1,$1004.w
	bra.s	.next
.got:	moveq	#0,d1
	move.b	5(a0),d1
	lsl.l	#8,d1
	move.b	6(a0),d1
	lsl.l	#8,d1
	move.b	7(a0),d1
	move.l	d5,d0
	addq.l	#1,d0
	and.l	#$ffffff,d0
	cmp.l	d0,d1
	bne.s	.bad
	addq.l	#1,$1000.w
	bra.s	.next
.bad:	addq.l	#1,$1004.w
.next:	add.l	#$010203,d5
	and.l	#$3fffff,d5
	dbf	d7,.echo
	move.l	#$d0e0600d,$ffc.w
.loop:	bra.s	.loop

; d0: a 24-bit word to the DSP, once TXDE
txword:	btst	#1,2(a0)
	beq.s	txword
	swap	d0
	move.b	d0,5(a0)
	swap	d0
	move.w	d0,d1
	lsr.w	#8,d1
	move.b	d1,6(a0)
	move.b	d0,7(a0)
	rts

prog:	dc.l	$44F400,$000001,$0AA980,$000002,$084E2B,$200040,$0AA981,$000006,$08CE2B,$0C0002
progend:
