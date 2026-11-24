# ZX Spectrum Next dot commands

Small utilities for NextZXOS, written in Z80/Z80N assembly or Z88DK C.
New assembly commands use SJAsmPlus; the original `SetNN` commands remain in
their tested NextForge/ZNC form for now.

## CDN

`.CDN` means "change directory and name". It changes the current directory and
then prints the drive-qualified, canonical long-filename path of the directory
that NextZXOS reached.

```text
.cdn                 show the current directory without changing it
.cdn ..              move to the parent and show the resulting path
.cdn fred            move into fred and show the resulting path
.cdn "My Games"      use quotes for LFNs containing spaces or a colon
```

If the directory change fails, `.CDN` returns the original esxDOS error to
NextZXOS and does not print a path. At the root, `.cdn ..` is expected to remain
at the root and print it, subject to the normal `F_CHDIR` behaviour of the
installed NextZXOS version.

The implementation uses the NextZXOS esxDOS-compatible `F_CHDIR` (`$A9`) and
`F_GETCWD` (`$A8`) hooks. `F_GETCWD` can return FAT 8.3 aliases, so `.CDN`
walks the resulting path component by component. For each parent directory it
uses `F_OPENDIR` (`$A3`) mode `$18` and `F_READDIR` (`$A4`) to match the short
name with the paired LFN, preserving the spelling stored on disk. Mode `$18`
requires NextZXOS 2.07 or later.

Arguments may end with NUL, ENTER, or an unquoted colon and are converted to
the null-terminated form required by `F_CHDIR`.

The directory-changing portion has been exercised under NextZXOS in CSpect.
The component-by-component LFN expansion is newly built and awaits runtime
confirmation there.

## SetNN

The legacy commands set the display mode to a particular number of characters
and perform a `CLS`.

### Set32
sets the display to the standard 32 column classic

### Set64
sets the display to a more usable 64 column mode

### Set85
sets the display to a slightly more taxing 85 column mode


The current sources execute tokenised forms of these NextBASIC statements:

```basic
SPECTRUM CHR$ %32 : CLS
SPECTRUM CHR$ %64 : CLS
SPECTRUM CHR$ %85 : CLS
```

The project is also intended to become a home for additional dot commands.
The shared source will eventually demonstrate NextZXOS ABI, memory, paging, error-handling,
and build details that future commands are likely to need.

## Status

All three `SetNN` commands have been built and tested successfully under
NextZXOS. They were built first with ZNC, then edited into standalone `.asm`
files and built with NextForge.

`.CDN` is the first command in the repository's SJAsmPlus build path. It builds
to a 1519-byte raw dot-command image at origin `$2000`.

## Installation and use

Copy the required extensionless files from `dot/` to the dot-command directory
on the Next SD card:

```text
C:/DOT/Set32
C:/DOT/Set64
C:/DOT/Set85
C:/DOT/cdn
```

Then enter `.SET32`, `.SET64`, `.SET85`, or `.CDN` at the
NextZXOS/NextBASIC command line.

## Building

The checked-in build script currently builds `.CDN` with SJAsmPlus 1.24.0 or a
compatible later version:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build.ps1
```

To remove and rebuild the generated binary:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build.ps1 -Clean
```

Use `-Assembler path/to/sjasmplus` to select a particular executable and
`-Command cdn` to build only that command. The script fails if SJAsmPlus fails
or the resulting dot command exceeds 8192 bytes.

The legacy `SetNN` sources are not built by this script because their current
NextForge/ZNC syntax is not accepted unchanged by SJAsmPlus. They can be ported
separately after their current runtime behaviour is captured on NextZXOS.

## Historical SetNN implementation notes

The sections below record investigation and design work from an older, larger
SJAsmPlus implementation of the display-mode commands. The current 51-byte
NextForge sources do not implement every paging and error-handling step
described below. Consult `src/set32.asm`, `src/set64.asm`, and `src/set85.asm`
for the code that produced the current release artifacts.

## Why the commands execute NextBASIC

The underlying Timex display mode can be changed through I/O port `$FF`, but a
direct port write is insufficient. NextZXOS also maintains software state for
the display, character renderer, cursor, windows, and editor geometry. The same
512-pixel hardware mode is used for both 64 and 85 columns, demonstrating that
the column count is not solely a hardware setting.

Calling the documented NextZXOS `IDE_BASIC` API with the same statement a user
would type lets NextZXOS perform the complete transition. This avoids a
mismatch between the hardware and the operating system's display state.

The relevant calls are:

```text
M_P3DOS   = $94    esxDOS bridge to the NextZXOS/+3DOS API
IDE_BASIC = $01C0  execute a tokenised BASIC command line
```

## Dot-command environment

A standard NextZXOS dot command:

- is assembled for origin `$2000`;
- is loaded into DivMMC RAM at `$2000`;
- has a maximum initial image size of 8 KiB;
- receives its arguments in `HL`, or zero if none were supplied;
- receives the complete command line in `BC`, excluding the leading dot;
- returns with carry clear on success;
- normally returns with carry set and an error code on failure.

The lower 16 KiB is not ordinary Spectrum RAM while a dot command runs.
Consequently, a pointer into the image at `$2000` cannot be passed to an API
requiring a buffer in main RAM.

## Tokenised BASIC command

`IDE_BASIC` accepts a tokenised line terminated by ENTER (`$0D`), not plain
ASCII source. The token values were confirmed against the NextBASIC tokenizer
and by testing the resulting commands under NextZXOS:

```text
$A3  SPECTRUM
$C2  CHR$
```

A stored Spectrum BASIC numeric literal contains visible ASCII digits and a
hidden numeric value. The command used by `.32` is:

```text
A3 C2 33 32 0E 00 00 20 00 00 0D
|  |  |---| |  |-----------|  |
|  |    32  |   integer 32    ENTER
|  |        numeric marker
|  CHR$
SPECTRUM
```

The `.64` and `.85` images change only the displayed digits and low byte of the
hidden integer.

## Allocating a valid buffer

`M_P3DOS` requires pointer parameters in ordinary RAM between `$4000` and
`$BFE0`. `IDE_BASIC` also requires the machine stack to remain in its normal
BASIC region between `STKEND` and `RAMTOP`.

The implementation asks the 48K BASIC ROM to allocate workspace:

```asm
ld   bc,command_length
rst  $18
defw $0030              ; BC_SPACES; returns start address in DE
```

The command is copied there and its address passed to `IDE_BASIC`. Afterwards,
the allocation is released:

```asm
ld   hl,(command_ptr)
ld   bc,command_length
rst  $18
defw $19e8              ; RECLAIM_2
```

This detail is important. An earlier implementation placed the command below
the current stack pointer. Moving `SP` below `STKEND` violated the `M_P3DOS`
contract, and NextZXOS rejected the call with carry clear and error `$00`.
Using `BC_SPACES` preserves the expected stack region and works correctly.

Within a dot command, `RST $18` followed by a routine address is the supported
way to call the standard 48K BASIC ROM.

## Paging requirements

`IDE_BASIC` uses the normal `ROM2/RAM5/RAM2/RAM0` configuration. Through
`M_P3DOS`, RAM bank 0 must already be paged at `$C000`.

The command therefore:

1. Saves `BANKM` at `$5B5C`.
2. Clears bits 0-2 to select RAM bank 0 while preserving other `$7FFD` flags.
3. Writes the temporary value to `BANKM` and port `$7FFD`.
4. Calls `IDE_BASIC` through `M_P3DOS` with `C=0`.
5. Restores the original port latch and `BANKM` value.

The `M_P3DOS` documentation also requires:

- no `$DFFD` paging to be active;
- MMU2 (`$4000-$5FFF`) to contain the normal lower half of RAM bank 5;
- pointer parameters to lie between `$4000` and `$BFE0`;
- `SP` to remain between `STKEND` and `RAMTOP` for this `C=0` call.

These conditions are supplied by a normal NextZXOS command-line invocation.

## `M_P3DOS` register convention

The bridge takes:

```text
DE = NextZXOS/+3DOS call ID
C  = RAM bank required at $C000
```

Parameters intended for the wrapped API's `BC`, `DE`, and `HL` are placed in
alternate `BC'`, `DE'`, and `HL'`. For `IDE_BASIC`, the command pointer goes in
`HL'`:

```asm
ld   hl,(command_ptr)
exx                         ; command pointer becomes HL'
ld   c,0                    ; RAM bank required by IDE_BASIC
ld   de,$01c0               ; IDE_BASIC
rst  $08
defb $94                    ; M_P3DOS
```

The documented convention says carry set from `M_P3DOS` means the wrapped call
succeeded and carry clear means failure. This is opposite to the dot-command
return convention, where carry clear indicates success. As explained below,
the tested system does not preserve that documented result for `IDE_BASIC`, so
this project checks `ERR_NR` instead.

## Error handling

The command initialises `ERR_NR` at `$5C3A` to a failure sentinel before
calling `IDE_BASIC`. A completed command sets `ERR_NR` to `$FF`; any other
value produces `IDE_BASIC ERR_NR $xx`.

Although the API documentation describes carry set as success, the tested
NextZXOS version returns carry clear from this `M_P3DOS` call even when
`IDE_BASIC` has executed and changed the display correctly. The implementation
therefore treats `ERR_NR`, not the bridge's returned carry flag, as
authoritative. Initialising it first also prevents a rejected or skipped call
from being mistaken for success because of a stale `$FF` value.
