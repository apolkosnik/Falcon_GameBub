; Bare test ROM (in place of TOS): as dspsnd.s, the DSP's sawtooth through
; the crossbar to the DAC, but sent as a replay routine sends its samples:
; from the SSI transmit interrupt, a fast interrupt (the two words at the
; vector, P:$0010, and the same at the transmit-with-exception vector,
; P:$0012), while the main program waits in a loop. IPR gives the SSI
; level 2, CRB enables the transmit interrupt, and the main program unmasks
; interrupts in the SR.
; The bench checks the audio (--audio-ramp 50:8).
; $FFC: $D0E0600D once the crossbar is set.
;   vasmm68k_mot -Fbin -quiet -o dspsndi.rom dspsndi.s
; SPDX-License-Identifier: GPL-2.0-or-later
	org	$E00000
	dc.l	$00010000
	dc.l	start
start:	move.w	#$2700,sr
	; the DSP's reset line, PSG port A bit 4: an output, high, then low
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
	; the crossbar
	lea	$ffff8900,a1
	clr.b	$20(a1)			; one track, track 0 monitored
	move.w	#$0090,$30(a1)		; DSP transmit: connected, 25 MHz, no handshake
	move.w	#$2000,$32(a1)		; the DAC from the DSP transmitter
	move.b	#1,$35(a1)		; divider 1: 49170 Hz
	move.b	#2,$37(a1)		; the codec's adder: the crossbar (DAC) only
	clr.w	$3a(a1)			; no attenuation
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

; the DSP program, from P:$0000
prog:	dc.l	$0c0040			; $00 jmp $40               (reset)
	dcb.l	15,$000000		; $01-$0f nop
	dc.l	$08cc2f			; $10 movep a1,x:$ffef      SSI transmit: TX
	dc.l	$200040			; $11 add x0,a
	dc.l	$08cc2f			; $12 movep a1,x:$ffef      SSI transmit with exception
	dc.l	$200040			; $13 add x0,a
	dcb.l	$40-$14,$000000		; $14-$3f nop
	dc.l	$08f4ac,$004100		; $40 movep #$4100,x:$ffec  CRA: 16 bit, 2 words a frame
	dc.l	$08f4ad,$005800		; $42 movep #$5800,x:$ffed  CRB: TIE, TE, network mode
	dc.l	$08f4a1,$0001f8		; $44 movep #$01f8,x:$ffe1  PCC: port C pins 3-8 the SSI
	dc.l	$08f4bf,$003000		; $46 movep #$3000,x:$ffff  IPR: the SSI at level 2
	dc.l	$44f400,$000800		; $48 move #$000800,x0      the step: $0008 in the 16-bit word
	dc.l	$200013			; $4a clr a
	dc.l	$00fcb8			; $4b andi #$fc,mr          interrupts unmasked
	dc.l	$0c004c			; $4c jmp $4c
progend:
