# LSN dot command

`.LSN` is a custom build of the Spectrum Next distribution's 128K `.ls`
command. It packages a frequently used listing profile under a short command
name while retaining the original file matching, directory catalogue, sorting,
formatting, and command-line option implementation.

## Background and design decision

The desired shorthand was:

```text
.ls -A -1 --lfn=on --gdf --time-style=long-iso -d --system
```

At first this looked similar to the SetNN commands in this repository. SetNN
allocates a tokenised NextBASIC statement in ordinary RAM and asks
`IDE_BASIC` to execute it. That pattern works because the statement changes
display state without loading another dot command.

It is not safe or supported for `.LSN` to execute `.ls` in the same way:

- NextZXOS provides `M_EXECCMD` (`$8f`) to execute a dot command, but its API
  explicitly states that the hook cannot be used from another dot command.
- A conventional dot command is loaded into DivMMC memory at `$2000-$3fff`.
  Loading `.ls` while `.LSN` was still active would replace the caller's own
  image.
- Passing a textual `.ls` line through `IDE_BASIC` would still reach the same
  nested dot-command loader and would not avoid that restriction.

The robust solution was therefore to build a renamed, minimally modified copy
of the real `.ls` implementation with the preferred initial settings.

## Usage

```text
.lsn
.lsn FILE...
.lsn OPTION... FILE...
.lsn --help
```

The built-in profile is equivalent to placing these arguments before any
arguments supplied by the user:

```text
-A -1 --lfn=on --gdf --time-style=long-iso -d --system
```

This means:

- omit the synthetic `.` and `..` entries;
- print one entry per line;
- print long filenames;
- group directories before files;
- use long-ISO timestamps where timestamps are displayed;
- list directory operands instead of entering them; and
- include system entries.

With no operand, the upstream lister still catalogues the current directory.
Explicit options are processed after the profile, so options such as `-C`,
`--lfn=off`, `-R`, and the other supported `.ls` switches can replace the
corresponding display, filename, or directory behaviour. `--gdf` and
`--system` have no inverse switches in the upstream parser.

The accepted timestamp switch is `--time-style=long-iso`; `.ls` does not
define a `--time-config` option.

## Selecting the upstream source

The sources in `src/lsn/` derive from:

```text
https://gitlab.com/thesmog358/tbblue/-/tree/master/src/c/DotCommands/ls/128/
```

Before importing it, the Spectrum Next distribution source was compared
directly with z88dk's copy under
`examples/zxn/unsorted/dot-command/ls/128/`. Of the 26 common source and build
files, 24 were text-identical after normalising line endings. The only
functional source difference was that the distribution selected 28 MHz while
the z88dk example selected 14 MHz; the other difference was one example date
in the help text. The option parser, defaults, catalogue code, sorting, memory
model, and dotN configuration were otherwise the same.

`src/lsn/UPSTREAM.md` pins the imported distribution snapshot and lists each
local change. Keeping the complete source in this repository makes the build
self-contained apart from the documented z88dk toolchain and makes future
upstream comparisons possible.

## Applying the LSN profile

The upstream global option structure initially retains its normal `.ls`
values. After `.ls` has read `TIME_STYLE` and `LS_COLOR` from `env.cfg`, `.LSN`
applies this profile:

```c
flags.file_filter = FLAG_FILE_FILTER_ALMOST_ALL;
flags.sort_mod = FLAG_SORT_MOD_GDF;
flags.date_func = date_fmt_long_iso;
flags.name_fmt_mod = FLAG_NAME_FMT_MOD_LFN;
flags.disp_fmt = FLAG_DISP_FMT_PER_LINE;
flags.sys = 1;
flags.dir_type = FLAG_DIR_TYPE_LIST;
```

Applying the profile after `env.cfg` is important: it gives the long-ISO choice
the same precedence it would have if the fixed option appeared on the command
line. The original parser then processes the user's real arguments, allowing
an explicit `-C`, `--lfn=off`, `-R`, time style, or other supported option to
replace the corresponding default. `--gdf` and `--system` remain enabled
because upstream provides no inverse switches for them.

No synthetic command line is constructed, and the original parser, wildcard
handling, error reporting, directory catalogue, and listing code remain in
control.

## Turbo-speed handling

The command records the turbo register on entry. If the machine is not already
at 28 MHz, it selects 28 MHz and records that a change was made. The registered
cleanup routine restores the original value on normal return and on paths that
use the C runtime's `exit` handling.

If the machine was already running at 28 MHz, `.LSN` performs no speed write
and cleanup leaves the register alone. This avoids imposing a permanent speed
change on the NextZXOS prompt.

## dotN memory model

The full lister does not fit in a conventional 8 KiB dot-command image. z88dk
builds it as a dotN image with a standard loader followed by managed pages. The
current image is 24576 bytes. Its pragmas place the main code at `$8180`,
reserve a 384-byte stack below it, allocate the required main-bank pages, and
request six extra pages for directory and file records.

## Building

The tested toolchain is z88dk frontend v26602-687c8e22e9 dated 2026-10-24.
Build from the repository root with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build.ps1 `
  -Command lsn -Z88dkRoot C:/path/to/z88dk
```

If `zcc` and `z88dk-zx7` are on `PATH`, `-Z88dkRoot` may be omitted. The build
stages sources under ignored `.tools/build/lsn`, compresses the help text,
builds the dotN, copies only `dot/lsn`, and removes the staging directory.

The current z88dk compiler requires const-correct `qsort` and `bsearch`
callbacks. Those signature-only compatibility changes are recorded in the
upstream provenance document.

The build integration deliberately has two paths:

- SJAsmPlus continues to build `.CDN` and the SetNN family and enforces their
  conventional 8192-byte ceiling.
- z88dk builds `.LSN` as dotN, for which the complete file is expected to be
  larger than 8192 bytes.

`build.ps1 -Command all` includes both paths. `-Command lsn` selects only the
z88dk build, and `-Clean` removes and regenerates the checked-in release image.

## Installing into a test image

The release file is extensionless and is copied to `C:/DOT/lsn`. For an HDF
or raw SD image managed by HDFMonkey, the deployment shape is:

```text
hdfmonkey put <image> dot/lsn /dot/lsn
hdfmonkey get <image> /dot/lsn <temporary-file>
```

The second command allows the installed entry to be compared byte-for-byte
with `dot/lsn` before launching the emulator. The regular local CSpect paths
and launch arguments are recorded in `AGENTS.md` rather than embedded in this
portable command guide.

## Licensing

The derived source and binary use the Clarified Artistic License supplied in
`src/lsn/LICENSE`. They are separate from the repository's CC0-1.0 original
code. Preserve the source, licence, attribution, and modification notice when
redistributing `dot/lsn`.

## Verification status

The source builds reproducibly to a 24576-byte dotN with the documented z88dk
toolchain. Repeated clean builds produced SHA-256
`28b940d39eec5d999948a603f11c42b6873ef7abd7ec77944bd63bdfeaaf77c6`.

The following verification was completed on 2026-11-25:

- the canonical clean build completed for `.CDN`, `.LSN`, and all SetNN
  commands;
- all three optimized SetNN reference hashes still passed;
- repeated `.LSN` builds were byte-identical and 24576 bytes long;
- HDFMonkey copied `dot/lsn` to `/dot/lsn` in the CSpect test image;
- extracting `/dot/lsn` from the image matched the release artifact
  byte-for-byte; and
- the default `.lsn` invocation ran successfully under NextZXOS in CSpect and
  produced the intended listing, as confirmed during interactive testing.

This is emulator verification, not real Spectrum Next hardware verification.
The default workflow is confirmed; individual option overrides, every error
path, repeated invocation under stress, and turbo-register restoration from
each possible entry speed have not yet been independently instrumented or
exhaustively tested.
