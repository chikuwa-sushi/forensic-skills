---
name: parse-mft
description: CDIR-Cで収集した$MFTをMFTECmdでCSVにパースする。ファイルの作成・変更履歴やタイムスタンプ改ざんを調べるときに使う。
---

# $MFTのパース

共通手順: `docs/parse-common.md`

- ツール: `MFTECMD`
- 入力: `$MFT`(`*MFT*` で検索)
- 出力名: `mft`

```powershell
$cfg = & .\scripts\Get-Config.ps1
& $cfg.MFTECMD -f '<$MFT>' --csv '<出力先>' --csvf mft.csv
```
