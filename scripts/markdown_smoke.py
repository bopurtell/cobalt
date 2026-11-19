#!/usr/bin/env python3
"""Real Markdown CLI/SGR smoke; run only after building a provider-enabled binary.

Usage: python3 scripts/markdown_smoke.py [COBALT [COBALT_WITHOUT_PROVIDER]]
No build is performed. Requires tmux and a UTF-8 locale; Python stdlib only.
Uses a private tmux socket, empty HOME/XDG directories and no LSP/network.
ANSI captures, raw startup output and shell terminal states remain in the printed
temporary directory on success or failure. Only source rows are style assertions.
"""

import argparse
from dataclasses import dataclass, replace
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import time


LINES = [
    "SMOKE_ANCHOR source",
    "# HeadingOne",
    "## HeadingTwo",
    "### HeadingThree",
    "#### HeadingFour",
    "##### HeadingFive",
    "###### HeadingSix",
    "plain **StrongWord** and *EmphasisWord* text",
    "[LinkLabel](https://example.invalid/path)",
    "plain `InlineCode` tail",
    "```",
    "FencedCode <&> **literal**",
    "```",
    "> QuoteWord",
    "- ListWord",
    "- [x] CheckedWord",
    "SMOKE_TAIL",
]
ORIGINAL = ("\n".join(LINES) + "\n").encode()
SGR = re.compile(r"\x1b\[([0-9;:]*)m")
DEADLINE = 15


@dataclass(frozen=True)
class Style:
    fg: tuple = ("default",)
    bg: tuple = ("default",)
    bold: bool = False
    italic: bool = False
    underline: bool = False


def sgr_rows(capture):
    """Decode capture-pane -e, carrying SGR state across row boundaries.

    tmux elides unchanged attributes between rows. Splitting into lines before
    decoding would therefore mistake inherited colors/fonts for defaults.
    Fixture source is ASCII, so one decoded character is one document cell.
    """
    style, rows, row = Style(), [], []
    at = 0
    while at < len(capture):
        match = SGR.match(capture, at)
        if match:
            codes = [int(value or "0") for value in match[1].replace(":", ";").split(";")]
            i = 0
            while i < len(codes):
                code = codes[i]
                if code == 0:
                    style = Style()
                elif code in (1, 3, 4, 22, 23, 24):
                    field = {1: "bold", 22: "bold", 3: "italic", 23: "italic",
                             4: "underline", 24: "underline"}[code]
                    style = replace(style, **{field: code in (1, 3, 4)})
                elif code in (38, 48):
                    channel = "fg" if code == 38 else "bg"
                    if i + 4 < len(codes) and codes[i + 1] == 2:
                        # Colon RGB may include an empty color-space ID.
                        extra = 1 if ":" in match[1] and i + 5 < len(codes) and codes[i + 2] == 0 else 0
                        start = i + 2 + extra
                        style = replace(style, **{channel: ("rgb", *codes[start:start + 3])})
                        i = start + 2
                    elif i + 2 < len(codes) and codes[i + 1] == 5:
                        style = replace(style, **{channel: ("indexed", codes[i + 2])})
                        i += 2
                    else:
                        raise AssertionError(f"Unsupported extended SGR: {match[0]!r}")
                elif code in (39, 49):
                    style = replace(style, **{"fg" if code == 39 else "bg": ("default",)})
                elif 30 <= code <= 37 or 90 <= code <= 97:
                    style = replace(style, fg=("ansi", code))
                elif 40 <= code <= 47 or 100 <= code <= 107:
                    style = replace(style, bg=("ansi", code))
                i += 1
            at = match.end()
        else:
            char = capture[at]
            assert char != "\x1b", f"Unexpected terminal escape near {capture[at:at + 30]!r}"
            if char == "\n":
                rows.append(row)
                row = []
            else:
                row.append((char, style))
            at += 1
    if row:
        rows.append(row)
    return rows


def source_rows(capture, lines=LINES):
    rows = sgr_rows(capture)
    assert len(rows) >= len(lines), "Source rows are not all visible"
    for index, expected in enumerate(lines):
        actual = "".join(char for char, _ in rows[index])
        # --bare places source at column zero. No concealment, substituted
        # punctuation, labels or fenced-code reflow are permitted in milestone 2.
        assert actual.rstrip(" ") == expected, (index + 1, expected, actual)
    return rows[:len(lines)]


def token(rows, line, text):
    index = LINES[line].index(text)
    return [style for _, style in rows[line][index:index + len(text)]]


def snapshot(rows):
    # Include two actual terminal padding cells after EOL, not footer/chrome.
    return [[style for _, style in row[:len(text) + 2]]
            for row, text in zip(rows, LINES)]


def assert_plain(rows):
    foreground = rows[-1][0][1].fg
    for row, text in zip(rows, LINES):
        for _, style in row[:len(text)]:
            assert style.fg == foreground, (text, style)
            assert not (style.bold or style.italic or style.underline), (text, style)


def assert_rich(rows):
    plain = rows[-1][0][1]
    heading_colors = []
    for line, word in enumerate(
            ["HeadingOne", "HeadingTwo", "HeadingThree", "HeadingFour", "HeadingFive", "HeadingSix"], 1):
        styles = token(rows, line, word)
        assert all(style.bold and style.fg != plain.fg for style in styles), (word, styles)
        heading_colors.append(styles[0].fg)
    assert len(set(heading_colors)) == 6, heading_colors
    assert all(style.bold for style in token(rows, 7, "StrongWord"))
    assert all(style.italic for style in token(rows, 7, "EmphasisWord"))
    label = token(rows, 8, "LinkLabel")
    destination = token(rows, 8, "https://example.invalid/path")
    assert all(style.underline and style.fg != plain.fg for style in label), label
    assert all(not style.underline and style.fg != label[0].fg for style in destination), destination
    inline = token(rows, 9, "InlineCode")
    fenced = token(rows, 11, "FencedCode")
    assert inline[0].bg != plain.bg, (inline, plain)
    assert all(style.bg == inline[0].bg for style in inline + fenced), (inline, fenced)
    for line in (9, 11):
        # Code surfaces are source-shaped, not whole-row fills.
        assert rows[line][len(LINES[line]) + 1][1].bg == plain.bg, rows[line]
    for line, word in ((13, "QuoteWord"), (14, "-"), (15, "[x]")):
        assert all(style.fg != plain.fg for style in token(rows, line, word)), (line, word)


def self_test():
    rows = sgr_rows("\x1b[38;2;12;34;56m\x1b[48;2;78;90;12m\x1b[1;3;4mA\nB"
                    "\x1b[22;23;24mC\x1b[0mD\n")
    assert rows[0][0][1] == rows[1][0][1]
    assert rows[0][0][1] == Style(("rgb", 12, 34, 56), ("rgb", 78, 90, 12), True, True, True)
    assert rows[1][1][1] == Style(("rgb", 12, 34, 56), ("rgb", 78, 90, 12))
    assert rows[1][2][1] == Style()


class Terminal:
    def __init__(self, root):
        self.root = root
        self.case = "shell"
        self.raw = root / "shell.raw"
        directories = {name: root / name.lower() for name in
                       ("HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME",
                        "XDG_STATE_HOME", "XDG_RUNTIME_DIR")}
        for directory in directories.values():
            directory.mkdir(mode=0o700)
        self.env = {name: str(value) for name, value in directories.items()}
        self.env.update(PATH=os.environ.get("PATH", "/usr/bin:/bin"), LC_ALL="C.UTF-8",
                        LANG="C.UTF-8", TERM="tmux-256color", COLORTERM="truecolor",
                        TMPDIR=str(root), SHELL="/bin/bash", PS1="MARKDOWN_SHELL> ")
        self.command = ["tmux", "-S", str(root / "tmux.sock"), "-f", "/dev/null"]

    def t(self, *args):
        result = subprocess.run(self.command + list(args), env=self.env, cwd=self.root,
                                capture_output=True, text=True, timeout=5)
        if result.returncode:
            raise AssertionError(f"tmux {args}: {result.stderr}")
        return result.stdout

    def start(self):
        shell = shlex.join(["env", "-i", *[f"{key}={value}" for key, value in self.env.items()],
                            "/bin/bash", "--norc", "--noprofile"])
        self.t("new-session", "-d", "-s", "markdown", "-x", "140", "-y", "40",
               "-c", str(self.root), shell)
        self.t("set-option", "-t", "markdown", "status", "off")
        self.wait(lambda: "MARKDOWN_SHELL>" in self.screen(), "isolated shell")

    def screen(self, ansi=False):
        # -N retains EOL cells: code's source-only Surface assertion must inspect
        # real terminal padding rather than relying on capture's trimming rules.
        return self.t("capture-pane", "-p", "-N", *(["-e"] if ansi else []), "-t", "markdown")

    def send(self, text):
        self.t("send-keys", "-t", "markdown", "-l", "--", text)

    def key(self, name):
        self.t("send-keys", "-t", "markdown", name)
        if name == "Escape":
            # Standalone ESC has a terminal-protocol ambiguity timer.
            time.sleep(.25)

    def wait(self, predicate, label):
        deadline = time.monotonic() + DEADLINE
        detail = None
        while time.monotonic() < deadline:
            try:
                if predicate():
                    return
            except (AssertionError, IndexError) as error:
                detail = error
            time.sleep(.05)
        self.capture("failure")
        raise AssertionError(f"{self.case}: timed out waiting for {label}; {detail}\n{self.screen()}")

    def check(self, assertion, label):
        def ready():
            assertion(source_rows(self.screen(True)))
            return True
        self.wait(ready, label)
        self.capture(label)

    def capture(self, label):
        (self.root / f"{self.case}-{label}.ansi").write_text(self.screen(True))

    def alternate(self):
        return self.t("display-message", "-p", "-t", "markdown", "#{alternate_on}").strip()

    def launch(self, binary, extension, enabled, label):
        self.case = label
        self.fixture = self.root / f"document.{extension}"
        self.fixture.write_bytes(ORIGINAL)
        self.raw = self.root / f"{label}.raw"
        self.t("pipe-pane", "-t", "markdown", f"cat > {shlex.quote(str(self.raw))}")
        options = ["--no-lsp", "--bare", "--theme", "crimson"]
        if enabled:
            options.append("--markdown")
        # A shell helper records the outer PTY modes before and after the real
        # CLI. Paths and arguments are shell-quoted; no user rc/config is loaded.
        helper = self.root / f"{label}.sh"
        helper.write_text(
            "stty -g > " + shlex.quote(str(self.root / f"{label}.before")) + "\n"
            + shlex.join([str(binary), *options, str(self.fixture)]) + "\n"
            + "result=$?\nstty -g > " + shlex.quote(str(self.root / f"{label}.after")) + "\n"
            + "printf '%s\\n' \"$result\" > " + shlex.quote(str(self.root / f"{label}.exit")) + "\n")
        self.send(shlex.join(["/bin/sh", str(helper)]))
        self.key("Enter")
        self.wait(lambda: self.alternate() == "1" and self.raw.exists()
                  and b"Snippets reloaded" in self.raw.read_bytes()
                  and "SMOKE_TAIL" in self.screen(), "async snippet startup readiness")
        # Dismiss transient startup feedback only after its asynchronous reply;
        # drawing the document alone does not mean input/startup has settled.
        self.send("lh")
        self.check(lambda rows: None, "startup-source")

    def toggle(self):
        self.send(" cc")
        self.wait(lambda: "Commands" in self.screen(), "command palette")
        self.send("Toggle document decorations")
        self.wait(lambda: "> Toggle document decorations" in self.screen(), "palette toggle result")
        self.key("Enter")
        self.wait(lambda: "Commands" not in self.screen(), "palette closed")

    def cursor_line(self, text):
        y = int(self.t("display-message", "-p", "-t", "markdown", "#{cursor_y}").strip())
        return self.screen().splitlines()[y].rstrip() == text

    def reveal(self):
        def raw_line(rows, index):
            styles = [style for _, style in rows[index][:len(LINES[index])]]
            assert all(style.fg == rows[-1][0][1].fg and not
                       (style.bold or style.italic or style.underline) for style in styles), styles
            assert len({style.bg for style in styles}) == 1, styles
        for movement, index in (("j", 1), ("8G", 7), ("10G", 9)):
            self.send(movement)
            self.wait(lambda: self.cursor_line(LINES[index]), "source cursor motion")
            self.check(lambda rows: raw_line(rows, index), f"active-line-{index + 1}")
            self.send("gg")
            self.check(assert_rich, "restored-away-from-source")

    def edit_undo_save(self, rich):
        self.send("j0iX")
        changed = list(LINES)
        changed[1] = "X" + changed[1]
        expected = ("\n".join(changed) + "\n").encode()
        self.wait(lambda: self.cursor_line(changed[1]), "literal heading edit")
        source_rows(self.screen(True), changed)
        assert self.fixture.read_bytes() == ORIGINAL, "An unsaved edit reached disk"
        self.key("Escape")
        self.send(" w")
        self.wait(lambda: self.fixture.read_bytes() == expected, "save edited source punctuation")
        self.send("u")
        self.wait(lambda: self.cursor_line(LINES[1]), "undo heading edit")
        source_rows(self.screen(True))
        assert self.fixture.read_bytes() == expected, "Undo changed disk before save"
        self.send(" w")
        self.wait(lambda: self.fixture.read_bytes() == ORIGINAL, "save exact original bytes after undo")
        self.send("gg")
        self.check(assert_rich if rich else assert_plain, "after-edit-undo-save")

    def finish(self):
        self.send(" q")
        after = self.root / f"{self.case}.after"
        result = self.root / f"{self.case}.exit"
        self.wait(lambda: result.exists() and after.exists() and self.alternate() == "0", "clean CLI quit")
        assert result.read_text().strip() == "0", result.read_text()
        assert (self.root / f"{self.case}.before").read_bytes() == after.read_bytes(), "Terminal modes changed"
        assert self.t("display-message", "-p", "-t", "markdown", "#{cursor_flag}").strip() == "1"
        assert self.fixture.read_bytes() == ORIGINAL, "Saved bytes differ after quit"
        self.t("pipe-pane", "-t", "markdown")

    def close(self):
        subprocess.run(self.command + ["kill-server"], env=self.env,
                       capture_output=True, timeout=5, check=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", nargs="?", default=str(
        Path(__file__).resolve().parents[1] / "_build/default/bin/cobalt.exe"))
    parser.add_argument("no_provider_binary", nargs="?")
    args = parser.parse_args()
    binaries = [Path(path).resolve() for path in (args.binary, args.no_provider_binary) if path]
    for binary in binaries:
        if not binary.is_file() or not os.access(binary, os.X_OK):
            parser.error(f"Build the executable first (this script never builds): {binary}")
    if shutil.which("tmux") is None:
        parser.error("tmux is required")
    self_test()
    temporary = Path("/tmp/opencode")
    root = Path(tempfile.mkdtemp(prefix="cobalt-markdown-smoke-",
                                dir=temporary if temporary.is_dir() else None))
    terminal = Terminal(root)
    try:
        terminal.start()
        for extension in ("md", "markdown"):
            terminal.launch(binaries[0], extension, False, f"{extension}-default-off")
            terminal.check(assert_plain, "plain-source")
            baseline = snapshot(source_rows(terminal.screen(True)))
            terminal.finish()
            terminal.launch(binaries[0], extension, True, f"{extension}-enabled")
            terminal.check(assert_rich, "rich-source")
            terminal.toggle()
            terminal.check(assert_plain, "disabled-from-palette")
            assert snapshot(source_rows(terminal.screen(True))) == baseline, "Disabled styles differ from default-off"
            terminal.toggle()
            terminal.check(assert_rich, "reenabled-from-palette")
            terminal.reveal()
            terminal.edit_undo_save(rich=True)
            terminal.finish()
            print(f"PASS: .{extension} opt-in/default-off; source SGR; palette toggle; reveal; edit/undo/save; PTY restoration")
        if len(binaries) == 2:
            terminal.launch(binaries[1], "md", True, "provider-absent")
            terminal.wait(lambda: b"Document decorations unavailable in this build" in terminal.raw.read_bytes(),
                          "nonfatal unavailable-provider notice")
            terminal.check(assert_plain, "unavailable-remains-source")
            terminal.toggle()
            terminal.check(assert_plain, "unavailable-toggle-is-nonfatal")
            terminal.edit_undo_save(rich=False)
            terminal.finish()
            print("PASS: absent-provider --markdown notice; palette; ordinary editing/saving/quit")
        else:
            print("SKIP: absent-provider case (pass its executable as the second argument)")
    finally:
        terminal.close()
        print(f"Markdown terminal captures: {root}")


if __name__ == "__main__":
    main()
