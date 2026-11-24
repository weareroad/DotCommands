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

If `F_CHDIR` fails, its error is returned immediately. The current directory
therefore remains subject to the normal atomicity and error behaviour of
NextZXOS rather than being simulated within `.CDN`.

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

## Building

From the repository root, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build.ps1 -Clean
```

The build uses SJAsmPlus and writes the extensionless command to `dot/cdn`.
The build script also rejects an image larger than the 8 KiB dot-command
limit. The current binary is 1,519 bytes.

## Testing status

The command has been exercised under NextZXOS in CSpect. Tests confirmed
directory changes, parent traversal, and expansion of a returned short alias
such as `ZXNEXT~1` to its stored long name, `zxNextUnite`.

Further changes should test at least:

- invocation with no argument;
- a child directory specified by short and long name;
- `..` at an ordinary level and at the root;
- names containing spaces;
- nonexistent directories;
- paths with several components requiring LFN expansion;
- a path near the 255-character limit.
