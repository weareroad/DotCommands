# `.CDN` — change directory and name

`.CDN` is a NextZXOS dot command that changes the current directory and then
prints the full, drive-qualified path using the long filenames stored on the
disk.

It is intended as a companion to the existing `CD` and `.CD` commands, not as
a replacement for either of them. The different name avoids changing the
behaviour expected by scripts or by other Spectrum Next installations.

## Using the command

With a directory argument, `.CDN` changes to that directory and prints the
resulting path:

```text
C:\APPS>.cdn zxnextunite
C:\APPS\zxNextUnite
```

The directory lookup follows the usual NextZXOS rules, so the argument may use
the short or long form of a name. The displayed result uses the name and case
stored in the directory entry.

Use `..` to move to the parent directory:

```text
C:\APPS\zxNextUnite>.cdn ..
C:\APPS
```

With no argument, `.CDN` does not change directory; it prints the expanded
long-filename form of the current path:

```text
.cdn
C:\APPS\zxNextUnite
```

Quote an argument when it contains spaces or a colon:

```text
.cdn "My Games"
```

Use either help option for a compact reminder:

```text
.cdn -h
.cdn -?
```

The version 0.1 help text is kept within the 32-column display width:

```text
.cdn [dir-name|prefix]
v0.1 - we.are.road

Change dir & print LFN path.
No arg: show current path.
Prefix: show permutations
        1-9: select, ENTER: 1st
        any other key cancels
```

Only those exact options are reserved; a longer argument beginning with `-`
still goes through normal directory handling.

### Prefix selection

An exact directory name always takes the fast path and behaves as described
above. If the exact change fails, `.CDN` treats the argument as a
case-insensitive prefix and looks for matching subdirectories of the current
directory. For example:

```text
C:\>.cdn a
1 C:\APPS
2 C:\AUDIO
```

Press the displayed digit to select a directory. Press ENTER to select item 1,
which makes a unique or commonly-first prefix quick to use: type its first
letter, ENTER to submit the command, then ENTER again to accept the first
match. Any key other than ENTER or a displayed choice cancels without changing
directory. In either case, a blank line separates the choice list from the
final path. Cancellation restates the unchanged current path so the result is
always explicit.

At most nine choices are displayed. If another matching directory exists, the
list ends with:

```text
(more, truncated)
```

Choices follow the order returned by the filesystem. The prefix applies to a
child directory's long filename; files are not offered.

The root is printed with its trailing backslash, for example `C:\`. Other
paths are printed without a trailing backslash.

If the requested directory does not exist or cannot be opened, `.CDN` returns
the native esxDOS/NextZXOS error and does not print a misleading path.

## NextZXOS requirement

The command requires NextZXOS 2.07 or later. It uses the long-and-short-name
directory mode introduced in that release to recover the exact long filename
corresponding to each FAT 8.3 alias.

## How the code works

The source is [`src/cdn.asm`](../src/cdn.asm) and uses standard SJAsmPlus
syntax. It is assembled as a raw dot-command image at `$2000`.

### Changing directory

On entry to a dot command, `HL` points to its argument or is zero when no
argument was supplied. `.CDN` copies and terminates that text before calling
the esxDOS-compatible `F_CHDIR` hook:

```text
F_CHDIR = $A9
```

The parser accepts NUL, ENTER, or an unquoted colon as the command terminator.
It removes one pair of surrounding double quotes and trims trailing spaces
from an unquoted argument. The input is limited to the NextZXOS pathname
maximum of 255 characters plus its terminating zero.

Before calling `F_CHDIR`, the command checks for exact `-h`, `-H`, and `-?`
arguments. They print a compact usage summary, version and attribution, then
return successfully. The initial release identifies itself as
`v0.1 - we.are.road`.

If `F_CHDIR` succeeds, `.CDN` immediately prints the resulting expanded path.
If it fails, the current directory is unchanged, allowing `.CDN` to try the
prefix-selection fallback described below. If no child directory matches, the
original `F_CHDIR` error is returned.

### Why `F_GETCWD` is not enough

After changing directory, the command calls:

```text
F_GETCWD = $A8
```

This supplies a canonical, drive-qualified path, but it can contain FAT short
names. For example, the directory `zxNextUnite` may be returned as
`ZXNEXT~1`. Printing that result directly would give:

```text
C:\APPS\ZXNEXT~1\
```

That is a valid path, but it is not the long-filename result that `.CDN` is
designed to show.

### Expanding each component

`.CDN` starts with the drive and root from the path returned by `F_GETCWD`,
then processes each short component in order. For every component it:

1. Opens the already-expanded parent with `F_OPENDIR` (`$A3`).
2. Selects mode `$18`, which makes `F_READDIR` return an LFN followed by its
   corresponding short name.
3. Reads entries with `F_READDIR` (`$A4`) until the short name matches the
   component, using an ASCII case-insensitive comparison.
4. Appends the paired long name to the output path.
5. Closes the directory handle with `F_CLOSE` (`$9B`).

This is repeated from the root downwards. Opening the expanded parent on each
iteration means the lookup remains unambiguous even when several levels of
the path were originally returned as short aliases.

The directory-entry buffer allows for the attribute byte, a 260-character
LFN plus terminator, a 12-character short name plus terminator, and the date,
time, and size metadata returned by `F_READDIR`.

The final path is still limited to 255 characters. If expansion would exceed
that limit, the command returns `ENAMETOOLONG` rather than overflowing its
buffer.

### Building the prefix choices

When the exact `F_CHDIR` call fails, `.CDN` expands the unchanged current path
and enumerates that directory in the same `$18` long-and-short-name mode. It
filters entries using the FAT directory attribute and compares the argument
with the start of each LFN without ASCII case sensitivity.

The first nine matching full paths are copied into fixed 256-byte slots. This
uses more of the dot-command image, but means the selected path remains stable
after `F_READDIR` reuses its directory-entry buffer. Discovering a tenth match
is enough to print the truncation marker; later entries do not need to be read.

The command polls the eight Spectrum keyboard half-rows directly. It first
waits for the ENTER key that submitted the command to be released, then waits
for a fresh press. A valid displayed digit changes to its saved full path and
ENTER maps to the first slot. Other keys return success without making a
filesystem change. After selection or cancellation, a blank line is printed
and the normal expanded-current-path routine is used to display the resulting
location. Direct matrix input avoids relying on a BASIC input channel, which
is not valid during every dot-command invocation.

## Building

From the repository root, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build.ps1 -Clean
```

The build uses SJAsmPlus and writes the extensionless command to `dot/cdn`.
The build script also rejects an image larger than the 8 KiB dot-command
limit. The current binary is 4,488 bytes.

## Testing status

The command has been exercised under NextZXOS in CSpect. Tests confirmed exact
directory changes, parent traversal, expansion of a returned short alias such
as `ZXNEXT~1` to its stored long name, `zxNextUnite`, interactive selection and
cancellation, and truncation after nine displayed choices.

Regression testing should cover:

- invocation with no argument;
- a child directory specified by short and long name;
- `..` at an ordinary level and at the root;
- names containing spaces;
- nonexistent directories;
- a unique prefix selected with ENTER;
- several prefix matches selected by digit and cancelled with another key;
- ten or more matches and the truncation marker;
- paths with several components requiring LFN expansion;
- a path near the 255-character limit.
