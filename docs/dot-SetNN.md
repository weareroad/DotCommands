# `.SET32`, `.SET64`, and `.SET85`

The SetNN family contains three NextZXOS dot commands that select a text
display width and clear the screen:

| Command | Result |
| --- | --- |
| `.SET32` | Standard 32-column Spectrum display |
| `.SET64` | More compact 64-column display |
| `.SET85` | Dense 85-column display |

The optimized mode-setting commands and the help behavior were tested
separately under NextZXOS in CSpect. Their merged 145-byte build requires a
final regression after rebasing onto the optimized upstream core.

## Using the commands

Copy the extensionless command binaries from `dot/` into `C:/DOT/` on the
Next SD card. At the NextBASIC command line, enter the required command:

```text
.set32
.set64
.set85
```

Changing mode also performs a `CLS`, so the new display geometry is visible
immediately and the screen contents are cleared.

Use `-h`, `-H`, or `-?` for brief help without changing mode or clearing the
screen. For example, `.set32 -h` prints:

```text
v0.1 - we.are.road

set display mode to 32 chars
```

The final line uses `64` or `85` for the other commands. Only those exact
options are treated as help; other arguments preserve the historical behavior.

## Current implementation

The three sources are:

- [`src/set32.asm`](../src/set32.asm)
- [`src/set64.asm`](../src/set64.asm)
- [`src/set85.asm`](../src/set85.asm)

They are small SJAsmPlus sources, ported mechanically from the tested
NextForge/ZNC versions, which differ only in the requested column count. The
optimized mechanical ports were 37 bytes. The current 145-byte binaries add
exact help option recognition and text before that optimized mode-setting
path, which executes the equivalent of one tokenised NextBASIC statement:

```basic
SPECTRUM CHR$ %32 : CLS
SPECTRUM CHR$ %64 : CLS
SPECTRUM CHR$ %85 : CLS
```

The current token streams are:

```text
A3 C2 25 33 32 3A FB 0D    SPECTRUM CHR$ %32:CLS
A3 C2 25 36 34 3A FB 0D    SPECTRUM CHR$ %64:CLS
A3 C2 25 38 35 3A FB 0D    SPECTRUM CHR$ %85:CLS
```

The significant tokens are `$A3` for `SPECTRUM`, `$C2` for `CHR$`, `$25` for
the integer-value prefix `%`, `$FB` for `CLS`, and `$0D` for ENTER.

## Why execute NextBASIC?

The display hardware can be influenced directly through I/O port `$FF`, but a
port write alone does not update all of NextZXOS's software state. The
operating system also tracks the active renderer, cursor, windows, and editor
geometry. In addition, 64- and 85-column modes use the same 512-pixel-wide
hardware mode but different character widths.

Executing the same `SPECTRUM CHR$` command that a user would enter lets
NextZXOS perform the complete transition and keeps its software state aligned
with the hardware.

## Allocating the command buffer

A dot command is loaded into DivMMC memory at `$2000`. The NextBASIC API needs
its command text in ordinary Spectrum RAM, so each SetNN command asks the 48K
BASIC ROM to allocate a workspace:

```asm
ld   bc,.len+40
rst  $18
dw   $0030          ; BC_SPACES
add  de,40           ; reserve calculator-stack space below the tokens
```

The token stream is copied into that allocation with `LDIR`. `IDE_BASIC`
reclaims the workspace while executing the line, so the optimized commands do
not save an allocation pointer or call `RECLAIM_2` explicitly.

Using BASIC workspace also keeps the machine stack in the range expected by
the ROM and NextZXOS APIs. Earlier experiments which moved the stack below
`STKEND` violated the `M_P3DOS` contract and were rejected.

## Calling `IDE_BASIC`

The relevant NextZXOS entry points are:

```text
M_P3DOS   = $94    esxDOS bridge to NextZXOS/+3DOS APIs
IDE_BASIC = $01C0  execute a tokenised BASIC command line
```

`M_P3DOS` takes the wrapped call ID in `DE` and the RAM bank required at
`$C000` in `C`. Arguments intended for the wrapped call's `BC`, `DE`, and `HL`
are supplied through the alternate register set. SetNN therefore places the
allocated command address in `HL'` and requests RAM bank 0:

```asm
pop  hl                   ; allocated token address
exx                        ; token address becomes HL'
ld   de,IDE_BASIC
ld   c,0
rst  $08
db   M_P3DOS
```

`IDE_BASIC` expects tokenised input terminated by ENTER, not an ASCII BASIC
source line.

## Paging and API constraints

The documented `IDE_BASIC` environment uses the normal
`ROM2/RAM5/RAM2/RAM0` arrangement, with RAM bank 0 at `$C000`. Its wider API
contract also requires no `$DFFD` paging, the normal lower half of RAM bank 5
in MMU2, pointer parameters in ordinary RAM, and the stack between `STKEND`
and `RAMTOP` for this call.

The present compact commands rely on the normal NextZXOS command-line
environment to provide those conditions. They do not contain the explicit
paging save-and-restore logic explored in an older, larger implementation.
That distinction matters if the commands are later invoked from a different
environment or refactored to do more work.

## Error handling

The current compact sources do not inspect the result of `BC_SPACES` or
`IDE_BASIC`, nor do they translate an error into the dot-command return
convention. `IDE_BASIC` reclaims the workspace and the commands return.

Earlier investigation found that the tested NextZXOS system returned carry
clear from the `M_P3DOS` call even when `IDE_BASIC` had executed successfully,
despite documentation describing the opposite sense for the bridge result.
The larger experimental implementation used the BASIC `ERR_NR` system
variable as its completion check instead.

This finding should be re-tested before adding error reporting. A future
implementation must not assume that an unverified carry flag is authoritative
for `IDE_BASIC` on every NextZXOS version.

## Building and history

The commands were originally built with ZNC and later edited into standalone
assembly files and built with NextForge on the Spectrum Next. The repository
sources have now been adjusted to standard SJAsmPlus syntax: hexadecimal
literals use `$`, the `org` directive is indented so it is not parsed as a
label, the NextForge `;; make dot` directive has become an ordinary source
comment, and SJAsmPlus is run with `--zxnext` for the Z80N `ADD DE,nn`
instruction. These are source-level changes only and do not alter emitted
bytes.

Build all commands from the repository root with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build.ps1 -Clean
```

Build just the SetNN family with `-Command setnn`, or select one with
`-Command set32`, `set64`, or `set85`. Outputs retain their historical names:
`dot/set32`, `dot/set64`, and `dot/set85`.

### Byte-for-byte baseline verification

Run the protected comparison build with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build.ps1 `
  -Command setnn -VerifySetNNReference
```

This protected mode defines `REFERENCE_BASELINE`, omitting only the help
dispatcher and strings. Each optimized core is assembled to a temporary file
and checked without replacing the normal help-enabled artifact. SJAsmPlus
1.24.0 reproduces all three optimized NextForge/ZNC binaries exactly:

| Command | Bytes | Reference SHA-256 |
| --- | ---: | --- |
| `.SET32` | 37 | `917c7975781993682ab896eb6c70624a15aba786a7965a94abceeb5790424445` |
| `.SET64` | 37 | `a877272fa3e64f88e7d5551f20433aa06e2978c7e4f2b0db47dd0ad6f3a81078` |
| `.SET85` | 37 | `ae948fbeb8048a2ae708fc949993e480ac62cb120214ddd5829829badc3aa57a` |

This keeps the SJAsmPlus port continuously checked against its byte-identical
37-byte baseline while allowing the normal help-enabled build to evolve.
