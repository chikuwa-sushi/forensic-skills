---
name: view-vhdx
description: WSL の ext4.vhdx などの VHDX の中身を、7-Zip で手早く確認する(ファイル一覧の CSV 化、テキストファイルの閲覧、ファイルの取り出し)。マウントせずに Linux 側のファイルを見たいときに使う。
---

# VHDX の中身を 7-Zip で見る

共通手順: `docs/parse-common.md`

- ツール: 7-Zip(`.env` の `SEVENZIP`。`setup.ps1` が `tools\7zip` に置く。単体版の `7za.exe` は VHDX / ext4 に対応していないので使わない)
- 入力: `ext4.vhdx` など。場所は `%LOCALAPPDATA%\Packages\<ディストリ>\LocalState\`、`%LOCALAPPDATA%\wsl\{GUID}\`、Docker Desktop は `%LOCALAPPDATA%\Docker\wsl\` 配下
- 出力名: `vhdx`(複数の VHDX を扱うときは `vhdx_<ディストリ名>` のように分ける)
- 7-Zip は VHDX を読むだけで変更しない。ジャーナルのリプレイもしない。

## 進め方

- **見たいファイルのパスが分かっている**: 一覧は取らず、手順 2(ファイルの取り出しなら手順 3)へ進む。
- **パスが分からない**: 手順 1 で一覧を取り、`Path` を確認してから手順 2 / 3 へ進む。

## 1. ファイル一覧を CSV にする(パスが不明なときだけ)

```powershell
$cfg = & .\scripts\Get-Config.ps1
$vhdx = '<ext4.vhdx のパス>'
$out = Join-Path $cfg.PARSED_DIR '<収集フォルダ名>\vhdx'
New-Item -ItemType Directory -Force $out | Out-Null
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$raw = @(& $cfg.SEVENZIP l -slt -sccUTF-8 $vhdx)
$code = $LASTEXITCODE
$raw | Set-Content (Join-Path $out 'list_raw.txt') -Encoding UTF8

# 7z の「Key = Value」形式の一覧を CSV 化（safe-read で読むため）
$start = [Array]::IndexOf([string[]]$raw, '----------')
$keys = 'Path','Folder','Size','Mode','Modified','Created','Accessed','iNode','User ID','Group ID','Symbolic Link'
$rows = New-Object Collections.Generic.List[object]
$cur = @{}
foreach ($l in @($raw[($start + 1)..($raw.Count - 1)]) + '') {
    $i = $l.IndexOf(' = ')
    if ($l -eq '' -and $cur['Path']) {
        $o = [ordered]@{}; foreach ($k in $keys) { $o[$k] = $cur[$k] }
        $rows.Add([pscustomobject]$o); $cur = @{}
    } elseif ($i -gt 0) { $cur[$l.Substring(0, $i)] = $l.Substring($i + 3) }
}
$rows | Export-Csv (Join-Path $out 'vhdx_files.csv') -NoTypeInformation -Encoding UTF8

# 空の結果を成功扱いにしない
if ($code -ge 2 -or $start -lt 0 -or $rows.Count -eq 0) {
    throw "7z list failed (exit=$code, rows=$($rows.Count)). See the 7-Zip error output above"
}
"exit=$code rows=$($rows.Count)"
```

- 終了コード 1 は警告。結果は使えるが、警告があったことを報告する。
- 「別のプロセスが使用中」で開けない場合は、その WSL が起動中。証拠ではなく稼働中の環境なら、停止してよいかユーザに確認する(勝手に `wsl --shutdown` しない)。
- 一覧が内側のイメージ 1 件(`*.img` など)だけで Linux のファイルが見えない場合は、推測で進めず報告して停止する。
- 読むときは `safe-read` スキル(`.\scripts\safe_read.ps1 -Path '<out>\vhdx_files.csv' -Match '<検索語>'`)。`Path` の区切りは `\`。

## 2. テキストファイルを見る

VHDX のルートからの相対パスを指定し、VHDX から直接 CSV(`Line`,`Text`)にする。テキストファイルにだけ使う。

```powershell
$cfg = & .\scripts\Get-Config.ps1
$vhdx = '<ext4.vhdx のパス>'
$out = Join-Path $cfg.PARSED_DIR '<収集フォルダ名>\vhdx'
$target = 'home\<ユーザ>\.bash_history'         # ルートからの相対パス
$target = $target.TrimStart('/', '\')           # 先頭に / があると一致しない
New-Item -ItemType Directory -Force $out | Out-Null
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$csv = Join-Path $out (($target -replace '[\\/:*?"<>|]', '_') + '.csv')
$n = 0
& $cfg.SEVENZIP e -so -bd -sccUTF-8 $vhdx $target |
    ForEach-Object { $n++; [pscustomobject]@{ Line = $n; Text = $_ } } |
    Export-Csv $csv -NoTypeInformation -Encoding UTF8
$code = $LASTEXITCODE
if ($code -ge 2) { throw "7z failed (exit=$code)" }
if ($n -eq 0) { throw "No lines read: path not found or file is empty ($target)" }
"exit=$code lines=$n csv=$csv"
```

- パスが存在しなくても 7-Zip は終了コード 0 で何も出力しない。上のエラーになったらパスを見直し、それでも分からなければ手順 1 で一覧を取る。

読むときは `safe-read` スキル(`.\scripts\safe_read.ps1 -Path '<csv>'`)。

## 3. ファイルを取り出す(必要なときだけ)

別のツールに渡すなど、ファイルそのものが必要なときに使う。取り出す範囲は絞る。

```powershell
$cfg = & .\scripts\Get-Config.ps1
$vhdx = '<ext4.vhdx のパス>'
$files = Join-Path $cfg.PARSED_DIR '<収集フォルダ名>\vhdx\files'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

& $cfg.SEVENZIP x $vhdx "-o$files" -aos -bd -sccUTF-8 'home\<ユーザ>\*' |
    Where-Object { $_ -match 'Everything|Files:|Folders:|ERROR|WARNING|Errors' }
"exit=$LASTEXITCODE"
```

- 管理者権限がないと、シンボリックリンクの作成で `Cannot create symbolic link` となり終了コードが 2 になる。他のファイルは取り出されるので、エラーがこれだけなら続行してよい。リンク先は一覧の `Symbolic Link` 列で分かる。
- 取り出したファイルは証拠データ。実行しない。テキストを読むときは手順 2 を使い、取り出し先を直接読まない。
- Linux で使えて Windows で使えないファイル名は、取り出し時に変更されることがある。正しいパスは一覧で確認する。

## 注意

- `Modified` / `Created` / `Accessed` は **7-Zip を実行した PC のローカルタイム**で表示される。報告するときはタイムゾーンを明記する。
- 見えるのは現存するファイルだけ。削除ファイルの復元やジャーナル解析はできない。必要なら TSK や Autopsy などの導入をユーザに提案する(自作パースはしない)。
- 同じコマンドに `PARSED_DIR` と読み取り系の語(`Get-Content`、`-Head` など)があると、Claude Code ではフックにブロックされる。`safe_read.ps1` に `-Head` は付けない。絞り込みは `-Match`、ページ送りは `-Skip` で行う。
