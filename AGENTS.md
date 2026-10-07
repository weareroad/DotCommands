# Agent guidance for DotCommands

## Project scope

This repository contains small ZX Spectrum Next dot commands for NextZXOS. It
is intentionally independent of the neighbouring PlaygroundPanic game. Do not
read, edit, build, commit, or otherwise involve PlaygroundPanic unless the user
explicitly asks for cross-project work.

The GitHub repository is public at:

`https://github.com/weareroad/DotCommands`

The default branch is `main` and the remote is `origin`.

## Current commands

The tested commands are:

- `.32` — executes `SPECTRUM CHR$ 32`
- `.64` — executes `SPECTRUM CHR$ 64`
- `.85` — executes `SPECTRUM CHR$ 85`

Install the extensionless binaries from `build/` as `C:/DOT/32`,
`C:/DOT/64`, and `C:/DOT/85`. All three have been tested successfully under
NextZXOS. A successful invocation changes mode silently.

## Source and design

- `src/columns.asm` is the shared Z80 implementation.
- `src/32.asm`, `src/64.asm`, and `src/85.asm` define each width and include
  the shared source.
- The commands call NextZXOS `IDE_BASIC` (`$01C0`) through `M_P3DOS` (`$94`)
  rather than changing Timex port `$FF` directly. This keeps NextZXOS display,
  cursor, window, and editor state consistent.
- `IDE_BASIC` requires a tokenised BASIC line. `SPECTRUM` is token `$A3` and
  `CHR$` is token `$C2`; numeric literals include visible digits and the hidden
  five-byte numeric representation.
- The command buffer must be in normal RAM. Allocate it with the 48K ROM
  `BC_SPACES` routine (`$0030`) and release it with `RECLAIM_2` (`$19E8`). Do
  not move `SP` below `STKEND`: that caused `M_P3DOS` to reject the call with
  error `$00` during development.
- RAM bank 0 must be paged at `$C000` for `IDE_BASIC`. Preserve and restore
  port `$7FFD` and the `BANKM` system variable at `$5B5C`.
- On the tested NextZXOS system, `M_P3DOS` returns carry clear even when
  `IDE_BASIC` executes successfully. The implementation initializes `ERR_NR`
  and treats `ERR_NR=$FF` as authoritative success. Do not reintroduce a
  carry-based success diagnostic without testing against real NextZXOS.
- Errors print `IDE_BASIC ERR_NR $xx`; success prints nothing.

Read `README.md` before changing the implementation. It contains the detailed
ABI, paging, tokenisation, failed-approach history, installation instructions,
and verification checklist.

## Build

Run:

```sh
make clean && make
```

The Makefile bootstraps a pinned, project-local SJAsmPlus 1.24.0 toolchain at:

`.tools/bin/sjasmplus`

The bootstrap downloads the official source release, verifies its SHA-256
checksum, and builds it without Lua support. The `.tools/` directory is ignored
by Git and must remain independent of NextBuild and other projects. Override it
with `make SJASMPLUS=/path/to/sjasmplus` when needed.

SJAsmPlus raw output does not pad from address zero through `ORG $2000`. The
final dot binaries must start with the code loaded at `$2000` and remain below
the 8 KiB dot-command limit.

## Verification

For source changes:

1. Run `make clean && make`.
2. Run `git diff --check`.
3. Confirm every output is below 8192 bytes.
4. Test commands under NextZXOS, including transitions between every mode and
   invoking a command when already in that mode.
5. Confirm success is silent, the prompt/cursor remain usable, and a BASIC
   program already in memory is not damaged.
6. Report emulator or hardware limitations explicitly.

Keep generated release binaries in `build/`; they are intentionally tracked so
users can copy them directly to an SD card without installing the assembler.
