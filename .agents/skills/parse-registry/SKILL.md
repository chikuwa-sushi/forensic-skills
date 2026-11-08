---
name: parse-registry
description: CDIR-Cで収集したレジストリハイブ(SAM/SECURITY/SOFTWARE/SYSTEM/NTUSER.DAT/UsrClass.dat)を、RECmdとバッチファイルでCSVにパースする。永続化、ユーザ操作、システム設定を調べるときに使う。
---

# レジストリのパース

共通手順: `docs/parse-common.md`

- ツール: `RECMD`、バッチファイル `RECMD_BATCH`
- 入力: 収集フォルダ(ハイブはサブフォルダも含めて検索される)
- 出力名: `registry`

```powershell
$cfg = & .\scripts\Get-Config.ps1
& $cfg.RECMD -d '<収集フォルダ>' --bn $cfg.RECMD_BATCH --csv '<出力先>' --csvf registry.csv
```

- ハイブがダーティでトランザクションログがないと失敗する。その場合は `--nl` を付けて再実行し、付けたことを報告する。
