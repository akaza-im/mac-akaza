# スリープ復帰後に変換できなくなる問題 — 調査ノート

> mac-akaza で最も深刻かつ再発を繰り返しているバグ。本ドキュメントに経緯・証拠・仮説・次の一手を集約する。
>
> 最終更新: 2026-06-15

## 1. 症状

macOS をスリープ→復帰すると、しばらくして（あるいは即座に）mac-akaza で日本語変換ができなくなる。
プロセスは生きているのに入力が通らない／変換が効かない状態になる。これまで複数回の修正を重ねたが**完全には解消していない**。

ユーザーの観察（2026-06-15）:
> 「OS と Swift プロセスの間の通信がうまくいっていないように見える」

→ akaza-server とのパイプ（Swift ↔ Rust）ではなく、**IMKit レイヤー（OS ↔ Swift IME プロセス）** の通信を疑うべき、という指摘。

## 2. アーキテクチャ（関連箇所）

2 段の通信経路がある。スリープ復帰問題はこのどちらか（または両方）で起きうる。

```
[アプリ] ──IMKit(XPC/Mach)──> [AkazaIME (Swift)] ──pipe(JSON-RPC)──> [akaza-server (Rust)]
          ↑ 経路A: OS↔Swift                      ↑ 経路B: Swift↔Rust
```

- 経路A: `IMKServer` / `IMKInputController`。OS がキーイベントを Swift に渡し、Swift が `insertText` / `setMarkedText` で結果を返す。
- 経路B: `AkazaServerProcess`（プロセス管理）+ `JSONRPCClient`（stdin/stdout パイプ）。

主なソース:
- `Sources/AkazaIME/main.swift` — エントリポイント。`IMKServer` 生成、`didWakeNotification` 監視、stderr を `~/Library/Logs/AkazaIME/akaza.log` にリダイレクト。
- `Sources/AkazaIME/AkazaServerProcess.swift` — akaza-server の起動/再起動/終了、指数バックオフ、`terminationHandler`。
- `Sources/AkazaIME/JSONRPCClient.swift` — JSON-RPC、リーダーループ（背景キューで `availableData` を読む）。
- `akaza-server/src/main.rs` — stdin を1行ずつ読み、変換して stdout に返す。

## 3. これまでの修正履歴（経路B 中心に対症療法を重ねてきた）

| commit | PR | 内容 |
|---|---|---|
| `7109da8` | #92 | **元の修正**。(1) `InputMethodConnectionName` をバンドルIDベース（`..._Connection`）に変更（macOS 13.4+ で復帰時に接続名が自動置換され IME が disabled になる問題への対処）。(2) `didWakeNotification` で akaza-server を再起動しパイプを張り直す。 |
| `a33f978` | #80 | akaza-server クラッシュ時の SIGPIPE で IME プロセスが落ちるのを抑止（`signal(SIGPIPE, SIG_IGN)`）。 |
| `8d78037` | #83 | 再起動バックオフ上限を 60s→15s に短縮。 |
| `43771c5` | — | 変換リクエストを非同期化しメインスレッドのブロックを解消。 |
| `c4a625b` | #101 | スリープ復帰時に `restart()` と `terminationHandler` が競合し akaza-server が二重起動するのを修正（`DispatchWorkItem` でキャンセル可能化 + `process === terminatedProcess` ガード）。 |

→ 経路B（パイプ／プロセス管理）はかなり堅牢化された。**しかし症状は再発しており、残る容疑は経路A（IMKit）に移っている。**

## 4. 2026-06-15 の調査で確認した事実

環境: macOS 26.5.1 (Build 25F80)、非サンドボックス配布。

- クラッシュレポート（`.ips` / `.diag`）に akaza 関連は**無し** → クラッシュではない。
- 復帰時のサーバー再起動は**ログ上クリーン**:
  ```
  07:17:25.568 wake from sleep — restarting akaza-server
  07:17:25.628 akaza-server terminated with status 15   ← SIGTERM
  07:17:25.658 akaza-server started (pid=74596)
  ```
- akaza-server バイナリ単体は**正常に変換できる**（モデルも正常）。
- 復帰後も AkazaIME の `handle()` は呼ばれている（`07:18:23` に keyCode ログあり）→ **IMKit が完全 disabled にはなっていない**ケースだった。
- `akaza.log` 全期間で `timed out` / `failed to write` / `JSON-RPC error` / `failed to decode` は**ゼロ件** → 経路B のエラーは出ていない。
- `~/Library/Logs/AkazaIME/akaza.log` に過去のスリープ復帰が多数記録されており、**毎回 `terminated with status 15`**（= SIGTERM で強制終了、後述）。
- 復帰直後に「`Loaded 308 romaji mappings`」（= `AkazaInputController` の生成／romkan リロード）が**数秒おきに頻発**。XPC ログでも peer プロセスの `invalidated because the client process exited` が反復。→ 経路A 側の不安定さを示唆。

**重要な性質: wedge は「サイレント」。両プロセス生存・サーバー応答可・キー入力は届く・エラーログ皆無、なのに変換結果がユーザーに反映されない。現状のログでは原因が捕捉できない。**

**決定的事実（2026-06-15 追記）: `killall AkazaIME`（Swift プロセスを丸ごと再起動）しても回復しない。**
→ 壊れた状態は Swift プロセスのメモリ内ではなく、**OS 側（IMKit / HIToolbox の接続レジストリ）に存在する**。Swift を再起動しても、OS がルーティングしてくれない接続名で再登録されるだけ、と考えると整合する。これは既知 IMKit バグの「リブートするまで disabled のまま」という記述とも一致。**この事実だけで、Swift プロセス内に閉じた仮説（H2/H3）は除外され、原因は経路A に絞り込まれる。**

### ログ確認の落とし穴（次回のため）

- zsh では `log` がエイリアス/関数で潰れていることがある。**`/usr/bin/log` をフルパスで**使うこと。
- akaza-server の stderr は親（AkazaIME）の stderr にリダイレクトされ、`~/Library/Logs/AkazaIME/akaza.log` に集約される。unified logging には出ない。**このファイルが第一級の証拠源。**

## 5. ウェブ調査: IMKit の既知問題（経路A）

- **接続名の自動置換バグ**: 「まれに（多くはラップトップ復帰後、macOS 13.4 Ventura）、システムが指定した接続名を破棄し `$(PRODUCT_BUNDLE_IDENTIFIER)_Connection` で接続し直す。結果としてサンドボックスに拒否されうる」。IME がメニューで**グレーアウト（disabled）し、リブートするまで回復しない**。
- 推奨対処は `InputMethodConnectionName` を `..._Connection` にすること。**→ mac-akaza は既に適用済み**（`Info.plist`）。非サンドボックスなのでサンドボックス拒否の経路は該当しないが、接続名の自動置換そのものは依然起こりうる。
- **専門家も「既に壊れた状態からのソフトウェア的回復手段は提示していない」**（=リブート or IME 再選択が唯一の回復）。
- スレッド要件: `IMKInputController` の API は MainActor で動く。client への `insertText` / `setMarkedText` のみ MainActor 上で非同期実行が許容される（裏を返すとこの2つはブロッキングしうる重い操作）。

出典:
- [Let's talk about what InputMethodKit needs to improve (gist, ShikiSuen)](https://gist.github.com/ShikiSuen/73b7a55526c9fadd2da2a16d94ec5b49)
- [macOS Input Method Development Guidelines for 2026 (Medium, Shiki Suen)](https://shikisuen.medium.com/macos-input-method-development-guidelines-for-2026-5123461fa53b)
- [InputMethodKit — Apple Developer Forums](https://developer.apple.com/forums/tags/inputmethodkit)

## 6. 原因の仮説（確度順）

### H1（最有力・`killall` 無効により裏付け）: 経路A の IMKit 接続が復帰時に OS 側で壊れる
ユーザーの直感（OS↔Swift 通信）と既知の接続名置換バグに合致し、かつ **`killall` で回復しない**事実が決定打。壊れた状態は OS 側にあるため、Swift プロセスを再起動しても回復しない。`handle()` が呼ばれても `client`（`IMKTextInput`）への `insertText` / `setMarkedText` がサイレントに無視される、あるいは OS が AkazaIME へイベント／応答をルーティングしなくなっている可能性。
- 検証案:
  - 復帰前後で OS の入力ソース登録状態を確認（`defaults read com.apple.HIToolbox`、接続名が `..._Connection` のまま維持されているか）。
  - 復帰後に `client.bundleIdentifier()` 等が応答するか、`insertText` の前後でログ。`insertText` 前に `responds(to:)` チェック（2026 ガイドライン推奨）。
  - 回復する操作を切り分け（入力ソース再選択／キーボード削除再追加／再ログイン／リブート）→ どのレイヤーをリセットすれば直るかで原因レイヤーが特定できる。

### H2（`killall` 無効により除外）: ~~`restart()` がメインスレッドをブロックする~~
`AkazaServerProcess.restart()` の `process?.waitUntilExit()`（`AkazaServerProcess.swift:161`）はメインスレッドを同期ブロックしうるが、これは Swift プロセス内の問題なので **`killall` で回復するはず → 観測（回復しない）と矛盾するため wedge の主因ではない**。ただしフリーズ要因として別途修正の価値はある。

### H3（`killall` 無効により除外）: ~~リーダーループのリーク／競合~~
`startReaderLoop()` のリーク（古いループが Foundation `Pipe` の write 端 fd 保持で EOF せず残り、遅れて `failAllPending()` を呼ぶ）も Swift プロセス内の問題なので **`killall` で回復するはず → 主因ではない**。コード衛生上の改善対象ではある。

### H4（副次バグ、wedge とは別）: 復帰時に学習データが消える
`terminated with status 15` = akaza-server は SIGTERM **ハンドラを持たず**強制終了している。`main.rs:134` の `handler.flush_learn()`（シャットダウン時 flush）は stdin EOF 経由の正常終了でしか到達しない。**毎回のスリープ復帰で、直近最大5分ぶんの学習が失われている。**
- 対処案: akaza-server に SIGTERM ハンドラを入れて flush してから exit する。あるいは Swift 側で terminate 前に stdin を閉じて正常終了させる。

## 7. 次の一手

`killall` で回復しない＝原因は OS 側（経路A）に確定的に絞られた。現状のログでは silent wedge を捕捉できないため、**まず計測を仕込み、次に「何をすれば回復するか」を切り分けて壊れているレイヤーを特定する**。

1. **回復操作の切り分け（最優先・低コスト）** — wedge 状態で以下を順に試し、どれで直るか記録する。これで壊れているレイヤーが一意に絞れる。
   - (a) 入力ソースを別 IME に切替→Akaza に戻す
   - (b) システム設定で Akaza を削除→再追加
   - (c) 再ログイン
   - (d) リブート
   - → (a) で直れば IMKit のアクティベーション、(b)〜で直れば接続レジストリ、(d) のみなら最も深いレイヤー。
2. **診断ログの追加（経路A 重点）**
   - `activateServer` / `deactivateServer` / `handle` 呼び出しと、その時の `client` 情報・接続名をログ。
   - 変換の往復（convert 送信 → 応答 → `setMarkedText` 実行）に相関IDを振り、`setMarkedText`/`insertText` が実際に効いているかを追跡。
   - `insertText` 前に `client.responds(to:)` をチェックしログ（2026 ガイドライン推奨）。
3. **再現手順の確立** — `pmset sleepnow` でスリープ/復帰を繰り返し wedge を再現させる。
4. **経路A の堅牢化を試す** — 復帰時に `IMKServer` を作り直せるか、OS への再登録ができるか調査。
5. **副次の H4 修正** — SIGTERM での graceful flush（学習データ消失対策、wedge とは独立に有益）。

## 8. 投入した計測（2026-06-15）と次回 wedge 時の読み方

`killall` で直らない＝原因は OS 側（経路A）に絞られたが、現状のログでは「往路（OS→IME のキーイベント配送）」と「復路（IME→アプリへの `insertText`/`setMarkedText`）」のどちらが断たれているか確定できない。これを次回発生時に一発で切り分けるため、経路A に計測ログを仕込んだ（ブランチ `debug/path-a-wake-logging`）。

実装: `Sources/AkazaIME/AkazaInputController+Diagnostics.swift`（新規）。全ログに `[diag]` を付与。**キー内容（keyCode/characters）はキーロガー化を避けるため一切記録しない**（`handle()` の既存ログも内容を出さない形に変更済み）。

ログ種別:
| ログ | 意味 | 出る＝ |
|---|---|---|
| `controller init id=N ...` / `deinit id=N` | コントローラ生成/破棄 | 復帰後にこれが**数秒おきに頻発**＝経路A のセッションがチャーン |
| `activateServer id=N ...` | OS がこのコントローラを活性化 | OS↔IME の接続確立。**復帰後に出ない**なら OS が IME を選んでいない |
| `handle id=N client=... ptr=... insert=t/f mark=t/f` | **往路**: キーイベントが届いた | **wedge 中にこれが出ない → 往路が断**（OS がイベントを配送していない） |
| `insertText id=N ctx=... client=... ptr=...` | **復路**: 確定テキスト送出を試行 | wedge 中にこれが**出るのに画面に出ない → 復路が断**（OS がアプリに渡していない） |
| `setMarkedText id=N ctx=... ...` | **復路**: preedit 送出を試行 | 同上 |
| `convert completion dropped — ...` | 変換応答が返ったが反映されず破棄 | controller 解放/状態変化による**サイレントドロップ**（in-process 原因の検出） |

`client=` のバンドルID・`ptr=`（client オブジェクトのポインタ）・`insert=/mark=`（復路セレクタへの応答性）で、**復帰前後で client が入れ替わる／応答しなくなる**ことを検出できる。

### 次回 wedge が起きたら（手順）
1. wedge 状態で適当にキーを打ち、`/usr/bin/log show --last 5m --predicate 'process CONTAINS "Akaza"' --style compact`（または `~/Library/Logs/AkazaIME/akaza.log`）で `[diag]` 行を確認。
2. 判定:
   - **`handle` が出ない** → 往路が断。OS がイベントを配送していない＝最も深い OS 側破損。対策は入力ソース再登録系。
   - **`handle` は出るが `insertText`/`setMarkedText` が出ない** → IME 内部のロジック分岐で止まっている（in-process）。`convert completion dropped` の有無を見る。
   - **`insertText`/`setMarkedText` は出るのに画面に反映されない** → 復路が断。client（`ptr`）が復帰前と変わっている／`insert=false` なら client が応答していない。
   - **`controller init` が頻発** → セッションチャーン。`activateServer` がどの id に来ているかと突き合わせる。
3. 判定結果を §6 の仮説に反映し、初めて「当てずっぽうでない対策」を実装する。

> この計測は原因特定後に削除する一時コード（全行 `[diag]`）。

## 付録: 即時回復手段（ユーザー向け）

壊れた状態からの回復は、既知の IMKit バグ上は**ソフトウェア的手段が乏しい**。
- **`killall AkazaIME` は回復手段にならない（確認済み, 2026-06-15）。** 壊れた状態が OS 側にあるため、Swift プロセスを再起動しても直らない。
- 試す価値があるのは（どれで直るかは未確認 = §7 の切り分け対象）: 入力ソースの再選択／システム設定で Akaza を削除→再追加／再ログイン／リブート。
