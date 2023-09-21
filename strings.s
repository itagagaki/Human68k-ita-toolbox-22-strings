* strings - extract strings from bynary files
*
* Itagaki Fumihiko 26-Feb-93  Create.
* 1.0
*
* Usage: strings [-aosuqv] [-<最小文字数>] [--] [<ファイル>] ...

.include doscall.h
.include chrcode.h

.xref DecodeHUPAIR
.xref issjis
.xref isdigit
.xref atou
.xref utoa
.xref strlen
.xref strfor1
.xref printfi
.xref strip_excessive_slashes

STACKSIZE	equ	2048

INPBUF_SIZE	equ	8192				*  64以上であること
OUTBUF_SIZE	equ	8192

DEFAULT_COUNT	equ	4

FLAG_a		equ	0	*  -a
FLAG_o		equ	1	*  -o
FLAG_s		equ	2	*  -s
FLAG_u		equ	3	*  -u
FLAG_q		equ	4	*  -q
FLAG_v		equ	5	*  -v

.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack_bottom(pc),a7		*  A7 := スタックの底
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.l	#-1,stdin
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		moveq	#0,d6				*  D6.W : エラー・コード
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d5				*  D5.B : フラグ
		move.l	#DEFAULT_COUNT,count
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		tst.b	1(a0)
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		bsr	isdigit
		beq	decode_count

		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		moveq	#FLAG_a,d1
		cmp.b	#'a',d0
		beq	set_option

		moveq	#FLAG_o,d1
		cmp.b	#'o',d0
		beq	set_option

		cmp.b	#'s',d0
		beq	option_s_found

		cmp.b	#'u',d0
		beq	option_u_found

		cmp.b	#'q',d0
		beq	option_q_found

		cmp.b	#'v',d0
		beq	option_v_found

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

option_s_found:
		bset	#FLAG_s,d5
		bclr	#FLAG_u,d5
		bra	set_option_done

option_u_found:
		bset	#FLAG_u,d5
		bclr	#FLAG_s,d5
		bra	set_option_done

option_q_found:
		bset	#FLAG_q,d5
		bclr	#FLAG_v,d5
		bra	set_option_done

option_v_found:
		bset	#FLAG_v,d5
		bclr	#FLAG_q,d5
		bra	set_option_done

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_count:
		subq.l	#1,a0
		bsr	atou
		bne	bad_count

		tst.b	(a0)+
		bne	bad_count

		move.l	d1,count
		bne	decode_opt_loop1
bad_count:
		lea	msg_illegal_count(pc),a0
		bsr	werror_myname_and_msg
		bra	usage

decode_opt_done:
	*
	*  save_buffer を確保する
	*
		move.l	count,d0
		add.l	d0,d0
		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,save_buffer
	*
	*
	*
		move.w	#1,-(a7)			*  標準出力
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		seq	do_buffering
		bne	outbuf_ok			*  -- キャラクタ・デバイスである
	*
	*  stdoutはブロック・デバイス
	*
		*  出力バッファを確保する
		*
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,outbuf_top
		move.l	d0,outbuf_ptr
outbuf_ok:
		lea	msg_header2(pc),a1
		st	show_header
		btst	#FLAG_v,d5
		bne	do_files

		sf	show_header
		btst	#FLAG_q,d5
		bne	do_files

		cmp.l	#1,d7
		shi	show_header
do_files:
	*
	*  標準入力を切り替える
	*
		clr.w	-(a7)				*  標準入力を
		DOS	_DUP				*  複製したハンドルから入力し，
		addq.l	#2,a7
		move.l	d0,stdin
		bmi	start_do_files

		clr.w	-(a7)
		DOS	_CLOSE				*  標準入力はクローズする．
		addq.l	#2,a7				*  こうしないと ^C や ^S が効かない
start_do_files:
	*
	*  開始
	*
		tst.l	d7
		beq	do_stdin
for_file_loop:
		subq.l	#1,d7
		movea.l	a0,a3
		bsr	strfor1
		exg	a0,a3
		cmpi.b	#'-',(a0)
		bne	do_file

		tst.b	1(a0)
		bne	do_file
do_stdin:
		lea	msg_stdin(pc),a0
		move.l	stdin,d1
		bmi	open_fail

		bsr	strings_one
		bra	for_file_continue

do_file:
		bsr	strip_excessive_slashes
		clr.w	-(a7)
		move.l	a0,-(a7)
		DOS	_OPEN
		addq.l	#6,a7
		move.l	d0,d1
		bmi	open_fail

		bsr	strings_one
		move.w	d1,-(a7)
		DOS	_CLOSE
		addq.l	#2,a7
for_file_continue:
		movea.l	a3,a0
		tst.l	d7
		beq	all_done

		lea	msg_header1(pc),a1
		bra	for_file_loop

all_done:
exit_program:
		move.l	stdin,d0
		bmi	exit_program_1

		clr.w	-(a7)				*  標準入力を
		move.w	d0,-(a7)			*  元に
		DOS	_DUP2				*  戻す．
		DOS	_CLOSE				*  複製はクローズする．
exit_program_1:
		move.w	d6,-(a7)
		DOS	_EXIT2

open_fail:
		lea	msg_open_fail(pc),a2
		bra	werror_exit_2
****************************************************************
* strings_one
****************************************************************
strings_one:
		tst.b	show_header
		beq	strings_one_1

		move.l	a0,-(a7)
		movea.l	a1,a0
		bsr	puts
		movea.l	(a7),a0
		bsr	puts
		lea	msg_header3(pc),a0
		bsr	puts
		movea.l	(a7)+,a0
strings_one_1:
		clr.l	offset
		move.l	#-1,scan_size
		sf	ungetc_flag
		sf	eof

		move.l	#64,d0				*  .Xタイプファイルのヘッダの長さだけ
		bsr	read				*  読み込んで
							*  .Xタイプファイルかどうかを調べる
		btst	#FLAG_a,d5
		bne	strings_one_reset

		cmp.l	#64,d0
		blo	strings_one_reset

		cmpi.w	#'HU',(a2)
		bne	strings_one_reset

		*  .Xタイプファイル -- data section だけをスキャンする
		move.l	$10(a2),scan_size
		move.l	d0,offset
		move.l	$0c(a2),d0
		add.l	d0,offset
		bsr	yomisute
strings_one_reset:
		move.l	count,d2			*  D2.L : letter count
		movea.l	save_buffer,a1
		move.l	offset,save_offset
strings_one_loop:
		bsr	get_letter
		bmi	strings_one_done
		bne	strings_one_reset

		move.w	d0,(a1)+
		subq.l	#1,d2
		bne	strings_one_loop

		btst	#FLAG_o,d5
		beq	strings_one_output_1

		movem.l	d1-d4/a0-a2,-(a7)
		move.l	save_offset,d0
		moveq	#0,d1				*  右詰め
		moveq	#' ',d2				*  pad文字
		moveq	#7,d3				*  最小フィールド幅
		moveq	#1,d4				*  最小変換桁数
		lea	utoa(pc),a0			*  unsinged -> ascii decimal
		lea	putc(pc),a1			*  output function
		suba.l	a2,a2				*  prefix string
		bsr	printfi
		movem.l	(a7)+,d1-d4/a0-a2
		moveq	#' ',d0
		bsr	putc
strings_one_output_1:
		movea.l	save_buffer,a1
		move.l	count,d2
strings_one_output_loop1:
		move.w	(a1)+,d0
		bsr	put_letter
		subq.l	#1,d2
		bne	strings_one_output_loop1
strings_one_output_loop2:
		bsr	get_letter
		bne	strings_one_output_done

		bsr	put_letter
		bra	strings_one_output_loop2

strings_one_output_done:
		moveq	#CR,d0
		bsr	putc
		moveq	#LF,d0
		bsr	putc
		bra	strings_one_reset

strings_one_done:
flush_outbuf:
		move.l	d0,-(a7)
		tst.b	do_buffering
		beq	flush_done

		move.l	#OUTBUF_SIZE,d0
		sub.l	outbuf_free,d0
		beq	flush_done

		move.l	d0,-(a7)
		move.l	outbuf_top,-(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	-4(a7),d0
		blo	write_fail

		move.l	outbuf_top,outbuf_ptr
		move.l	#OUTBUF_SIZE,outbuf_free
flush_done:
		move.l	(a7)+,d0
		rts

read_fail:
		bsr	flush_outbuf
		lea	msg_read_fail(pc),a2
werror_exit_2:
		bsr	werror_myname_and_msg
		movea.l	a2,a0
		bsr	werror
		moveq	#2,d6
		bra	exit_program
*****************************************************************
get_letter:
		movem.l	d2,-(a7)
		tst.b	ungetc_flag
		beq	get_letter_1

		moveq	#0,d0
		move.b	ungetc_char,d0
		sf	ungetc_flag
		bra	get_letter_2

get_letter_1:
		bsr	getc
		bmi	get_letter_return
get_letter_2:
		addq.l	#1,offset
		cmp.b	#HT,d0
		beq	get_letter_true

		cmp.b	#$20,d0
		blo	get_letter_false

		cmp.b	#$7e,d0
		bls	get_letter_true

		btst	#FLAG_s,d5
		bne	get_letter_sjis

		btst	#FLAG_u,d5
		beq	get_letter_false
get_letter_euc:
		cmp.b	#$a1,d0
		blo	get_letter_false

		cmp.b	#$fe,d0
		bhi	get_letter_false

		move.b	d0,d2
		bsr	getc
		exg	d0,d2
		bmi	get_letter_false

		cmp.b	#$a1,d2
		blo	get_letter_2_false

		cmp.b	#$fe,d2
		bls	get_letter_2_true
get_letter_2_false:
		move.b	d2,ungetc_char
		st	ungetc_flag
get_letter_false:
		moveq	#1,d2				*  N:=0, Z:=0
		bra	get_letter_return

get_letter_sjis:
		cmp.b	#$81,d0
		blo	get_letter_false

		cmp.b	#$9f,d0
		bls	get_letter_sjis_2

		cmp.b	#$a1,d0
		blo	get_letter_false

		cmp.b	#$df,d0
		bls	get_letter_true			*  1バイトカナ

		cmp.b	#$ef,d0
		bhi	get_letter_false
get_letter_sjis_2:
		move.b	d0,d2
		bsr	getc
		exg	d0,d2
		cmp.b	#$40,d2
		blo	get_letter_2_false

		cmp.b	#$7e,d2
		bls	get_letter_2_true

		cmp.b	#$80,d2
		blo	get_letter_2_false

		cmp.b	#$fc,d0
		bhi	get_letter_2_false
get_letter_2_true:
		lsl.w	#8,d0
		move.b	d2,d0
		addq.l	#1,offset
get_letter_true:
		cmp.b	d0,d0
get_letter_return:
		movem.l	(a7)+,d2
		rts
*****************************************************************
getc:
		sub.l	#1,scan_size
		bcs	getc_eof

		tst.l	byte_remain
		bne	getc_1

		move.l	#INPBUF_SIZE,d0
		bsr	read
		beq	getc_eof
getc_1:
		moveq	#0,d0
		move.b	(a2)+,d0
		sub.l	#1,byte_remain
		cmp.b	d0,d0
		rts

getc_eof:
		clr.l	scan_size
		clr.l	byte_remain
		st	eof
		moveq	#-1,d0
		rts
*****************************************************************
read:
		lea	inpbuf(pc),a2
		clr.l	byte_remain
		tst.b	eof
		bne	read_done

		move.l	d0,-(a7)
		move.l	a2,-(a7)
		move.w	d1,-(a7)
		DOS	_READ
		lea	10(a7),a7
		move.l	d0,byte_remain
		bmi	read_fail
read_done:
		move.l	byte_remain,d0
		rts
*****************************************************************
yomisute:
		movem.l	d2/a2,-(a7)
		move.l	d0,d2
yomisute_loop:
		move.l	#INPBUF_SIZE,d0
		cmp.l	d2,d0
		bls	do_yomisute_1

		move.l	d2,d0
do_yomisute_1:
		bsr	read
		beq	yomisute_eof

		sub.l	d0,d2
		bne	yomisute_loop
yomisute_done:
		movem.l	(a7)+,d2/a2
		clr.l	byte_remain
		rts

yomisute_eof:
		st	eof
		bra	yomisute_done
*****************************************************************
put_letter:
		move.w	d0,-(a7)
		lsr.w	#8,d0
		beq	put_letter_1

		bsr	putc
put_letter_1:
		move.w	(a7)+,d0
putc:
		tst.b	do_buffering
		bne	putc_do_buffering

		move.l	d0,-(a7)

		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		cmp.l	#1,d0
		bne	write_fail

		move.l	(a7)+,d0
		bra	putc_done

putc_do_buffering:
		tst.l	outbuf_free
		bne	putc_do_buffering_1

		bsr	flush_outbuf
putc_do_buffering_1:
		move.l	a0,-(a7)
		movea.l	outbuf_ptr,a0
		move.b	d0,(a0)+
		move.l	a0,outbuf_ptr
		movea.l	(a7)+,a0
		subq.l	#1,outbuf_free
putc_done:
		rts
*****************************************************************
puts:
		movem.l	d0/a0,-(a7)
puts_loop:
		move.b	(a0)+,d0
		beq	puts_done

		bsr	putc
		bra	puts_loop
puts_done:
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
write_fail:
		lea	msg_write_fail(pc),a0
		bsr	werror
		bra	exit_3
*****************************************************************
insufficient_memory:
		lea	msg_no_memory(pc),a0
		bsr	werror_myname_and_msg
exit_3:
		moveq	#3,d6
		bra	exit_program
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## strings 1.0 ##  Copyright(C)1993 by Itagaki Fumihiko',0

msg_myname:		dc.b	'strings: ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_open_fail:		dc.b	': オープンできません',CR,LF,0
msg_read_fail:		dc.b	': 入力エラー',CR,LF,0
msg_write_fail:		dc.b	'strings: 出力エラー',CR,LF,0
msg_stdin:		dc.b	'- 標準入力 -',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_illegal_count:	dc.b	'最小文字数の指定が不正です',0
msg_header1:		dc.b	CR,LF
msg_header2:		dc.b	'==> ',0
msg_header3:		dc.b	' <=='
msg_newline:		dc.b	CR,LF,0
msg_usage:		dc.b	CR,LF,'使用法:  strings [-aosuqv] [-<最小文字数>] [--] [<ファイル>] ...',CR,LF,0
*****************************************************************
.bss

.even
stdin:			ds.l	1
outbuf_top:		ds.l	1
outbuf_ptr:		ds.l	1
outbuf_free:		ds.l	1
save_buffer:		ds.l	1
count:			ds.l	1
offset:			ds.l	1
save_offset:		ds.l	1
byte_remain:		ds.l	1
scan_size:		ds.l	1
show_header:		ds.b	1
do_buffering:		ds.b	1
eof:			ds.b	1
ungetc_flag:		ds.b	1
ungetc_char:		ds.b	1
.even
inpbuf:			ds.b	INPBUF_SIZE

		ds.b	STACKSIZE
.even
stack_bottom:
*****************************************************************

.end start
