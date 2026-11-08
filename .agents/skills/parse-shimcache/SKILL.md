---
name: parse-shimcache
description: CDIR-Cで収集したSYSTEMハイブのAppCompatCache(ShimCache)をAppCompatCacheParserでCSVにパースする。実行ファイルの存在痕跡を調べるときに使う。
---

# ShimCacheのパース

共通手順: `docs/parse-common.md`

- ツール: `APPCOMPATCACHEPARSER`
- 入力: `SYSTEM` ハイブ
- 出力名: `shimcache`

```powershell
$cfg = & .\scripts\Get-Config.ps1
& $cfg.APPCOMPATCACHEPARSER -f '<SYSTEM>' --csv '<出力先>' --csvf shimcache.csv
```
