# `.SET32`, `.SET64`, and `.SET85`

The SetNN family contains three NextZXOS dot commands that select a text
display width and clear the screen:

| Command | Result |
| --- | --- |
| `.SET32` | Standard 32-column Spectrum display |
| `.SET64` | More compact 64-column display |
| `.SET85` | Dense 85-column display |

All three commands have been built and tested successfully under NextZXOS.

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

## Current implementation

The three sources are:

- [`src/set32.asm`](../src/set32.asm)
- [`src/set64.asm`](../src/set64.asm)
- [`src/set85.asm`](../src/set85.asm)

They are small NextForge/ZNC sources which differ only in the requested column
count. Each binary is 51 bytes and executes the equivalent of one tokenised
NextBASIC statement:

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
ld   bc,.len
rst  $18
dw   $0030          ; BC_SPACES
```

The token stream is copied into that allocation with `LDIR`. After the BASIC
command has executed, the workspace is released:

```asm
ld   hl,(.addr_s)
ld   bc,.len
rst  $18
dw   $19E8          ; RECLAIM_2
```

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
ld   de,IDE_BASIC
ld   c,0
exx
ld   hl,(.addr_s)
exx
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

The present 51-byte commands rely on the normal NextZXOS command-line
environment to provide those conditions. They do not contain the explicit
paging save-and-restore logic explored in an older, larger implementation.
That distinction matters if the commands are later invoked from a different
environment or refactored to do more work.

## Error handling

The current compact sources do not inspect the result of `BC_SPACES` or
`IDE_BASIC`, nor do they translate an error into the dot-command return
convention. They reclaim the workspace and return.

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
assembly files and built with NextForge on the Spectrum Next. Their
`;; make dot` directive and source syntax are not accepted unchanged by the
repository's SJAsmPlus 1.24.0 build path.

For that reason, `build.ps1` currently builds `.CDN` only. Porting SetNN to
SJAsmPlus should be treated as a separate change: preserve the tested 51-byte
behaviour, establish reproducible raw binaries at origin `$2000`, and compare
the new artifacts under NextZXOS before replacing the existing commands.
