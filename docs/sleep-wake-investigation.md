# スリープ復帰後に変換できなくなる問題 — 調査ノート

> mac-akaza で最も深刻かつ再発を繰り返しているバグ。本ドキュメントに経緯・証拠・仮説・次の一手を集約する。
>
> 最終更新: 2026-07-13
>
> **【解決 2026-07-13】根本原因は Secure Event Input の解放漏れと確定した。§11 を参照。**
> IME 側のバグではなく、他プロセス（今回は ghostty）が Secure Keyboard Entry を
> 有効化したまま解放しないことで、OS がキーイベントを IME に配送しなくなる仕様動作だった。

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

## 9. 原因確定（2026-06-22）: 往路（OS→IME のキーイベント配送）の断

§8 の計測を入れたビルドで wedge が再発（土日 6/20-21 を挟んだ 6/22 09:15 の wake 後）。`~/Library/Logs/AkazaIME/akaza.log` の `[diag]` ログで**原因が確定した**。

決定的な観測:
| 事実 | 値 |
|---|---|
| 最後に `handle`（往路）が呼ばれた時刻 | **2026-06-19 19:18:26**（wake 前・金曜夜） |
| 6/22 09:15:36 の wake 後の `handle` 件数 | **0 件**（約1時間ずっと） |
| 同 wake 後の `activateServer`/`deactivateServer` | **43 件**（アプリ切替のたびに正常に到着） |
| 全 client の応答性 | 一律 `insert=true mark=true`（client オブジェクトは生存） |

結論:
- **OS は AkazaIME を「アクティブな IME」として扱い続けている**（activate/deactivate は飛ぶ）。
- **client オブジェクトは生きていて `insertText`/`setMarkedText` に応答できる**（＝復路は無傷）。
- **だが keyDown が一切 `handle()` に配送されない**＝**OS のキーイベント配送経路（往路）だけが断たれている**。

これは「復路の断」でも「in-process のドロップ」でもなく、**純粋に往路の断**。`killall` で回復しない事実（壊れているのは OS の HIToolbox/TSM のキールーティングで、Swift 再起動では OS がイベントを渡さない）とも、長時間スリープ（土日）で出やすい観察とも整合する。§6 の H1 が「往路の断・復路は生存」という具体形で確定。

→ 次の課題は「**どの操作で往路が復活するか**」の切り分け（§7-1）。復活操作が分かれば、wake 通知時にそれをプログラムで自動実行する対策に直結する。有力候補は `TISSelectInputSource` による入力ソースの一時トグル（別ソースへ切替→Akaza へ戻す）で OS のキールーティングを張り直す案。

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

## 10. ライブ検証（2026-06-23）: 回復操作の切り分けと診断ツールの訂正

6/23 に wedge が再発し、**発生中のライブ状態**で §7-1 の回復操作切り分けを実施した。重要な発見が3つ。

### 10-1. 往路の断はプロセス全体で起きている（特定コントローラの問題ではない）
wedge 中に打鍵すると、**新規に生成された `controller init` のコントローラでも `handle` が 0 件**だった（`activateServer` は来るが keyDown が来ない）。§9 の「往路の断」が、古いコントローラ固有ではなく **AkazaIME プロセス全体（OS↔IME 接続全体）** で起きていることが確定。

### 10-2. 診断ツールの訂正 — TIS API と `defaults read` は wedge の真の状態を反映しない
wedge 中・回復後の両方で、以下が**同じ表示**だった:
- `/tmp/akaza_tis_dump`（`TISCreateInputSourceList` + `kTISPropertyInputSourceIsEnabled`）→ 常に `Akaza.Japanese: enabled=true`
- `defaults read com.apple.HIToolbox AppleEnabledInputSources` → 常に Akaza が出てこない

つまり**この2つは状態判定に使えない**。当初「AppleEnabledInputSources から Akaza が消えた＝disabled が原因」と考えたが、これは**誤り**（壊れていても回復していても表示が変わらない）。
さらに、wedge 中に `TISEnableInputSource` / `TISDisableInputSource` / `TISSelectInputSource` トグル / **システム設定の「＋」での再追加**を試したが、いずれも状態を変えられなかった。
→ **信用できる唯一の状態信号は `~/Library/Logs/AkazaIME/akaza.log` の `handle` 到着有無**（来ていれば往路は生存）。
→ この結果、TIS API での自動再有効化を狙った **PR #109 は無効と判明しクローズ**した。

### 10-3. 【最重要】`make install`（バンドル置換）で reboot 無しに回復した
wedge 中に次を実行したところ**復活した**（akaza.log で `handle` 再開・7000件超を確認）:
```sh
make install && killall AkazaIME && pkill -9 -f akaza-server
```
このとき **wake は起きておらず、wake 時 IMKServer 再生成の実験（§10-4）は未発火**。効いたのは `make install` の中身——
```
rm -rf ~/Library/Input Methods/Akaza.app   # 旧バンドル削除
cp -a out/Akaza.app ~/Library/Input Methods/  # 新バンドル設置
```
**バンドルがディスク上で置き換わると macOS が入力メソッドを再登録し、OS 側に溜まった壊れた接続/登録がクリアされた**、というのが最有力の説明。「`killall` 単独では治らない（＝同じバンドルに再接続するだけ）」事実とも整合する。
⇒ **再登録が回復の鍵**であり、(a) reboot より軽い回復手段、(b) wake 時の予防（バンドル touch / 再登録 / `TISRegisterInputSource`）の有力候補。

**未確定（次回の切り分け課題）**: 「バンドル置換そのもの」が効いたのか「単なる完全プロセス再起動」で十分なのか。次回 wedge 時は **まず `killall AkazaIME` だけ → ダメなら `make install`** の順で試し、どちらで治るかを記録する。

### 10-4. 投入した予防実験（commit 7eef1b4, debug/path-a-wake-logging）
wake 通知時に `akaza-server` 再起動に加えて **`IMKServer` 自体を作り直す**コードを `Sources/AkazaIME/main.swift` に追加（解放→runloop 1サイクル→同名で再 init、最大5回リトライ）。OS↔AkazaIME 接続が腐る前に張り直す狙い。**効果は未検証**（投入後まだ wake が起きていない）。次回以降の wake で `[diag] IMKServer recreated on wake` の有無と wedge 再発有無を観測する。最悪 IMKServer 再生成に失敗しても killall / 自動再起動で回復するため、reboot を要する現状より悪化はしない。

### 10-5. 補足: 今回の wedge 直前にスリープは無かった
pmset ログ上、wedge が顕在化した時刻の直前にスリープ/ロックは無く（Caffeine 稼働中）、当日朝の wake 由来の潜在破損が後から顕在化した可能性がある。⇒ **wake トリガだけの対策では取りこぼす恐れ**。署名/notarization 仮説は最有力だが未確定のまま（GUI 再追加時の trustd 署名検証バーストは状況証拠どまり）。

### 10-6. 2026-06-26: `IMKServer` wake 時再生成は main thread を詰まらせる疑いが強い
07:40 の wake 後ログで以下を確認した:

- `AkazaIME: wake from sleep — restarting akaza-server`
- `AkazaIME[diag]: wake — releasing IMKServer (...)`
- その後に期待した `IMKServer recreated on wake` / `recreate failed` が出ない
- 以後、別プロセスとして AkazaIME が起動し直されるまで通常の `handle` ログが出ない

コード上は `imkServer = IMKServer(...)` の直後に成功/失敗ログを出すため、ログが途切れた位置から **`IMKServer` initializer 自体が main thread 上で戻っていない**可能性が高い。したがって wake 時に同一プロセス内で `IMKServer` を破棄/再生成する予防実験は撤去した。経路A の回復は、既に効果を確認した `make install` によるバンドル再登録、またはそれに近い OS 側再登録手段で検証する。

### 10-7. 2026-06-26: `make install` 後に Akaza が入力メニューから消える
`make install && killall AkazaIME && pkill -9 -f akaza-server` 後に Akaza が選択不能になった。確認結果:

- `~/Library/Input Methods/Akaza.app` は存在し、Info.plist の入力ソース定義も存在する
- ただし `codesign -dv` の Identifier が `AkazaIME` になっており、`CFBundleIdentifier` の `com.github.tokuhirom.inputmethod.Japanese.Akaza` と不一致
- `AppleEnabledInputSources` から Akaza が消えていた
- `TISRegisterInputSource` / `TISEnableInputSource` は `status=0` を返すが、`TISSelectInputSource(Akaza.Japanese)` は `-50` のまま
- `com.apple.hiservices-xpcservice` の connection invalid が TIS 操作時に継続して出る
- 一方で AkazaIME プロセス自体には `activateServer` が来ており、プロセス生存と入力メニュー上の可用性が乖離している

`make install` で未署名に近いバンドルを入れると LaunchServices / TIS / 署名 ID の整合が崩れる可能性があるため、`bundle` の最後に `codesign --force --deep --sign - out/Akaza.app` を追加した。以後の検証では、インストール後に `codesign -dv ~/Library/Input\ Methods/Akaza.app` の Identifier が `com.github.tokuhirom.inputmethod.Japanese.Akaza` であることを確認する。

## 11. 【原因確定 2026-07-13】Secure Event Input の解放漏れ

wedge がライブ再発し、これまでの全仮説を棄却する切り分けの末、根本原因を特定した。

### 11-1. 今回の切り分けで全て陰性になった

タイムライン: 07:10:30 FullWake → 07:54:37 まで `handle` 正常 → 09:24 以降 `handle` ゼロ（この間スリープ無し）。

| 操作 | 結果 |
|---|---|
| `killall AkazaIME`（09:26, 09:27 の 2 回） | ✗ handle ゼロのまま |
| `make install`（バンドル置換 + 署名確認済み） | ✗ **回復せず** — 6/23 の「バンドル置換で回復」と矛盾 |
| 新規 controller 生成（ghostty id=2, Slack id=3/4） | ✗ activateServer は来るが handle ゼロ |
| 入力ソーストグル（ABC→Akaza） | ✗ 回復せず — §9 の「新セッション生成で回復」仮説を反証 |
| 別アプリ（Slack）で入力 | ✗ アプリ単位ではなくシステム全体の断 |

### 11-2. 真犯人: Secure Event Input

「activateServer は届くのに keyDown だけ全アプリで届かない」を仕様として説明できるのが
**Secure Event Input**（`EnableSecureEventInput`）。どこかのプロセスが有効化している間、
macOS はパスワード保護のため**キーイベントを IME に配送しない**（制御メッセージは届き続ける）。

確認方法（wedge 中に実行して確定）:

```sh
ioreg -l -w 0 | grep -o 'kCGSSessionSecureInputPID"=[0-9]*'
# → kCGSSessionSecureInputPID"=14255
ps -p 14255 -o pid,lstart,command
# → /Applications/Ghostty.app/Contents/MacOS/ghostty
```

**ghostty が Secure Input を握りっぱなしだった。** ghostty は端末の termios が
「パスワード入力モード」（ECHO off + ICANON on）になるとメニューの Secure Keyboard Entry
設定と無関係に自動で Secure Input を有効化する。全 TTY の termios を確認したところ
パスワードモードのペインは存在せず、**ghostty 内部のカウンタが解放し損ねて張り付いた**状態
（ghostty 側のバグの可能性が高い）。

### 11-3. これまでの謎が全て説明される

| これまでの観測 | Secure Input 説での説明 |
|---|---|
| activateServer は届くのに handle だけ来ない（§9） | Secure Input 中はキーイベントが IME をバイパスする仕様 |
| プロセス全体・全アプリで断（§10-1） | Secure Input はシステムグローバル |
| killall / バンドル置換 / TIS トグル / 再追加が全部無効 | IME 側には何の問題もないから |
| リブート・再ログインで治る | ghostty が終了して Secure Input が解放される |
| 6/22 の「自然回復」（§9） | ghostty が Secure Input を解放した瞬間。直前の controller init との相関は偶然 |
| 6/23 の「make install で回復」（§10-3） | **偶然の一致**。今回バンドル置換では回復しなかった |
| スリープ復帰との相関 | 復帰時のロック画面パスワード入力や、復帰前後のパスワードプロンプト検出の誤作動で張り付きやすい |
| wake 直後ではなく数時間後に発症（§10-5, 今回も） | 発症タイミング＝ghostty がパスワードモードを検出した（解放し損ねた）時刻であり、wake そのものではない |

### 11-4. 対処

- **回復**: Secure Input を握っているプロセス（`ioreg` で特定）を再起動する。ghostty なら Cmd+Q → 再起動。リブート不要。
- **【重要・2026-07-13 実測】保持プロセスを終了しても解放されないことがある。** 今回、旧 ghostty (pid 14255) を Cmd+Q で終了した後も `kCGSSessionSecureInputPID=14255`（死んだ PID）のまま残留し、`IsSecureEventInputEnabled()` も true を返し続けた（WindowServer セッション状態の腐敗）。この場合は **画面ロック（Ctrl+Cmd+Q）→ パスワードでロック解除** で解放される（loginwindow が Secure Input を取得→解放する際に腐った状態が上書きされる）。実際にこれで回復し、直後に `handle` の到着を確認した。
- **検出（実装済み 2026-07-13）**: `Sources/AkazaIME/SecureInputDiagnostics.swift`
  - `activateServer` 時に Secure Input 有効なら `SECURE EVENT INPUT ACTIVE (pid=... app...)` を akaza.log に記録
  - wake 時（didWakeNotification）にも同様に記録
  - 入力メニューに「⚠️ 「アプリ名」が Secure Input を有効化中 — 日本語入力不可」を表示
- **予防**: mac-akaza 側では他プロセスの Secure Input を解放できない（OS の仕様）。ghostty 側の解放漏れバグの調査・報告は別途。
- **【追記 2026-07-24】「IME 側は何もできない」は部分的に誤りの可能性**: macSKK #351 により、`~/Library/Input Methods`（ユーザーライブラリ）の IME は SKE 有効中に無効化され解放後も復帰しないが、`/Library/Input Methods`（システムライブラリ）の IME は影響を受けないことが実証されている。他 IME 実装の調査結果と輸入候補は [secure-input-survey.md](secure-input-survey.md) 参照。

### 11-5. 過去の診断コードの扱い

§8 で投入した `[diag]` ログ（往路/復路の計測）は原因特定に決定的な役割を果たした
（「handle だけ来ない」の確定が Secure Input 説への到達に必須だった）。
Secure Input 検出を常設化した後、過剰な per-key ログは削減してよい。

## 付録: 即時回復手段（ユーザー向け）

**2026-07-13 に根本原因が Secure Event Input の解放漏れと確定した（§11）。回復手順は以下。**

1. 犯人を特定する:
   ```sh
   ioreg -l -w 0 | grep -o 'kCGSSessionSecureInputPID"=[0-9]*'
   ps -p <PID> -o pid,lstart,command
   ```
2. そのプロセスを再起動する（ghostty なら Cmd+Q → 再起動）。リブート不要。
3. **プロセス終了後も解放されない場合**（死んだ PID が残留する）: **画面ロック Ctrl+Cmd+Q → パスワードでロック解除**。2026-07-13 にこれで回復を実測（§11-4）。
4. 入力メニューに「⚠️ … Secure Input を有効化中」が出ていれば、それが原因表示（実装済み）。

過去に試して**効かなかった**手段（Secure Input が原因なので当然）:

- `killall AkazaIME` 単独（2026-06-15, 2026-07-13）
- `make install`（バンドル置換）— 2026-06-23 に「回復した」ように見えたのは偶然の一致（2026-07-13 に反証）
- TIS API トグル・システム設定での削除/再追加（2026-06-23）
- 入力ソースの手動トグル ABC→Akaza（2026-07-13）

状態判定は `defaults read` や TIS dump ではなく、**`~/Library/Logs/AkazaIME/akaza.log` に `handle` が来ているか**で行うこと（§10-2）。
