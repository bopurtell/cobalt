# Markdown styling: manual acceptance

[Testing index](README.md) · [Implementation plan](../plans/markdown_decorations.md)

Milestone 2 checks source-preserving styling, not a rendered preview or WYSIWYG
editor. Table alignment, hidden link destinations, virtual rows and automatic
formatting belong to later milestones.

## Start with a scratch copy

After building the Markdown-enabled executable:

```sh
scratch=$(mktemp /tmp/opencode/cobalt-markdown-check.XXXXXX.md)
cp docs/testing/fixtures/markdown_styles.md "$scratch"
sha256sum "$scratch"
_build/default/bin/cobalt.exe --markdown "$scratch"
```

The first fixture line is ordinary prose. Leave the cursor there initially:
the current source line intentionally reveals its undecorated form.

## What to check

1. **Visible styling:** heading levels are distinguishable; emphasis/strong have
   italic/bold treatment where supported by the terminal/font; inline/fenced code
   cells have a background; explicit inline-link labels and destinations are
   distinguishable. Reference/shortcut links are intentionally conservative.
2. **Source stays visible:** all `#`, stars, backticks, fence markers, brackets,
   destinations, list/check markers and table pipes remain present. Tables do not
   gain padding or borders. No external viewer opens and no URLs are fetched.
3. **Cursor reveal:** move onto a styled line and back off it. Its decoration
   disappears while active and returns when leaving. Text, cursor column, line
   numbers and document row count must not change.
4. **Toggle:** open `Space c c`, choose **Toggle document decorations**, then
   repeat. Disabling removes Markdown-specific styling immediately; re-enabling
   restores it without changing text or setting the dirty flag.
5. **Editing and history:** edit headings, an unfinished emphasis/link, and fence
   delimiters. Movement, yank/paste, `u` and `Ctrl-r` still operate on source bytes.
   Invalid or incomplete syntax must not crash the editor or retain stale ranges.
6. **Selections/search:** try `v`, `V`, `Ctrl-v`, and block insertion. Visual and
   block-insert presentation stays raw. Search overlays must remain legible over
   decorated prose/code without shifting the cursor.
7. **Unicode and clipping:** move around `界`, combining text and emoji. Resize to
   a narrow terminal and horizontally scroll long lines. No cursor drift, hidden
   source controls, new line breaks or changed save bytes are acceptable.
8. **Lifecycle:** switch between Markdown and ordinary source buffers, reload a
   file, close/reopen it, and toggle while viewing a non-Markdown file. Styles must
   never migrate to the wrong buffer or survive edits at obsolete offsets.
9. **Themes/presentation:** try light and dark themes, Zen/Bare, and terminal
   resizing. Source and geometry remain unchanged; code backgrounds are styling
   of source cells, not full-width preview boxes.

Undo any edits, save with `Space w`, and quit with `Space q`. Repeat
`sha256sum "$scratch"`; it should match the initial value if all edits were undone.
Also open the scratch file without `--markdown` to verify the default-off path.

## Absent-provider check

Try the explicit no-provider executable:

```sh
dune build -j 4 bin/cobalt_no_provider.exe
_build/default/bin/cobalt_no_provider.exe --markdown "$scratch"
```

It must open and edit the file normally.
Requesting Markdown styling should report that support is unavailable in that
build, not abort startup, saving or navigation. The implementation plan records
the reproducible build-without-Markdown proof and actual verification results.

The focused automated terminal check is:

```sh
dune build -j 4 @scripts/smoke-markdown
```

It uses isolated settings and a private tmux server. The stronger absence proof
builds a temporary source copy without `markdown/`:

```sh
python3 scripts/smoke_no_markdown.py --jobs 6
```

## Configuration isolation for scripted smokes

The existing theme smoke inherits `XDG_CONFIG_HOME`; the shell smoke discards it
with `env -i` but retains `HOME`. Use temporary empty settings for automated
default-behavior assertions. Do not change personal settings to make a test pass.
