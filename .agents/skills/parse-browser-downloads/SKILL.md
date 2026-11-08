---
name: parse-browser-downloads
description: 収集したブラウザプロファイル(Edge/Chrome/Firefox/IE 等)のダウンロード履歴を、NirSoft BrowserDownloadsView で CSV にパースする。ファイルのダウンロード元URL・保存先・日時を調べるときに使う(閲覧履歴は parse-browser)。
---

# ブラウザのダウンロード履歴のパース

共通手順: `docs/parse-common.md`

- ツール: NirSoft `BrowserDownloadsView`(`.env` の `BROWSERDOWNLOADSVIEW`)
- 入力: 収集フォルダ内の `Users`(各ユーザの `AppData\...` にブラウザのダウンロード記録がある構成)
- 出力名: `browser_downloads`
- 用途: **ダウンロード元URL(referrer / URLチェーン)は閲覧履歴(parse-browser)には出ない**。保存ファイルがどのサイトから来たかはこのスキルで調べる。

```powershell
$cfg = & .\scripts\Get-Config.ps1
$users = '<収集フォルダ>\...\Users'          # C:\Users と同じ構造のフォルダ(ユーザ配下に AppData)
$out = Join-Path $cfg.PARSED_DIR '<収集フォルダ名>\browser_downloads'
New-Item -ItemType Directory -Force $out | Out-Null

# 収集した profiles フォルダからダウンロード履歴を読み、CSV 保存(GUIは出ずに終了する)
& $cfg.BROWSERDOWNLOADSVIEW /DownloadsSource 3 /DownloadsSourceFolder $users `
    /scomma (Join-Path $out 'browser_downloads.csv')
```

- `/DownloadsSource 3` + `/DownloadsSourceFolder <Users>`: 指定した profiles フォルダ(`C:\Users` 相当)配下の各ユーザのダウンロード記録を読む。単一プロファイルだけなら `/DownloadsSource 4` でそのユーザフォルダを指定。
- 対象ブラウザを絞るなら `/LoadIE 1 /LoadEdge 1 /LoadChrome 1 /LoadFirefox 1`(既定は全て)。
- フラグ名はバージョンで異なることがある。うまく読めないときは、GUIの Advanced Options(F9)で「Load downloads from = specified profiles folder」に設定して `/cfg <ini>` に保存し、`/cfg <ini> /scomma <csv>` で実行する。初回に `-ShowHash` 等で挙動を確認してもよい。
- 出力 CSV 列の例: `Download URL, Web Page URL(referrer), Filename, Start Time, End Time, File Size, Web Browser, User Profile, ...`。ダウンロード元ホストは `Download URL` / `Web Page URL`。
- 時刻の既定はローカルタイム。UTC で揃えるなら解析時にタイムゾーンを明記する。
- **中身は読まない。読むときは `safe-read` スキル**(`.\scripts\safe_read.ps1 -Path '<out>\browser_downloads.csv' -Schema`)。
