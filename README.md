# ZX Spectrum Next dot commands

### (Some of the code in this repo was generated with the help of AI) 

Small utilities for NextZXOS, beginning with commands that switch the
NextBASIC editor and command line between its supported text widths:

```text
.32
.64
.85
```

The commands are shorthand for these working NextBASIC statements:

```basic
SPECTRUM CHR$ 32
SPECTRUM CHR$ 64
SPECTRUM CHR$ 85
```

The project is also intended to become a home for additional dot commands.
The shared source demonstrates NextZXOS ABI, memory, paging, error-handling,
and build details that future commands are likely to need.

## Status

All three commands have been built and tested successfully under NextZXOS.
Successful mode changes are silent. Diagnostic text is printed only when the
NextZXOS API call or executed BASIC command fails.

The generated files are `build/32`, `build/64`, and `build/85`. Each is
currently 157 bytes.

## Installation and use

Copy the extensionless files to the dot-command directory on the Next SD card:

```text
C:/DOT/32
C:/DOT/64
C:/DOT/85
```

Then enter `.32`, `.64`, or `.85` at the NextZXOS/NextBASIC command line. The
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

Diagnostics use the dot-command `RST $10` character-output service. The
command then exits cleanly so NextZXOS does not replace the useful message with
a generic report. On success it clears carry and returns silently.

## Source layout

```text
.
├── .gitignore
├── AGENTS.md
├── Makefile
├── README.md
├── build/
│   ├── 32
│   ├── 64
│   └── 85
├── src/
│   ├── 32.asm
│   ├── 64.asm
│   ├── 85.asm
│   └── columns.asm
└── tools/
    └── bootstrap-sjasmplus.sh
```

`src/columns.asm` contains the implementation. Each wrapper defines its width
and two visible ASCII digits before including that shared source. Paging,
memory management, API calls, and error handling therefore remain identical.

## Building

The build uses a pinned, project-local copy of SJAsmPlus 1.24.0. It does not
use or modify a system-wide assembler or a NextBuild installation:

```sh
make
```

On the first build, `tools/bootstrap-sjasmplus.sh` downloads the official
source release, verifies its SHA-256 checksum, and compiles the assembler into:

```text
.tools/bin/sjasmplus
```

The downloaded source and binary are ignored by Git. This keeps the toolchain
isolated from NextBuild and from other development projects. Bootstrapping
requires `curl`, `tar` with xz support, GNU Make, and a C++17 compiler.

To prepare the toolchain without building the commands, run:

```sh
make toolchain
```

You can also use a different SJAsmPlus executable without editing the Makefile:

```sh
make SJASMPLUS=/path/to/sjasmplus
```

Remove generated files with:

```sh
make clean
```

SJAsmPlus raw output begins with the first assembled byte, so `ORG $2000` sets
the runtime address without adding an 8192-byte prefix to the file.

## Adding another fixed-width variant

Create a wrapper like:

```asm
WIDTH           equ     42
WIDTH_ASCII_1   equ     '4'
WIDTH_ASCII_2   equ     '2'
                include "columns.asm"
```

Then add its target to the Makefile. NextBASIC must support the requested
value; the implementation does not validate it in advance and reports any
resulting `ERR_NR` failure.

For future dot commands with different purposes, reuse only relevant pieces:

- use `BC_SPACES` when an API needs a temporary main-RAM buffer;
- reclaim every successful allocation before returning;
- preserve and restore paging state;
- obey the wrapped call's RAM configuration;
- remember that `M_P3DOS` parameters use alternate registers;
- distinguish API errors from errors reported by the invoked service;
- keep the image below the 8 KiB basic dot-command limit.

## Verification checklist

1. Run `make clean && make`.
2. Confirm outputs are comfortably below 8192 bytes.
3. Confirm width variants differ only in displayed digits and hidden integer
   unless an implementation change was intended.
4. Copy extensionless files to `C:/DOT/`.
5. Test transitions from each width to every other width.
6. Run each command when already in its requested mode.
7. Confirm success is silent and leaves a usable prompt and cursor.
8. Confirm a BASIC program already in memory is undamaged.
9. Exercise an intentionally invalid development build if error handling
   changes.
10. Test in CSpect and, when possible, on real Spectrum Next hardware.

## References

- NextZXOS API documentation, normally on the Next SD card at
  `C:/DOCS/NEXTZXOS/NextZXOS_and_esxDOS_APIs.pdf`
- NextBASIC documentation for `SPECTRUM`
- Standard 48K ROM routines `BC_SPACES` (`$0030`) and `RECLAIM_2` (`$19E8`)

The source remains authoritative for exact implementation details; this README
records the constraints and design decisions behind it.
