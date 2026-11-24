; AUTO folder program for the disk tests (sim/run_tests.sh): prints a line
; and writes WROTE.TXT on the boot drive through GEMDOS, then returns.
; vasmm68k_mot -Ftos -o WRTEST.PRG wrtest.s
; SPDX-License-Identifier: GPL-2.0-or-later
	pea	msg(pc)
	move.w	#9,-(sp)		; Cconws
	trap	#1
	addq.l	#6,sp

	move.w	#0,-(sp)		; Fcreate(name, 0)
	pea	fname(pc)
	move.w	#$3c,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi.s	.fail
	move.w	d0,d7

	pea	text(pc)		; Fwrite(handle, len, buf)
	move.l	#textend-text,-(sp)
	move.w	d7,-(sp)
	move.w	#$40,-(sp)
	trap	#1
	lea	12(sp),sp

	move.w	d7,-(sp)		; Fclose
	move.w	#$3e,-(sp)
	trap	#1
	addq.l	#4,sp

	pea	okmsg(pc)
	bra.s	.out
.fail:
	pea	failmsg(pc)
.out:
	move.w	#9,-(sp)
	trap	#1
	addq.l	#6,sp
	clr.w	-(sp)			; Pterm0
	trap	#1

msg:	dc.b	"WRTEST: Falcon on Game Bub",13,10,0
okmsg:	dc.b	"WRTEST: written",13,10,0
failmsg:dc.b	"WRTEST: Fcreate failed",13,10,0
fname:	dc.b	"\WROTE.TXT",0
	even
text:	dc.b	"Written by the Falcon core on the Game Bub",13,10
	dcb.b	1000,$41
	dc.b	13,10,"end",13,10
textend:
