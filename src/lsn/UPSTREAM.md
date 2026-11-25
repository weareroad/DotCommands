# LSN upstream provenance

`LSN` is a modified build of Allen Albright's 128K `ls` dot command from the
Spectrum Next distribution:

- Repository: <https://gitlab.com/thesmog358/tbblue>
- Source path: `src/c/DotCommands/ls/128/`
- Snapshot commit: `3a892b03738cfb27eee01f33d09186d3215a5a4a`
- Snapshot checked: 2026-11-25

The distribution source was compared with the z88dk copy under
`examples/zxn/unsorted/dot-command/ls/128/`. They were functionally identical;
the distribution build selected 28 MHz while the z88dk copy selected 14 MHz.

## Local modifications

- The command is named `LSN` and has project-specific version/help text.
- After reading `env.cfg`, it applies defaults equivalent to:

  ```text
  -A -1 --lfn=on --gdf --time-style=long-iso -d --system
  ```

- Explicit command-line options and file operands are still parsed normally.
- It selects 28 MHz only when necessary and restores the entry speed from its
  registered cleanup handler on every normal `main`/`exit` path.
- Comparator callbacks use the const-correct `qsort`/`bsearch` signatures
  required by the tested 2026 z88dk toolchain.
- The help text fixes upstream's `--fromat=commas` typo.

The derived source remains under the upstream Clarified Artistic License in
`LICENSE`; it is not covered by this repository's CC0 dedication.
