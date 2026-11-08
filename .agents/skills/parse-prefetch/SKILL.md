---
name: parse-prefetch
description: CDIR-Cで収集したPrefetch(*.pf)をPECmdでCSVにパースする。プログラムの実行履歴を調べるときに使う。
---

# Prefetchのパース

共通手順: `docs/parse-common.md`

- ツール: `PECMD`
- 入力: `*.pf` を含むフォルダ
- 出力名: `prefetch`

```powershell
$cfg = & .\scripts\Get-Config.ps1
& $cfg.PECMD -d '<Prefetchフォルダ>' --csv '<出力先>' --csvf prefetch.csv -q
```
