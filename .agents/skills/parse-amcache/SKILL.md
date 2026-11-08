---
name: parse-amcache
description: CDIR-Cで収集したAmcache.hveをAmcacheParserでCSVにパースする。実行ファイルの存在・実行痕跡とSHA1を調べるときに使う。
---

# Amcacheのパース

共通手順: `docs/parse-common.md`

- ツール: `AMCACHEPARSER`
- 入力: `Amcache.hve`
- 出力名: `amcache`

```powershell
$cfg = & .\scripts\Get-Config.ps1
& $cfg.AMCACHEPARSER -f '<Amcache.hve>' --csv '<出力先>' -i
```
