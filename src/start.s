	bits	16
	org	0x7C00
_start:
	; Init
	mov	ax,cs
	mov	ss,ax
	mov	ds,ax
	mov	es,ax
	mov	sp,0x4000
	; Load Second Sector
	mov	ax, 0x0208
	mov	cx, 0x0002
	xor	dh, dh
	mov	bx, 0x7E00
	int	0x13
	jc	$
	; Set P to a print function
	mov	word[_variables + 160], _runtime_print
	; Start
	mov	si, _ready
	call	_puts
_start.m3:
	mov	di, _buffer
	mov	cx, 255
_start.m0:
	call	_getchar
	cmp	al, 13
	je	_start.m2
	stosb
	loop	_start.m0
_start.m2:
	mov	byte[_buffer_len], 255
	sub	byte[_buffer_len], cl
	mov	al, 10
	call	_putchar
_start.m1:
        pusha
	mov	di, word[_jit_current]
	mov	byte[di], 0xC3
	mov	si, _exec
	mov	di, _buffer_len
	call	_cmp
	jc	_start.m4
	call	_jit
        call    _print_hex
        mov     si, _nl
        call    _puts
	mov	si, _ready
	call	_puts
	mov	word[_jit_current], _jit
        popa
        jmp     _start.m3
_start.m4:
	mov	di, _buffer_len
	call	_compile_line
	jmp	_start.m3
_getchar:
	xor	ax,ax
	int	16H
	cmp	al, '@'
	je	.at
        cmp     al, '!'
        jne     _putchar
        mov     al, 24
        jmp     _putchar
.at:
	mov	al, 26
_putchar:
	mov	ah,0EH
	int	10H
	ret
_puts:	;; SI
	xor	ch,ch
	lodsb
	mov	cl, al
	mov	ah, 0EH
_puts.m0:
	lodsb
	int	10H
	loop	_puts.m0
	ret
_cmp:
	push	di
	lodsb
	mov	cl, al
	xchg	si, di
	lodsb
	xchg	si, di
	cmp	al, cl
	jne	_cmp.m0
	mov	cl, al
	repe	cmpsb
	jne	_cmp.m0
	pop	di
	clc
	ret
_cmp.m0:
	pop	di
	stc
	ret
_empty:
	times	510 - ($ - $$) nop
_magic:
	dw	0xaa55
_endof_block0:
_compile_line:
        mov     si, di
        lodsb
        mov     cl, al
        xor     ch, ch
        call    _parse_expression
	ret
_parse_expression:
        ; Parse a single expression at SI, updates SI and CX
        ; Skip leading spaces
.skip_spaces:
        cmp     cx, 0
        je      .done
        mov     al, [si]
        cmp     al, ' '
        jne     .check_token
        inc     si
        dec     cx
        jmp     .skip_spaces
.check_token:
        mov     al, [si]
        cmp     al, '('
        je      _parse_list
	cmp	al, '+'
	je	_parse_add
	cmp	al, '-'
	je	_parse_sub
	cmp	al, 27
	je	_parse_return
	cmp	al, 26
        je	_parse_call
	cmp	al, '='
	je	_parse_assign
        cmp     al, '$'
        je      _parse_here
        cmp     al, 24
        je      _parse_goto
        cmp     al, '0'
        jl      .identifier
        cmp     al, '9'
        jg      .identifier
        jmp     _parse_number
.identifier:
        inc     si
        dec     cx
        xor     ah, ah
        shl     ax, 1
        add     ax, _variables
        push    di
        push    ax
        mov     di, [_jit_current]
        mov     al, 0xA1        ; MOV AX, [addr]
        stosb
        pop     bx
        mov     ax, bx
        stosw
        mov     al, 0x50        ; PUSH AX
        stosb
        mov     [_jit_current], di
        pop     di
.done:
        ret
_parse_number:
	push	bx
	push	dx
	xor	ax,ax
	xor	bx,bx
.num_loop:
	mov	dx,10
        cmp     cx, 0
        je      .emit
        mov     bl, [si]
        cmp     bl, '0'
        jl      .emit
        cmp     bl, '9'
        jg      .emit
	sub	bx, '0'
	mul	dx
	add	ax,bx
	inc     si
        dec     cx
        jmp     .num_loop
.emit:
	mov	bx, ax
	push	di
	mov	di, word[_jit_current]
	mov	al, 0xB8
	stosb
	mov	ax, bx
	stosw
	mov	al, 0x50
	stosb
	mov	word[_jit_current], di
	pop	di
.done:
	pop	dx
	pop	bx
        ret
_parse_goto:
        inc     si
        dec     cx
        call    _parse_expression
        push    di
        mov     di, [_jit_current]
        mov     al, 0x5B        ; POP BX
        stosb
        mov     al, 0xFF        ; EXT opcode
        mov     ah, 0xE3        ; ModRM for JMP BX
        stosw
	mov	al, 0x50
	stosb
        mov     [_jit_current], di
        pop     di
        ret
_parse_here:
        inc     si
        dec     cx
        push    di
        mov     di, [_jit_current]
        mov     al, 0xB8
        stosb
        mov     ax, di
        add     ax, -1
        stosw
	mov	al, 0x50
	stosb
        mov     [_jit_current], di
        pop     di
        ret
_parse_call:
        inc     si              ; Skip '→'
        dec     cx
        call    _parse_expression
        push    di
        mov     di, [_jit_current]
        mov     al, 0x5B        ; POP BX
        stosb
        mov     al, 0xFF        ; EXT opcode
        mov     ah, 0xD3        ; ModRM for CALL BX
        stosw
	mov	al, 0x50
	stosb
        mov     [_jit_current], di
        pop     di
        ret
_parse_binop:
        inc     si              ; Skip the operator
        dec     cx
        call    _parse_expression  ; Parse first operand
        call    _parse_expression  ; Parse second operand
        ret
_parse_return:
	inc	si
	dec	cx
	call	_parse_expression
        push    di
        mov     di, [_jit_current]
        mov     al, 0x5A        ; POP AX
        stosb
	mov	al, 0xC3	; RET
	stosb
	mov	[_jit_current], di
	pop	di
	ret
_parse_assign:
        inc     si
        dec     cx
        lodsb
        dec     cx
        xor     ah, ah
        shl     ax, 1
        add     ax, _variables
        push    ax
        call    _parse_expression
        pop     ax
        push    di
        push    ax
        mov     di, [_jit_current]
        mov     al, 0x58
        stosb
        pop     bx
        mov     al, 0xA3
        stosb
        mov     ax, bx
        stosw
        mov     [_jit_current], di
        pop     di
        ret
_parse_add:
        call    _parse_binop
        push    di
        mov     di, [_jit_current]
        mov     al, 0x5B        ; POP BX
        stosb
        mov     al, 0x58        ; POP AX
        stosb
        mov     al, 0x01        ; ADD AX, BX
        mov     ah, 0xD8
        stosw
        mov     al, 0x50        ; PUSH AX
        stosb
        mov     [_jit_current], di
        pop     di
        ret
_parse_sub:
        call    _parse_binop
        push    di
        mov     di, [_jit_current]
        mov     al, 0x5B        ; POP BX
        stosb
        mov     al, 0x58        ; POP AX
        stosb
        mov     al, 0x29        ; SUB AX, BX
        mov     ah, 0xD8
        stosw
        mov     al, 0x50        ; PUSH AX
        stosb
        mov     [_jit_current], di
        pop     di
        ret
_parse_list:
        inc     si
        dec     cx
.list_loop:
        call    _parse_expression
.skip_spaces2:
        cmp     cx, 0
        je      .error
        mov     al, [si]
        cmp     al, ' '
        jne     .check_end
        inc     si
        dec     cx
        jmp     .skip_spaces2
.check_end:
        cmp     al, ')'
        je      .end_list
        jmp     .list_loop
.end_list:
        inc     si
        dec     cx
        ret
.error:
	mov	si, _error
	call	_puts
        ret
_runtime_print:
	mov	ah, 0EH
	mov	al, byte[_variables + 'A' * 2]
	int	10H
	ret
_skip_spaces:
        push    ax
.loop:
        cmp     cx, 0
        je      .done
        mov     al, [si]
        cmp     al, ' '
        jne     .done
        inc     si
        dec     cx
        jmp     .loop
.done:
        pop     ax
        ret
_print_hex:
        push    bx
        push    cx
        push    dx
        push    si
        mov     bx, ax
        mov     cx, 4
.hex_loop:
        rol     bx, 4
        mov     al, bl
        and     al, 0x0F
        cmp     al, 10
        jb      .digit
        add     al, 'A' - 10
        jmp     .print
.digit:
        add     al, '0'
.print:
        mov     ah, 0x0E
        int     10H
        loop    .hex_loop
        pop     si
        pop     dx
        pop     cx
        pop     bx
        ret
_data:
_nl:    db      2, 10, 13
_ready: db	7, "READY", 10, 13
_exec:	db	3, "RUN"
_error: db	3, "ERR"
_jit_current:
	dw	_jit
_variables:
	times	256*2 db 0
_buffer_len:
	db	0
_buffer:
	times	255 db 0
_jit:
