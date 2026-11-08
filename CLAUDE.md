@AGENTS.md

## Claude Code 固有
- `.claude/hooks/guard-parsed.ps1` が、`PARSED_DIR` を直接読む操作(Read / Grep / 読み取り系コマンド)を止める。
- ツールの画面出力を絞り込むときは `Where-Object { $_ -match '...' }` を使う(`Select-String` は `PARSED_DIR` と同じコマンドにあるとフックに止められる)。
- `safe_read.ps1` に `-Head` を付けない(読み取り語 `head` が `PARSED_DIR` のパスと同じコマンドにあるとフックに止められる)。絞り込みは `-Match`、ページ送りは `-Skip` で行う。
