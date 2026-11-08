---
name: parse-shellbags
description: CDIR-Cで収集したNTUSER.DAT/UsrClass.datのShellBagsをSBECmdでCSVにパースする。ユーザがフォルダにアクセスした履歴を調べるときに使う。
---

# ShellBagsのパース

共通手順: `docs/parse-common.md`

- ツール: `SBECMD`
- 入力: `NTUSER.DAT` / `UsrClass.dat` を含むフォルダ(ユーザごと)
- 出力名: `shellbags\<ユーザ名>`

```powershell
$cfg = & .\scripts\Get-Config.ps1
& $cfg.SBECMD -d '<ユーザのハイブフォルダ>' --csv '<出力先>'
```
