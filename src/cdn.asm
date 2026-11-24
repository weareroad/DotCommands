; CDN - change directory and print its canonical long-filename path.
;
; Usage:
;   .cdn                 print the current directory
;   .cdn ..              change to the parent and print the result
;   .cdn fred            change to fred and print the result
;   .cdn "My Games"      quoted paths may contain spaces or ':'
;
; Dot-command entry:
;   HL = argument address, or 0 when no argument was supplied
;   BC = complete command line address (unused)
;
; Dot-command exit:
;   carry clear = success
;   carry set, A = standard esxDOS error

                org     $2000

ESX_F_GETCWD    equ     $a8
ESX_F_CHDIR     equ     $a9
ESX_F_OPENDIR   equ     $a3
ESX_F_READDIR   equ     $a4
ESX_F_CLOSE     equ     $9b

ESX_ENOENT      equ     5
ESX_EINVAL      equ     7
ESX_ENAMETOOLONG equ    21

ESX_PATHNAME_MAX equ    256     ; includes the terminating zero
PATH_CHARS_MAX  equ     ESX_PATHNAME_MAX-1
ESX_DIRENT_MAX  equ     283     ; attr + LFN + SFN + time/date/size
ESX_MODE_LFN_AND_SHORT equ $18

start:
                ld      a,h
                or      l
                jr      z,show_current_directory

                call    copy_argument
                ret     c                       ; A = parsing error

                ld      a,(argument_buffer)
                or      a
                jr      z,show_current_directory

                ; In a dot command, filesystem hooks take their normal IX
                ; pointer parameter in HL instead.
                ld      a,'*'                   ; current/default drive
                ld      hl,argument_buffer
                rst     $08
                db      ESX_F_CHDIR
                ret     c                       ; A = esxDOS error

show_current_directory:
                ; F_GETCWD returns a drive-qualified canonical path, but its
                ; components may be short FAT aliases such as ZXNEXT~1.  The
                ; expansion routine below resolves each alias to its paired
                ; long filename by enumerating the containing directory.
                ld      a,$ff
                ld      de,current_filespec
                ld      hl,short_path
                rst     $08
                db      ESX_F_GETCWD
                ret     c                       ; A = esxDOS error

                call    expand_long_path
                ret     c

                ld      hl,long_path
print_path:
                ld      a,(hl)
                or      a
                jr      z,print_newline
                rst     $10
                inc     hl
                jr      print_path

print_newline:
                ld      a,$0d
                rst     $10
                or      a                       ; carry clear = success
                ret

; Expand the short canonical path in short_path into a drive-qualified LFN
; path in long_path.  For every component, F_OPENDIR mode $18 makes F_READDIR
; return the LFN followed by its corresponding short name.  Matching the short
; component therefore gives us the exact on-disk long spelling.
;
; Returns carry clear on success.  On failure, returns carry set with A holding
; a standard esxDOS error code.
expand_long_path:
                ld      hl,short_path
                ld      de,long_path

                ; A canonical path begins with a drive prefix such as C:.
                ld      a,(hl)
                or      a
                jp      z,invalid_argument
                ld      (de),a
                inc     de
                inc     hl
                ld      a,(hl)
                cp      ':'
                jp      nz,invalid_argument
                ld      (de),a
                inc     de
                inc     hl
                ld      a,'\'
                ld      (de),a
                inc     de
                xor     a
                ld      (de),a

                ld      (long_end),de
                ld      (short_cursor),hl
                ld      a,PATH_CHARS_MAX-3
                ld      (long_remaining),a
                xor     a
                ld      (component_count),a

expand_next_component:
                ld      hl,(short_cursor)
                call    skip_path_separators
                ld      a,(hl)
                or      a
                ret     z

                call    copy_short_component
                ret     c
                ld      (short_cursor),hl

                ; Open the already-expanded parent directory.  The drive in
                ; long_path overrides the default-drive selector in A.
                ld      a,'*'
                ld      b,ESX_MODE_LFN_AND_SHORT
                ld      c,0
                ld      hl,long_path
                rst     $08
                db      ESX_F_OPENDIR
                ret     c
                ld      (directory_handle),a

find_component_entry:
                ld      a,(directory_handle)
                ld      hl,dirent_buffer
                rst     $08
                db      ESX_F_READDIR
                jr      c,directory_read_error
                or      a
                jr      z,component_not_found

                ; The entry starts with attributes, then a zero-terminated LFN
                ; and a zero-terminated short name.
                ld      hl,dirent_buffer+1
find_short_name:
                ld      a,(hl)
                inc     hl
                or      a
                jr      nz,find_short_name

                ld      de,component_buffer
                call    strings_equal_ci
                jr      nz,find_component_entry

                ld      a,(directory_handle)
                rst     $08
                db      ESX_F_CLOSE
                ret     c

                ld      hl,dirent_buffer+1
                call    append_long_component
                ret     c
                jr      expand_next_component

directory_read_error:
                ld      (pending_error),a
                ld      a,(directory_handle)
                rst     $08
                db      ESX_F_CLOSE
                ld      a,(pending_error)
                scf
                ret

component_not_found:
                ld      a,(directory_handle)
                rst     $08
                db      ESX_F_CLOSE
                ret     c
                ld      a,ESX_ENOENT
                scf
                ret

; Advance HL over either slash style used by NextZXOS paths.
skip_path_separators:
                ld      a,(hl)
                cp      '/'
                jr      z,skip_one_separator
                cp      '\'
                ret     nz
skip_one_separator:
                inc     hl
                jr      skip_path_separators

; Copy one short-name component from (HL) to component_buffer.  Return with HL
; at the following separator or terminator.
copy_short_component:
                ld      de,component_buffer
                ld      c,12
copy_short_character:
                ld      a,(hl)
                or      a
                jr      z,short_component_done
                cp      '/'
                jr      z,short_component_done
                cp      '\'
                jr      z,short_component_done

                ld      b,a
                ld      a,c
                or      a
                jp      z,path_too_long
                ld      a,b
                ld      (de),a
                inc     de
                inc     hl
                dec     c
                jr      copy_short_character

short_component_done:
                xor     a
                ld      (de),a
                ret

; Compare zero-terminated strings at HL and DE without ASCII case sensitivity.
; Returns Z for equal and NZ for different.
strings_equal_ci:
                ld      a,(de)
                call    uppercase_ascii
                ld      b,a
                ld      a,(hl)
                call    uppercase_ascii
                cp      b
                ret     nz
                or      a
                ret     z
                inc     hl
                inc     de
                jr      strings_equal_ci

uppercase_ascii:
                cp      'a'
                ret     c
                cp      'z'+1
                ret     nc
                sub     'a'-'A'
                ret

; Append the zero-terminated LFN at HL to long_path.  Root already ends in a
; backslash; later components receive one separator before their name.
append_long_component:
                ld      de,(long_end)
                ld      a,(component_count)
                or      a
                jr      z,append_long_name
                ld      a,'\'
                call    append_long_character
                ret     c

append_long_name:
                ld      a,(hl)
                or      a
                jr      z,long_component_done
                call    append_long_character
                ret     c
                inc     hl
                jr      append_long_name

long_component_done:
                xor     a
                ld      (de),a
                ld      (long_end),de
                ld      a,(component_count)
                inc     a
                ld      (component_count),a
                or      a                       ; clear carry
                ret

append_long_character:
                push    af
                ld      a,(long_remaining)
                or      a
                jr      z,path_too_long_stacked
                dec     a
                ld      (long_remaining),a
                pop     af
                ld      (de),a
                inc     de
                or      a                       ; clear carry
                ret

; Copy the dot-command argument to path_buffer and add a zero terminator.
; Input may end in zero, ENTER, or an unquoted colon.  One pair of surrounding
; double quotes is removed so LFNs can contain spaces and colons.
;
; Returns carry clear on success.  On failure, returns carry set with A holding
; a standard esxDOS error code.
copy_argument:
                ld      de,argument_buffer
                ld      bc,PATH_CHARS_MAX

skip_leading_spaces:
                ld      a,(hl)
                cp      ' '
                jr      nz,argument_start
                inc     hl
                jr      skip_leading_spaces

argument_start:
                cp      '"'
                jr      z,copy_quoted_argument

                ld      (last_non_space),de

copy_unquoted_argument:
                ld      a,(hl)
                or      a
                jr      z,finish_unquoted_argument
                cp      $0d
                jr      z,finish_unquoted_argument
                cp      ':'
                jr      z,finish_unquoted_argument

                call    copy_character
                ret     c

                cp      ' '
                jr      z,unquoted_character_done
                ld      (last_non_space),de
unquoted_character_done:
                inc     hl
                jr      copy_unquoted_argument

finish_unquoted_argument:
                ; Discard spaces immediately before the command terminator.
                ld      de,(last_non_space)
                xor     a
                ld      (de),a
                ret

copy_quoted_argument:
                inc     hl                      ; omit opening quote
copy_quoted_character:
                ld      a,(hl)
                or      a
                jr      z,invalid_argument      ; missing closing quote
                cp      $0d
                jr      z,invalid_argument
                cp      '"'
                jr      z,quoted_argument_done

                call    copy_character
                ret     c
                inc     hl
                jr      copy_quoted_character

quoted_argument_done:
                inc     hl                      ; omit closing quote
skip_trailing_spaces:
                ld      a,(hl)
                cp      ' '
                jr      nz,check_quoted_terminator
                inc     hl
                jr      skip_trailing_spaces

check_quoted_terminator:
                or      a
                jr      z,finish_quoted_argument
                cp      $0d
                jr      z,finish_quoted_argument
                cp      ':'
                jr      nz,invalid_argument

finish_quoted_argument:
                xor     a
                ld      (de),a
                ret

; Copy A to (DE), enforcing the maximum path length.  A is preserved so the
; caller can still decide whether the copied character was a space.
copy_character:
                push    af
                ld      a,b
                or      c
                jr      z,path_too_long_stacked
                pop     af
                ld      (de),a
                inc     de
                dec     bc
                or      a                       ; clear carry
                ret

path_too_long_stacked:
                pop     af
path_too_long:
                ld      a,ESX_ENAMETOOLONG
                scf
                ret

invalid_argument:
                ld      a,ESX_EINVAL
                scf
                ret

current_filespec:
                db      '.',0

last_non_space: dw      0
short_cursor:   dw      0
long_end:       dw      0
directory_handle: db   0
pending_error:  db      0
component_count: db    0
long_remaining: db     0

component_buffer:
                defs    13,0

argument_buffer:
                defs    ESX_PATHNAME_MAX,0

short_path:
                defs    ESX_PATHNAME_MAX,0

long_path:
                defs    ESX_PATHNAME_MAX,0

dirent_buffer:
                defs    ESX_DIRENT_MAX,0

                assert  $ <= $4000
