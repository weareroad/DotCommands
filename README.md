# ZX Spectrum Next dot commands

## SetNN
sets the display mode to a particular number of characters and performs a CLS

### Set32
sets the display to the standard 32 column classic

### Set64
sets the display to a more usable 64 column mode

### Set85
sets the display to a slightly more taxing 85 column mode


The commands are shorthand for these working NextBASIC statements:

```basic
SPECTRUM CHR$ 32 : CLS  
SPECTRUM CHR$ 64 : CLS  
SPECTRUM CHR$ 85 : CLS  
```

The project is also intended to become a home for additional dot commands.
The shared source will eventually demonstrate NextZXOS ABI, memory, paging, error-handling,
and build details that future commands are likely to need.

## Status

All three commands have been built and tested successfully under NextZXOS.
They've been built first with ZNC, and then later edited into simple .asm files and built with NextForge.

## Installation and use

Copy the extensionless files in 'dot' to the dot-command directory on the Next SD card:

```text
C:/DOT/Set32
C:/DOT/Set64
C:/DOT/Set85
```

Then enter `.SET32`, `.SET64`, or `.SET85` at the NextZXOS/NextBASIC command line. The
numeric filenames are accepted by NextZXOS, so longer names are unnecessary.

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
