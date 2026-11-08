---
name: parse-browser
description: 収集したブラウザプロファイル(Edge/Chrome/Firefox/IE 等)の履歴を、NirSoft BrowsingHistoryView で CSV にパースする。閲覧履歴・ダウンロード元・訪問時刻を調べるときに使う。
---

# ブラウザ履歴のパース

共通手順: `docs/parse-common.md`

- ツール: NirSoft `BrowsingHistoryView`(`.env` の `BROWSERHISTORYVIEW`)
- 入力: 収集フォルダ内の `Users`(各ユーザの `AppData\...` に Edge/Chrome/Firefox の履歴がある構成)
- 出力名: `browser`

```powershell
$cfg = & .\scripts\Get-Config.ps1
$users = '<収集フォルダ>\...\Users'          # C:\Users と同じ構造のフォルダ(ユーザ配下に AppData)
$out = Join-Path $cfg.PARSED_DIR '<収集フォルダ名>\browser'
New-Item -ItemType Directory -Force $out | Out-Null

# 収集した profiles フォルダから履歴を読み、CSV 保存（GUIは出ずに終了する）
& $cfg.BROWSERHISTORYVIEW /HistorySource 3 /HistorySourceFolder $users `
    /VisitTimeFilterType 1 /scomma (Join-Path $out 'browser_history.csv')
```

- `/HistorySource 3` + `/HistorySourceFolder <Users>`: 指定した profiles フォルダ(`C:\Users` 相当)配下の各ユーザのブラウザ履歴を読む。単一プロファイルだけなら `/HistorySource 4` でそのユーザフォルダを指定。
- `/VisitTimeFilterType 1`: 期間フィルタなし(全件)。
- 対象ブラウザを絞るなら `/LoadIE 1 /LoadEdge 1 /LoadChrome 1 /LoadFirefox 1`(既定は全て)。
- 時刻の既定はローカルタイム。UTC で揃えたいなら `/cfg` で設定するか、解析時にタイムゾーンを明記する。
- 出力 CSV 列の例: `URL, Title, Visit Time, Visit Count, Visited From, Visit Type, Web Browser, User Profile, Browser Profile, URL Length, Typed Count, History File, Record ID`。
- **中身は読まない。読むときは `safe-read` スキル**(`.\scripts\safe_read.ps1 -Path '<out>\browser_history.csv' -Schema`)。
- **ダウンロード履歴(ダウンロード元URL等)は `parse-browser-downloads` スキル**(BrowserDownloadsView)を使う。閲覧履歴にはダウンロード元が出ないことがある。
- Cookie / キャッシュなど他のブラウザ痕跡は、対応する NirSoft ツール(MZCacheView, ChromeCacheView 等)を使う。未導入なら、その旨をユーザに伝えてから入手を相談する(自作パースはしない)。
