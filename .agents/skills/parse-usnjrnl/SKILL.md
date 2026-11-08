---
name: parse-usnjrnl
description: CDIR-Cで収集した$UsnJrnl:$JをMFTECmdでCSVにパースする。ファイルの作成・削除・リネーム履歴を調べるときに使う。
---

# $UsnJrnl:$Jのパース

共通手順: `docs/parse-common.md`

- ツール: `MFTECMD`
- 入力: `$J`(`*UsnJrnl*` または `*$J*` で検索)。親パス解決のため同じ収集フォルダの `$MFT` も使う。
- 出力名: `usnjrnl`

```powershell
$cfg = & .\scripts\Get-Config.ps1
& $cfg.MFTECMD -f '<$J>' -m '<$MFT>' --csv '<出力先>' --csvf usnjrnl.csv
```
