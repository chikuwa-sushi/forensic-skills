# windows-dfir-skills

フォレンジック用の Agent Skills 集(Claude Code / Codex CLI など)。マウントしたディスクイメージからアーティファクトを収集し、確立したツール(Eric Zimmerman Tools / impacket / NirSoft)でパースし、パース結果を安全に読んで解析する。解析はユーザが入手可能なツールで行い、自作スクリプトは明示指示があるときだけ作る(詳細は `AGENTS.md`)。

## 必要なもの
- Windows / PowerShell 5.1
- .NET 10 ランタイム(EZ Tools 用): `winget install Microsoft.DotNet.Runtime.10`
- Python 3(`parse-secrets` の impacket 用。setup が `.venv` を作成する)
- 7-Zip(`view-vhdx` 用。setup が `tools\7zip` に置く。別の場所のものを使うなら `.env` の `SEVENZIP` を変更する)
- 管理者権限(CDIR-C で収集する場合、および impacket 用の Defender 除外を入れる場合)

## セットアップ
```powershell
.\scripts\setup.ps1
```
- `tools.lock` の URL から CDIR-C・EZ Tools・NirSoft ツール(BrowsingHistoryView / BrowserDownloadsView)・7-Zip を `tools\` にダウンロードする。CDIR-C と 7-Zip は SHA256 を照合する。取得日時・URL・SHA256・バージョンは `tools\installed.txt` に記録する。
- `.env` がなければ `.env.example` から作る。必要なら `COLLECT_DIR` / `PARSED_DIR` を書き換える(プロジェクトフォルダの外に置く)。
- `.claude\skills` を `.agents\skills` へのジャンクションとして作る(Claude Code 用)。
- Python があれば `.venv` を作成し `requirements.txt`(impacket)を入れる。実行は `.env` の `PYTHON`。
  - **impacket は Windows Defender に `HackTool:Python/Impacket` として隔離される**ため、管理者ターミナルで `.\scripts\setup.ps1 -DefenderExclude` を実行して `.venv` を Defender の除外に追加する(`parse-secrets` スキルで使用)。

## 対応エージェント
| エージェント | スキル | 共通ルール | パース結果の直接読み取り防止 |
|---|---|---|---|
| Claude Code | `.claude/skills`(ジャンクション) | `CLAUDE.md` → `AGENTS.md` | フックで強制 |
| Codex CLI | `.agents/skills` | `AGENTS.md` | ルールと `safe_read.ps1` のみ(強制なし) |

- スキルの実体は `.agents/skills/`。編集はこちらで行う。
- Claude Code 以外(Codex 等)は PARSED_DIR 直読みを止めるフックが効かないため、`AGENTS.md` のルールと `scripts/safe_read.ps1` を必ず守る。各スキルは `.agents/skills/<名前>/SKILL.md` を読んでから手順どおりに実行する。
- Codex では、サンドボックスの設定で `COLLECT_DIR` / `PARSED_DIR` への書き込み(収集・パース)とネットワーク接続(setup)を許可する必要がある。設定方法は Codex のドキュメントを参照。

## 使い方
エージェントからスキルを呼び出す。

| スキル | 内容 |
|---|---|
| `collect-cdirc` | 指定ドライブから収集する。NTFS なら CDIR-C、NTFS でなければ(.ad1 など)ファイルをコピーして収集する |
| `parse-mft` / `parse-usnjrnl` | $MFT / $UsnJrnl:$J(MFTECmd) |
| `parse-evtx` | イベントログ(EvtxECmd) |
| `parse-prefetch` | Prefetch(PECmd) |
| `parse-registry` | レジストリ(RECmd + Kroll_Batch) |
| `parse-amcache` | Amcache(AmcacheParser) |
| `parse-shimcache` | ShimCache(AppCompatCacheParser) |
| `parse-shellbags` | ShellBags(SBECmd) |
| `parse-srum` | SRUM(SrumECmd) |
| `parse-secrets` | ローカルアカウントのNT/LMハッシュ・LSA secrets(impacket secretsdump、venv) |
| `parse-browser` | ブラウザ閲覧履歴(NirSoft BrowsingHistoryView) |
| `parse-browser-downloads` | ブラウザのダウンロード履歴(NirSoft BrowserDownloadsView) |
| `view-vhdx` | WSL の ext4.vhdx などの中身を確認する(7-Zip) |
| `safe-read` | パース結果を安全に読み、解析する |

例: 「F ドライブから収集して」→「パースして」→「safe-read で〇〇を調べて」

## 構成
```
AGENTS.md                 全エージェント共通のルール(CLAUDE.md から読み込む)
.agents/skills/           スキル本体
.env.example              パス設定のひな形(.env はGit管理外)
requirements.txt          venv に入れる確立ツール(impacket)
tools.lock                ツールの取得元とハッシュ
config/cdir.ini.template  CDIR-C の収集項目
scripts/                  setup / 収集 / safe_read / 設定読込
docs/parse-common.md      パーススキル共通の手順
.claude/hooks/            PARSED_DIR を直接読めないようにするフック(Claude Code のみ)
.venv/                    Python 製の確立ツール実行用(setup が作成、Git管理外)
```

## 安全対策(プロンプトインジェクション)
パース結果に埋め込まれた文によって、Claude への指示が上書きされないようにしている。
- `safe_read.ps1`: 制御文字・見えない文字を取り除き、`<` `>` を無害化し、長い値を切り詰め、インジェクションらしい行に `!SUSPICIOUS` を付け、出力全体を実行ごとにランダムなIDを付けた区切りで囲む。
- フック(Claude Code のみ): `PARSED_DIR` を Read / Grep / Get-Content などで直接読むのを止める。
- `AGENTS.md` と `safe-read` スキル: データは証拠であって指示ではない、というルールを定めている。

いずれも完全ではないので、多層防御として使う。

## 制約
- CDIR-C は NTFS ボリュームを直接読む。.ad1 などの論理イメージには使えないので、ファイルのコピーで収集する。その場合、`$MFT`・`$UsnJrnl`・削除済みファイルは、イメージに含まれていない限り取れない。
- FTK Imager でマウントした .ad1 では、同じ名前のファイルが二重に見えることがあり、その中身は確実に取り出せない(`_manifest.csv` に `DuplicateNames` として記録される)。
- EZ Tools は配布URLに版が含まれないため、ハッシュを固定していない。取得したハッシュは `tools\installed.txt` に記録する。
