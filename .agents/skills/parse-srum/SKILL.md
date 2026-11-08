---
name: parse-srum
description: CDIR-Cで収集したSRUM(SRUDB.dat)をSrumECmdでCSVにパースする。アプリごとのネットワーク使用量やリソース使用状況を調べるときに使う。
---

# SRUMのパース

共通手順: `docs/parse-common.md`

- ツール: `SRUMECMD`
- 入力: `SRUDB.dat`、アプリ名解決用の `SOFTWARE` ハイブ
- 出力名: `srum`

```powershell
$cfg = & .\scripts\Get-Config.ps1
& $cfg.SRUMECMD -f '<SRUDB.dat>' -r '<SOFTWARE>' --csv '<出力先>'
```

- DBがダーティで失敗したら、作業用コピーに `esentutl /r` / `/p` で修復が必要か、ユーザに確認する。原本は修復しない。
