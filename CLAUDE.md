# mac-akaza

## プロジェクト概要

macOS 用日本語 IME。Swift (InputMethodKit) フロントエンド + Rust (akaza-server) バックエンドの 2 プロセス構成。

## アーキテクチャ

- **Swift Frontend**: InputMethodKit IME。キー入力処理、ローマ字→かな変換、候補ウィンドウ UI、akaza-server プロセス管理
- **akaza-server (Rust)**: libakaza を利用したかな漢字変換エンジン。JSON-RPC over stdin/stdout で通信
- **通信**: JSON-RPC 2.0、1行1メッセージ（改行区切り）
- **自動再起動**: akaza-server が異常終了した場合、Swift 側で自動再起動（指数バックオフ付き）

## ビルド・実行

- Swift 部分: Xcode プロジェクト (`AkazaIME.xcodeproj`) でビルド
- Rust 部分 (akaza-server): `cargo build --release`
- インストール先: `~/Library/Input Methods/Akaza.app`
- モデルデータ: `Contents/Resources/model/` に配置（akaza-default-model の GitHub Releases からダウンロード）

## コーディング規約

- Swift コードは Swift 標準のコーディングスタイルに従う
- Rust コードは `cargo fmt` / `cargo clippy` に従う
- InputMethodKit の API では preedit のことを MarkedText と呼ぶ

## ディレクトリ構成

```
AkazaIME/          # Swift IME フロントエンド
akaza-server/      # Rust JSON-RPC サーバー (将来追加)
Resources/         # アイコン等のリソース
```

## 重要な注意事項

- InputMethodKit の IME は `~/Library/Input Methods/` にインストールする必要がある
- IME のデバッグは難しい。変更後はシステム環境設定からキーボードを一度削除して再追加するか、`killall AkazaIME` してから再起動する必要がある場合がある
- akaza-server との通信は非同期で行い、UI スレッドをブロックしないこと
- akaza-server のクラッシュに備え、変換リクエストのタイムアウトを設定すること

### 既知の問題: macOS ディスク書き込み制限による強制終了

macOS は 1 プロセスのディスク書き込み量を 86400 秒あたり約 2147 MB（約 24.86 KB/s）に制限しており、超過すると OS がプロセスを強制終了する。

**原因**: `learn` リクエスト（変換確定のたびに発火）で `write_user_files()` を毎回呼ぶと、unigram/bigram/skip-bigram の 3 ファイル（合計 ~1.5 MB）を毎回 AES 暗号化してフルで書き直すため、長時間使用で制限を超える。

**対処**: `akaza-server/src/handler.rs` の `handle_learn` は 5 分に 1 回だけ書き込み、シャットダウン時に必ず flush する実装になっている（`FLUSH_INTERVAL = 300s`）。60 秒では 24 時間フル稼働時に制限ギリギリになるため 5 分を選択。

## ログ・クラッシュ調査手順

### 1. クラッシュレポートを確認する

```sh
# ユーザークラッシュレポート
ls ~/Library/Logs/DiagnosticReports/ | grep -iE "akaza|Akaza"

# システムクラッシュレポート（強制終了・リソース超過含む）
ls /Library/Logs/DiagnosticReports/ | grep -iE "akaza|Akaza"
```

ファイル拡張子の見方:
- `.ips` — クラッシュ（Segfault 等）
- `.diag` — リソース超過による強制終了（disk writes, CPU, memory）

`.diag` の `Event:` 行で何が原因かわかる（例: `disk writes`）。

### 2. プロセス稼働状況を確認する

```sh
ps aux | grep -i akaza | grep -v grep
```

### 3. AkazaIME の NSLog を確認する

```sh
# 直近 1 時間
log show --last 1h --predicate 'process CONTAINS "Akaza"' --style compact

# リアルタイム監視
log stream --predicate 'process CONTAINS "Akaza"' --style compact
```

akaza-server は stderr にログを出力している（`env_logger`）。
Swift 側の NSLog は unified logging に流れる。

### 4. akaza-server の stderr をリアルタイムで見る

akaza-server 単体を起動して直接 stderr を確認する。

```sh
MODEL="$HOME/Library/Input Methods/Akaza.app/Contents/Resources/model"
SERVER="$HOME/Library/Input Methods/Akaza.app/Contents/MacOS/akaza-server"
"$SERVER" "$MODEL" 2>&1 >/dev/null
```

## バージョンアップ手順

akaza ライブラリとモデルを新しいバージョン（例: `vYYYY.MMD.0`）に更新する場合、以下の 2 ファイルを修正する。

1. `akaza-server/Cargo.toml` の `libakaza` タグを更新
   ```toml
   libakaza = { git = "https://github.com/akaza-im/akaza.git", tag = "vYYYY.MMD.0" }
   ```

2. `Makefile` の `MODEL_VERSION` を更新
   ```makefile
   MODEL_VERSION = vYYYY.MMD.0
   ```

3. `Cargo.lock` を更新
   ```sh
   cargo update -p libakaza
   ```

## 誤変換の調査手順

誤変換の報告を受けた場合、以下の手順で原因を特定する。

### 1. akaza-server に直接変換リクエストを送る

インストール済みのモデルとビルド済みバイナリを使い、JSON-RPC で変換結果を確認する。

```sh
MODEL="/Users/$(whoami)/Library/Input Methods/Akaza.app/Contents/Resources/model"
SERVER="/path/to/mac-akaza/target/release/akaza-server"

# convert: Viterbi 最良パス（実際に変換されるもの）
printf '{"jsonrpc":"2.0","id":1,"method":"convert","params":{"yomi":"あらいだそう"}}\n' \
  | "$SERVER" "$MODEL" 2>/dev/null

# convert_k_best: 上位 k パス（サジェスト候補）
printf '{"jsonrpc":"2.0","id":1,"method":"convert_k_best","params":{"yomi":"あらいだそう","k":5}}\n' \
  | "$SERVER" "$MODEL" 2>/dev/null
```

結果の各文節には複数の候補が含まれる。変換モードで Space を押すと候補を順に辿れる。

### 2. 文節境界を強制した変換で仮説を検証する

誤変換の原因が文節分割の失敗である場合、`force_ranges` で境界を固定して正解候補が存在するか確認する。
`force_ranges` の値は **UTF-8 バイトオフセット** で指定する（ひらがな 1 文字 = 3 バイト）。

```sh
# 例: "あらいだそう"(18バイト) を "あらいだそ"(15バイト) + "う"(3バイト) に分割
printf '{"jsonrpc":"2.0","id":1,"method":"convert","params":{"yomi":"あらいだそう","force_ranges":[[0,15],[15,18]]}}\n' \
  | "$SERVER" "$MODEL" 2>/dev/null
```

force_ranges で正解が得られた場合、問題は **Viterbi のスコアリング** にある（セグメント自体は辞書に存在するが、別の分割の方がコストが低い）。

### 3. 部分文字列の単体変換で辞書エントリを確認する

文節候補に正解が含まれているかを確認する。

```sh
for yomi in あらいだ あらいだす あらいだそ あらいだそう; do
  printf '{"jsonrpc":"2.0","id":1,"method":"convert","params":{"yomi":"'"$yomi"'"}}\n' \
    | "$SERVER" "$MODEL" 2>/dev/null
done
```

- 部分文字列の単体変換で正解が出る → 辞書エントリは存在する → スコアリング問題
- 単体変換でも出ない → 辞書エントリが欠落 → akaza-default-model への辞書追加が必要

### 4. SKK-JISYO.L の該当エントリを確認する

```sh
grep "^あらいだ" ~/.local/share/akaza/SKK-JISYO.L
```

### 5. 原因の分類と対処

| 原因 | 対処 |
|---|---|
| 辞書エントリが欠落 | akaza-default-model に追加 |
| エントリはあるが分割スコアが不利 | libakaza のコストモデル改善、または akaza-default-model に活用形エントリを追加 |
| ユーザー辞書で補完可能 | 設定画面の「ユーザー辞書」タブで登録 |

なお、変換モードで **Shift+Right / Shift+Left** を押すと文節境界を 1 文字単位で伸縮できる。
force_ranges での検証で正解が出た場合、ユーザーはこの操作で回避可能。

## 関連リポジトリ

- [akaza](https://github.com/akaza-im/akaza) - Rust 製かな漢字変換エンジン (コアライブラリ libakaza)
- [akaza-default-model](https://github.com/akaza-im/akaza-default-model) - デフォルト言語モデル (~151MB)

## 重要: libakaza / akaza-default-model は同じ作者のリポジトリ

mac-akaza、libakaza、akaza-default-model はすべて同じ作者が管理しているリポジトリである。
問題の原因が libakaza や akaza-default-model にある場合、「upstream に報告する」「依頼する」という発想は誤り。
該当リポジトリのコードを直接調査・修正する方針で動くこと。

libakaza のソースは https://github.com/akaza-im/akaza/ にある（ローカルでは `additionalWorkingDirectories` として設定済み）。
