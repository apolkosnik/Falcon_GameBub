; Bare test ROM (in place of TOS): Falcon DMA sound, 16-bit stereo at
; 49170 Hz (25.175 MHz clock, divider 1), a square wave from RAM through
; the crossbar to the DAC, the PSG's channel A on the ADC input, both in the
; codec's adder; the bench reports the audio outputs' range (sim/run_tests.sh).
;   vasmm68k_mot -Fbin -quiet -o sndtest.rom sndtest.s
; SPDX-License-Identifier: GPL-2.0-or-later
	org	$E00000
	dc.l	$00010000
	dc.l	start
start:	move.w	#$2700,sr
	; a 64-word frame at $2000: 16 stereo pairs high, 16 low
	lea	$2000,a0
	moveq	#15,d0
.hi:	move.l	#$40004000,(a0)+
	dbf	d0,.hi
	moveq	#15,d0
.lo:	move.l	#$C000C000,(a0)+
	dbf	d0,.lo
	lea	$ffff8900,a1
	clr.w	(a1)			; stopped
	move.b	#$00,$3(a1)		; frame start $002000
	move.b	#$20,$5(a1)
	move.b	#$00,$7(a1)
	move.b	#$00,$f(a1)		; frame end $002080
	move.b	#$20,$11(a1)
	move.b	#$80,$13(a1)
	clr.b	$20(a1)			; one track
	move.b	#$40,$21(a1)		; 16 bit stereo
	clr.w	$30(a1)			; sources: 25 MHz clock
	clr.w	$32(a1)			; destinations: the DAC from DMA play
	move.b	#1,$35(a1)		; divider 1: 49170 Hz
	move.b	#3,$37(a1)		; adder: ADC + DAC
	move.b	#3,$38(a1)		; ADC: PSG both sides
	clr.w	$3a(a1)			; attenuation 0
	move.b	#3,$1(a1)		; play, repeat
	; PSG: channel A tone, full volume
	lea	$ffff8800,a2
	move.b	#0,(a2)
	move.b	#$40,2(a2)
	move.b	#1,(a2)
	move.b	#0,2(a2)
	move.b	#7,(a2)
	move.b	#$fe,2(a2)
	move.b	#8,(a2)
	move.b	#15,2(a2)
	move.l	#$d0e0600d,$ffc.w
.loop:	bra.s	.loop
