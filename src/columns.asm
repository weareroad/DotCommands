; Shared implementation for the .32, .64 and .85 NextZXOS dot commands.
;
; The including source must define WIDTH and its two visible ASCII digits.

                org     $2000

M_P3DOS         equ     $94
IDE_BASIC       equ     $01c0
ERR_NR          equ     $5c3a
BANKM           equ     $5b5c
ZX128_PORT      equ     $7ffd

start:
                ; IDE_BASIC cannot read the command from DivMMC memory at
                ; $2000. Allocate normal RAM in the BASIC workspace. Unlike
                ; moving SP, this keeps SP between STKEND and RAMTOP as
                ; required by M_P3DOS for calls using RAM bank 0.
                ld      bc,command_length
                rst     $18
                defw    $0030           ; 48K ROM BC_SPACES; DE = new space
                ld      (command_ptr),de
                ld      hl,basic_command
                ld      bc,command_length
                ldir

                ; IDE_BASIC requires RAM bank 0 at $c000 before M_P3DOS
                ; enters the ROM2/RAM5/RAM2/RAM0 configuration.
                ld      a,(BANKM)
                ld      (saved_bankm),a
                and     $f8
                ld      (BANKM),a
                ld      bc,ZX128_PORT
                out     (c),a

                ; M_P3DOS takes the wrapped call's HL in alternate HL.
                ld      hl,(command_ptr)
                exx
                ld      c,0             ; IDE_BASIC requires RAM bank 0
                ld      de,IDE_BASIC
                xor     a
                ld      (ERR_NR),a       ; sentinel: IDE_BASIC must set $ff
                rst     $08
                defb    M_P3DOS

                ; Restore paging and release the temporary BASIC workspace.
                ; Some NextZXOS versions return carry clear here even though
                ; IDE_BASIC executed successfully, so ERR_NR is authoritative.
                ld      a,(saved_bankm)
                ld      bc,ZX128_PORT
                out     (c),a
                ld      (BANKM),a

                ld      hl,(command_ptr)
                ld      bc,command_length
                rst     $18
                defw    $19e8           ; 48K ROM RECLAIM_2

                ; IDE_BASIC reports parser/runtime status through ERR_NR.
                ; $ff means that the command completed successfully.
                ld      a,(ERR_NR)
                inc     a
                jr      nz,basic_error

                or      a               ; carry clear = successful dot command
                ret

basic_error:
                ld      a,(ERR_NR)
                push    af
                ld      hl,basic_error_message
                call    print_string
                pop     af
                call    print_hex

diagnostic_done:
                ld      a,$0d
                rst     $10
                or      a               ; message printed; exit cleanly
                ret

print_string:
                ld      a,(hl)
                inc     hl
                or      a
                ret     z
                rst     $10
                jr      print_string

print_hex:
                push    af
                rrca
                rrca
                rrca
                rrca
                call    print_nibble
                pop     af

print_nibble:
                and     $0f
                add     a,'0'
                cp      '9'+1
                jr      c,print_digit
                add     a,'A'-'9'-1
print_digit:
                rst     $10
                ret

command_ptr:    defw    0
saved_bankm:    defb    0

basic_command:
                defb    $a3             ; SPECTRUM
                defb    $c2             ; CHR$
                defb    WIDTH_ASCII_1    ; visible numeric text
                defb    WIDTH_ASCII_2
                defb    $0e              ; hidden numeric-value marker
                defb    0,0,WIDTH,0,0    ; positive integer, little-endian
                defb    $0d              ; ENTER / end of command
command_end:
command_length  equ     command_end-basic_command

basic_error_message:
                defm    "IDE_BASIC ERR_NR $"
                defb    0
