; Bare test ROM (in place of TOS): the DSP plays through the crossbar to
; the DAC, as a Falcon demo's DSP replay routine does. The DSP is reset and
; bootstrapped as by Dsp_ExecBoot (PSG port A bit 4, then 512 words through
; TXH/TXM/TXL); its program sets port C to the SSI, the SSI to 16-bit
; words, 2 words a frame, network mode, transmitter on, and then writes a
; sawtooth to TX on every TDE: each word $0008 more than the one before
; (A1 is moved, not A, so the ramp wraps without the limiter). The 68030
; connects the crossbar as Devconnect(DSPXMIT, DAC, CLK25M, 1, NO_SHAKE)
; and Soundcmd do: DSP transmit on the 25 MHz clock without handshake, the
; DAC's source the DSP transmitter, divider 1 (49170 Hz), the codec's adder
; from the crossbar only, no attenuation.
; The bench checks the audio (--audio-ramp): see sim/tb/sim_main.cpp.
; $FFC: $D0E0600D once the crossbar is set.
;   vasmm68k_mot -Fbin -quiet -o dspsnd.rom dspsnd.s
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

; the DSP program, at P:$0000
prog:	dc.l	$08f4ac,$004100		; $00 movep #$4100,x:$ffec  CRA: 16 bit, 2 words a frame
	dc.l	$08f4ad,$001800		; $02 movep #$1800,x:$ffed  CRB: TE, network mode
	dc.l	$08f4a1,$0001f8		; $04 movep #$01f8,x:$ffe1  PCC: port C pins 3-8 the SSI
	dc.l	$44f400,$000800		; $06 move #$000800,x0      the step: $0008 in the 16-bit word
	dc.l	$200013			; $08 clr a
	dc.l	$0aae86,$000009		; $09 jclr #6,x:$ffee,$09   wait TDE
	dc.l	$08cc2f			; $0b movep a1,x:$ffef      TX (A1: register $0C)
	dc.l	$200040			; $0c add x0,a
	dc.l	$0c0009			; $0d jmp $09
progend:
