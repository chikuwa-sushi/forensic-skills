---
name: collect-cdirc
description: ユーザが指定したドライブにマウントされたディスクイメージから、CDIR-Cでフォレンジックアーティファクトを収集する。NTFSでない場合(.ad1などの論理イメージ)はファイルコピーで収集する。
---

# CDIR-Cによる収集

## 設定
- `.env`: `CDIRC_PATH`, `COLLECT_DIR`
- 収集項目: `config/cdir.ini.template`(`{TARGET}` `{OUTPUT}` はスクリプトが置換)

## 注意
- イメージは読み取り専用でマウントする。
- `tools/cdir-collector` の cdir.ini は使わない・変更しない。スクリプトが作業フォルダにコピーして実行する。
- ツールがなければ `.\scripts\setup.ps1` を案内する。

## 手順
1. 対象ドライブ文字をユーザに確認する(未指定なら聞く)。
2. 実行する。
   ```powershell
   .\scripts\Invoke-Cdirc.ps1 -Drive F:
   ```
   - NTFSならCDIR-Cで収集する。管理者権限が必要。権限エラーなら、ユーザに管理者ターミナルで同じコマンドを実行してもらう。
   - NTFSでなければ(`mode=logical`)、`Invoke-LogicalCollect.ps1` でファイルをコピーして収集する。管理者権限は不要。
3. 結果を確認する。
   - CDIR-C: `system_hash_match=False` なら、対象ドライブ以外を収集した可能性がある。報告して停止する。
   - logical:
     - `root_candidates`(終了コード3): 候補をユーザに示し、`-Root '<パス>'` を付けて再実行する。
     - `missing` の項目: イメージに含まれていない。一覧にして報告する。
     - `usnjrnl_J_stream=False`: `$J` がコピーできていない。FTK Imagerでのエクスポートを案内する。
     - `hash_mismatch` が1以上: 報告して停止する。
     - 削除済みファイルは収集できないことを伝える。
4. 収集フォルダのパスと、収集されたアーティファクトの種類を報告する。
   - フォルダ名は `<コンピュータ名>_<ドライブ文字>_<日時>`(logicalは末尾に `_logical`)。コンピュータ名は解析端末のもの。
   - 収集フォルダの隣に記録が残る。
     - CDIR-C: `_cdir.ini`(使用した設定)、`_hashes.csv`
     - logical: `_manifest.csv`(有無)、`_hashes.csv`(元とコピーのSHA256)、`_robocopy.log`
