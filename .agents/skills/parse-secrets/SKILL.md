---
name: parse-secrets
description: 収集したSAM/SYSTEM(必要ならSECURITY)から、ローカルアカウントのNT/LMハッシュとLSA secretsをimpacket secretsdumpで抽出する。ローカルユーザのパスワードハッシュやキャッシュ資格情報を調べるときに使う。
---

# ローカルアカウントのハッシュ / LSA secrets 抽出

共通手順: `docs/parse-common.md`

- ツール: impacket `secretsdump`(Python。`.env` の `PYTHON`(= `.venv\Scripts\python.exe`)で実行。`requirements.txt` で導入)
- 入力: 収集フォルダ内の `SAM` と `SYSTEM`。キャッシュ資格情報/LSA secrets も見るなら `SECURITY` も。
- 出力名: `secrets`

```powershell
$cfg = & .\scripts\Get-Config.ps1
$sam = '<収集フォルダ>\...\SAM'; $sys = '<収集フォルダ>\...\SYSTEM'
$out = Join-Path $cfg.PARSED_DIR '<収集フォルダ名>\secrets'
New-Item -ItemType Directory -Force $out | Out-Null

# secretsdump をオフラインモードで実行（管理者権限は不要。ハイブは読むだけ）
# 実行するのは venv の Scripts\secretsdump.py（コマンド本体）。
# `-m impacket.examples.secretsdump` はライブラリなので、何も出力せず終了コード 0 で終わる。使わない。
$sd = Join-Path (Split-Path $cfg.PYTHON) 'secretsdump.py'
if (-not (Test-Path -LiteralPath $sd)) { throw "secretsdump.py not found: $sd (run scripts\setup.ps1)" }
$env:PYTHONWARNINGS = 'ignore::UserWarning'   # pkg_resources の非推奨警告を抑える
$raw = & $cfg.PYTHON $sd -sam $sam -system $sys LOCAL 2>&1
$code = $LASTEXITCODE
$raw | Set-Content (Join-Path $out 'secretsdump_raw.txt') -Encoding UTF8   # 生ログ

# user:rid:lmhash:nthash::: を CSV 化（safe-read で読むため）
$rows = @($raw |
  Where-Object { $_ -match '^[^:]+:\d+:[0-9a-fA-F]{32}:[0-9a-fA-F]{32}:::' } |
  ForEach-Object { $p = $_ -split ':'; [pscustomobject]@{ Account=$p[0]; RID=$p[1]; LMHash=$p[2]; NTHash=$p[3] } })
$rows | Export-Csv (Join-Path $out 'secrets.csv') -NoTypeInformation -Encoding UTF8

# 空の結果を成功扱いにしない
if ($code -ne 0 -or $rows.Count -eq 0) {
    throw "secretsdump failed (exit=$code, hash_rows=$($rows.Count)). Read secretsdump_raw.txt with safe_read.ps1"
}
"exit=$code hash_rows=$($rows.Count)"
```

- 失敗したら(終了コードが 0 以外か、ハッシュ行が 0 件)、`secretsdump_raw.txt` を `safe_read.ps1` で読んで原因を報告し、停止する。SAM にはビルトインアカウントが必ずあるので、ハッシュ行が 0 件なら正常な結果ではない。
- `No module named 'pkg_resources'` で失敗した場合は、setuptools が 81 以降になっている。`requirements.txt` の固定バージョン(`setuptools==80.9.0`)を `pip install -r requirements.txt` で入れ直す。

- LSA secrets / キャッシュ資格情報も取るなら `-security '<SECURITY>'` を足す(出力は `secretsdump_raw.txt` 側に出る)。
- impacket が未導入(Windows Defender が `HackTool:Python/Impacket` として隔離)の場合は、管理者ターミナルで `.\scripts\setup.ps1 -DefenderExclude`(`.venv` を Defender の除外に追加)してから入れる。
- 出力は `secrets.csv`(Account/RID/LMHash/NTHash)と `secretsdump_raw.txt`。**中身は読まない。読むときは `safe-read` スキル**(`.\scripts\safe_read.ps1 -Path '<out>\secrets.csv' -Schema`)。
- 空パスワードの NT ハッシュは `31d6cfe0d16ae931b73c59d7e0c089c0`、空 LM は `aad3b435b51404eeaad3b435b51404ee`。
