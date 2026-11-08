---
name: parse-evtx
description: CDIR-Cで収集したイベントログ(*.evtx)をEvtxECmdでCSVにパースする。ログオン、サービス、PowerShell実行などを調べるときに使う。
---

# イベントログのパース

共通手順: `docs/parse-common.md`

- ツール: `EVTXECMD`(exeと同じフォルダの `Maps` を使用)
- 入力: `*.evtx` を含むフォルダ
- 出力名: `evtx`

```powershell
$cfg = & .\scripts\Get-Config.ps1
& $cfg.EVTXECMD -d '<evtxフォルダ>' --csv '<出力先>' --csvf evtx.csv
```
