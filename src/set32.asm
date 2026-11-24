; SET32 - select the 32-column display and clear the screen.

    org $2000
MAKE_BC_SPACES      equ $0030
IDE_BASIC           equ $01c0
M_P3DOS             equ $94
CALCSTACK_SPACE     equ 40

start:
    IFNDEF REFERENCE_BASELINE
    ld a,h
    or l
    jr z,.set_mode

.skip_leading_spaces:
    ld a,(hl)
    cp ' '
    jr nz,.check_dash
    inc hl
    jr .skip_leading_spaces

.check_dash:
    cp '-'
    jr nz,.set_mode
    inc hl
    ld a,(hl)
    cp '?'
    jr z,.check_help_end
    and $df
    cp 'H'
    jr nz,.set_mode

.check_help_end:
    inc hl
.skip_trailing_spaces:
    ld a,(hl)
    cp ' '
    jr nz,.check_help_terminator
    inc hl
    jr .skip_trailing_spaces

.check_help_terminator:
    or a
    jr z,.show_help
    cp $0d
    jr z,.show_help
    cp ':'
    jr nz,.set_mode

.show_help:
    ld hl,.help_text
.print_help:
    ld a,(hl)
    or a
    ret z
    rst $10
    inc hl
    jr .print_help
    ENDIF

.set_mode:
    ; Allocate token space above 40 bytes reserved for the calculator stack.
    ld bc,.len+CALCSTACK_SPACE
    rst $18
    dw MAKE_BC_SPACES
    add de,CALCSTACK_SPACE

    ; Copy the tokens and retain their address for IDE_BASIC.
    push de
    ld hl,.toks
    ld bc,.len
    ldir
    pop hl

    ; Execute the tokenized BASIC code. IDE_BASIC reclaims the workspace.
    exx
    ld de,IDE_BASIC
    ld c,0          ; Page in BANK 0
    rst $08
    db M_P3DOS
    ret

.toks db $a3,$c2,$25,"32",":",$fb,$0d ; SPECTRUM CHR$ %32:CLS
.len equ $-.toks

    IFNDEF REFERENCE_BASELINE
.help_text:
    db "v0.1 - we.are.road",$0d,$0d
    db "set display mode to 32 chars",$0d,0
    ENDIF
