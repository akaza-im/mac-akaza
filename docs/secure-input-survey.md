# Secure Event Input: 他の IMKit IME 実装の調査 (2026-07-24)

mac-akaza の Secure Input wedge 問題（[sleep-wake-investigation.md](sleep-wake-investigation.md) §11）に関連して、
他の IMKit ベース IME が Secure Event Input にどう対処しているかを調査した記録。

## TL;DR

略語: **SKE = Secure Keyboard Entry**。ターミナルアプリ（Terminal.app / iTerm2 等）のメニューから
Secure Event Input を手動で有効化する機能の名称。

1. **【最重要】インストール先が `/Library/Input Methods`（システム）か `~/Library/Input Methods`（ユーザー）かで Secure Input 時の挙動が変わる**（macSKK #351 で実証）。ユーザーライブラリの IME は SKE 有効中に無効化され、**解放後も復帰しない**。システムライブラリの IME は影響を受けなかった。macSKK は v2.0.0 でインストール先変更（pkg 化）により解決した。mac-akaza は現在ユーザーライブラリにインストールしており、まさに問題の出る構成。
2. Secure Input を明示的にハンドリングしている IMKit IME は **fcitx5-macos / SokIM / Fire** の 3 つのみ。主要 OSS 日本語 IME（macSKK, AquaSKK, azooKey-Desktop, Mozc）は検出コードすら持たない。検出・警告では mac-akaza が最も進んでいる。
3. 「解放後も wedge が残る」問題への IMK レベルの既知の処方箋は存在しない。明示対処組の共通結論は「**解放イベントは存在しないので、毎キー・毎 activateServer・タイマーで再評価するしかない**」。

## 各実装の対応状況

| IME | 言語 | Secure Input 対応 | 備考 |
|---|---|---|---|
| [fcitx5-macos](https://github.com/fcitx/fcitx5-macos) | 多言語 | ◎ 検出 + 正当性判定 + stale-true 無視 | 最先端。PR #269 は mac-akaza に輸入済み |
| [SokIM](https://github.com/kiding/SokIM) | 韓国語 | ○ 検出 + 英字退避 + 自己修復 | wedge 前提の自己回復設計が参考になる |
| [Fire](https://github.com/qwertyyb/Fire) | 中国語 | ○ activateServer で検出し英字退避 | ABC 削除環境の防御 (issue #158) |
| [macSKK](https://github.com/mtgto/macSKK) | 日本語 | △ コードなし・**インストール先で解決** | issue #351 → v2.0.0 で `/Library` へ移設 |
| [AquaSKK](https://github.com/codefirst/aquaskk) | 日本語 | △ コードなし | 昔から pkg で `/Library` に入れる設計のため問題自体を踏んでいない |
| [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) | 日本語 | ✗ なし | 関連 issue もゼロ |
| [Mozc](https://github.com/google/mozc) | 日本語 | ✗ なし | bundleId 別 quirks テーブルのみ（後述） |
| [Squirrel](https://github.com/rime/squirrel) | 中国語 | ✗ なし | |
| [Gureum](https://github.com/gureum/gureum) | 韓国語 | ✗ なし | |
| [OpenVanilla](https://github.com/openvanilla/openvanilla) | 中国語 | ✗ なし | |

## 配布形態の比較 (2026-07-24 各リポジトリで実測)

| IME | 配布形態 | インストール先 | 根拠 |
|---|---|---|---|
| macSKK | pkg (v2.0.0〜) | `/Library` | `script/app.plist` の `RootRelativeBundlePath` |
| AquaSKK | pkg (`requireAuthorization`, 要ログアウト) | `/Library` | `platform/mac/pkg/aquaskk.plist` |
| azooKey-Desktop | pkg + install.sh | `/Library` | `install.sh`, `pkg-scripts/postinstall` |
| Mozc / Google 日本語入力 | 公式インストーラ pkg | `/Library` | `src/mac/installer/`, `tweak_installer_files.py` |
| fcitx5-macos | tar + install/update スクリプト (sudo) | `/Library` | `CMakeLists.txt` `APP_INSTALL_PATH` |
| Squirrel | pkg | `/Library` | `package/make_package` |
| Gureum | pkg (`productbuild`) | `/Library` | `tools/post_archive.sh` |
| SokIM | pkg | `/Library` | `.github/workflows/release.yml` |
| OpenVanilla | 独自インストーラアプリ | **`~/Library`** | `Source/Mac/Installer/AppDelegate.swift` |
| **mac-akaza** | `make install` (cp) | **`~/Library`** | `Makefile` `INSTALL_DIR` |

**ユーザーライブラリ派は OpenVanilla と mac-akaza だけ。** 他は全て `/Library/Input Methods`
（root 権限が要るので必然的に pkg か sudo スクリプト）。

## 【最重要】macSKK #351: インストール先がすべて

<https://github.com/mtgto/macSKK/issues/351>

- iTerm2 の Secure Keyboard Entry (SKE) 有効時、`~/Library/Input Methods` の IME（macSKK, azooKeyMac）は入力メニューでグレーアウトして使えなくなるが、`/Library/Input Methods` の AquaSKK は無効にならなかった。
- 報告者は `sudo mv "$HOME/Library/Input Methods/macSKK.app" '/Library/Input Methods/'` だけで全アプリで解消。
- mtgto 氏の検証（macOS 15.4.1, Terminal / Kitty / iTerm2）: ターミナル起動時から SKE が有効だとユーザーライブラリの IME は無効化され、**「そのあと Secure Keyboard Entry 無効に戻してもユーザーライブラリの IME は有効にはならないぽい」** — mac-akaza の「解放後も wedge が残る」観測と完全に一致。
- 対処: v2.0.0 (2025-06-14) でデフォルトのインストール先を `/Library/Input Methods` に変更（pkg インストーラ、`RootRelativeBundlePath` 指定）して解決（issue #360）。
  [FAQ](https://github.com/mtgto/macSKK/blob/main/docs/faq.md) にも「SKE が有効なアプリで日本語入力システムを使うには、システムライブラリにインストールされている必要があります」と明記。

**mac-akaza への含意**: 「Secure Input 中はどの IME にもキーが来ないのは仕様で IME 側は何もできない」
（sleep-wake-investigation.md §11-4）は部分的に誤りだった可能性が高い。OS はインストール先で IME の
信頼度を区別しており、`/Library/Input Methods` へ移設すれば wedge 自体を回避できる見込みがある。
Makefile の `INSTALL_DIR` 変更（sudo が必要）または pkg インストーラ化で検証・対応する。

> **【2026-07-24 実測で反証】** 下記「実測: `~/Library` vs `/Library`」の通り、Darwin 25.5.0
> （macOS 26 系）では **`/Library` 版でも ABC 化は起きた**。macSKK #351 の「`/Library` なら
> 影響を受けない」はこの環境では再現せず、上記の「移設で wedge を回避できる」含意は成立しない。
> OS バージョン差（#351 は macOS 15.4.1 = Sequoia）が原因と見られる。

## 実測: `~/Library` vs `/Library`（2026-07-24, Darwin 25.5.0）

macSKK #351 の主張を自環境で検証するため、Terminal.app の Secure Keyboard Entry (SKE) を
手動で ON/OFF し、入力ソースの `current` と各 Akaza 入力ソースの enabled/selected/selectable、
バンドルの所在（`~/Library` か `/Library` か）を 0.5s 間隔でサンプリングした
（スクリプトは scratchpad の `ske-monitor.swift`）。同一 bundleId の衝突を避けるため、
`/Library` 検証時は `~/Library` 版を退避して一本化した。

観測結果:

| 構成 | SKE 保持アプリ(Terminal)が前面 | 別アプリが前面 | SKE 完全解放後 |
|---|---|---|---|
| `~/Library` | `current` が **ABC に強制切替** | `current`=Akaza 維持 | Akaza に復帰（この回は回復） |
| `/Library` | `current` が **ABC に強制切替**（同じ） | 揺れあり | `current`=ABC 表示だが**ユーザー操作で Akaza に戻せる**（永続 wedge ではない） |

判明したこと:

1. **`/Library` 移設は ABC 化を防がない**。macSKK #351 の「グレーアウト＝ABC 化」現象は
   `/Library` 版でも起きた。移設は SKE wedge の根本対策にならない（少なくとも Darwin 25.5.0）。
2. **ABC 化には「SKE 保持アプリがフォアグラウンドにいる」ことが必要**。SKE 有効なだけでは
   （保持アプリが前面にいない CLI ホルダ）`current`=Akaza を維持し、強制切替は起きなかった。
   macSKK #351 の「ターミナル起動時から SKE 有効」もこの前面条件を満たしていた。
3. 観測された `current=ABC` は**受動的な入力ソース値**で、ユーザーが入力ソース切替（英数/かな等）
   すれば Akaza に戻せる。過去の本物の wedge（Akaza を選んでもキーが一切来ない、
   sleep-wake-wedge-bug）とは別物。
4. SKE 中でも `TISSelectInputSource(Akaza)` は `OSStatus=0` で成功し `current`=Akaza に戻せる
   （ただし UI 上はグレーアウト表示、キーは配送されない）。
5. 副次: 真の保持者が別プロセスなのにモニタ側で無関係のフォアグラウンドアプリが
   holder として記録されるケースを再確認（rdar://48953777 の PID 誤記録）。

**結論**: 「pkg 化して `/Library` へ移設すれば SKE wedge が直る」という survey の当初の当て込みは、
現行 OS では**否定された**。移設は配布形態としては妥当（他 IME もほぼ全て `/Library`）だが、
SKE wedge の対策としては効かない。本命は **SKE 解放検出後の自動回復**
（TextExpander 式の true→false ポーリング + 内部状態リセット、または IME プロセスの
exit→imklaunchagent 再起動）に切り替えるべき。

関連: macSKK [#112](https://github.com/mtgto/macSKK/issues/112)（ディスプレイオフで ABC しか使えなくなる、open）
にも Secure Input 解放漏れ由来のケースが報告されている（blog.64p.org 2026-07-13 のエントリが引用されている）。

## fcitx5-macos: stale-true を obey しない設計

[controller.swift](https://github.com/fcitx/fcitx5-macos/blob/master/src/controller.swift) /
[secure.swift](https://github.com/fcitx/fcitx5-macos/blob/master/src/secure.swift) /
[macosfrontend.swift](https://github.com/fcitx/fcitx5-macos/blob/master/macosfrontend/macosfrontend.swift)

- 設計思想: `IsSecureEventInputEnabled()` の **true を信用しない**。「行儀の悪いアプリは blur しても
  Disable を呼ばないので、true に従うと英字キーボードにロックされる」とコメントに明記。
  保持 PID の bundleId がフォーカス中アプリと一致するときだけ obey する（PR #269、mac-akaza 輸入済み）。
- **毎キー再評価**するが、性能のため IORegistry からの PID 取得はフォーカス変化時のみに絞り、
  keyDown 時はキャッシュ (`obeySecureInput`) を使う。
- `isPasswordOnly(app:)`: `com.apple.loginwindow` / `com.apple.wifi.WiFiAgent` /
  `com.apple.wifi-settings-extension` は「Secure Input を宣言しないパスワード専用 UI」として
  静的リストで常時英字扱い。
- secure.swift（espanso 移植）のコメントに「Ctrl+Cmd+Q → 再ログイン後は loginwindow の PID が
  保持者として返る」という残留状態への言及あり。

## SokIM: wedge 前提の自己修復設計

[AppDelegate.swift](https://github.com/kiding/SokIM/blob/main/SokIM/AppDelegate.swift)

- `handle()` 冒頭で `IsSecureEventInputEnabled()` なら `return false`（OS に丸投げ）。
- `NSTextInputContext.keyboardSelectionDidChangeNotification` を observe し、Secure Input 中なら
  組み立て状態を全破棄して英字エンジンへ強制切替。
- `NSWorkspace.didWakeNotification` / `screensDidWakeNotification` で自前の IOHID モニタを
  強制再起動（失敗時 1 秒後リトライ）。`handle()` 内でも状態不整合を検出したら
  `restartIfIdle()` で自己修復 — 「気づいたら死んでいた」前提の設計。

## Fire: ABC 削除環境への防御

[FireInputServer.swift](https://github.com/qwertyyb/Fire/blob/master/Fire/FireInputServer.swift) /
[issue #158](https://github.com/qwertyyb/Fire/issues/158)

- 通常はパスワード欄で OS が ABC に自動切替するので第三者 IME は呼ばれないが、
  **ユーザーが ABC 入力ソースを削除していると Secure Input 中でも第三者 IME が呼ばれる**。
- `activateServer` ごとに `IsSecureEventInputEnabled()` を検査し、自ら英字モードへ退避。

## Mozc / azooKey: Secure Input 対応はないが参考になる点

- Mozc [mozc_imk_input_controller.mm](https://github.com/google/mozc/blob/master/src/mac/mozc_imk_input_controller.mm):
  bundleId 別 quirks テーブル。`com.apple.securityagent` では URL を開かない（Secure Input 文脈への唯一の言及）、
  Office アプリでは `selectedRange:` を呼ばない（クラッシュ回避）等。
- azooKey-Desktop `azooKeyMacInputController.swift`: **Chromium deadlock 回避** —
  activateServer 中に同期の `client.attributes(forCharacterIndex:)` を呼ぶと Chromium の JS コンパイル中に
  deadlock するため呼ばない（Chromium issue 503787240）。
  教訓: activation 中の同期的な IMK client 往復は避ける。

## 「解放後も固まる」現象の既知原因

1. **実は解放されていない（最多）**: `EnableSecureEventInput` はカウント式
   （Carbon ヘッダ CarbonEventsCore.h）。enable/disable の回数が合わないと永久に有効のまま。
   - Chrome: パスワード送信時にカーソルが password field に残っていると Disable し損ねる既知バグ
     （[TextExpander の解説](https://textexpander.com/secure-input)）
   - loginwindow: ロック解除・ファストユーザスイッチ後に保持者として残留
     （[Apple Community 253793652](https://discussions.apple.com/thread/253793652)）
   - ghostty: [Discussion #10480](https://github.com/ghostty-org/ghostty/discussions/10480) —
     メインスレッド飢餓で `DisableSecureEventInput()` の実行が遅延。行儀の良いアプリでも stuck に見える
   - 常習犯リスト: [Keyboard Maestro wiki](https://wiki.keyboardmaestro.com/assistance/Secure_Input_Problem)
2. **保持者 PID 自体が信頼できない**: [rdar://48953777](https://github.com/lionheart/openradar-mirror/issues/21098) —
   バックグラウンドのアプリが Enable を呼ぶと `kCGSSessionSecureInputPID` には
   **その時アクティブだったアプリ**の PID が記録される。fcitx5 方式の bundleId 比較警告は
   無実のフォーカスアプリを犯人扱いする可能性がある（mac-akaza の警告にも同じ注意が必要）。
3. **ユーザーライブラリ IME の非復帰**（macSKK #351、前述）: SKE 解放後もユーザーライブラリの IME は
   有効に戻らない OS 側挙動。
4. Apple 公式の救済 API は存在しない。[TN2150](https://developer.apple.com/library/archive/technotes/tn2150/_index.html)
   は「保持プロセスの責任」としか言っておらず、DTS も
   [回答を持たない](https://developer.apple.com/forums/thread/698113)。
   OS レベルの回復は「画面ロック（Ctrl+Cmd+Q）→ 解錠」が定番（mac-akaza でも 2026-07-13 実測）。

## mac-akaza への輸入候補（優先順・2026-07-24 実測後に改訂）

1. **自己修復: 解放検出後も一定時間 handle が来ないなら IME プロセス自身を exit**
   （IMKit の IME は必要時に OS が再起動する。`killall AkazaIME` の自動化に相当。SokIM の
   restartIfIdle パターンの応用）。**当初 5 位だったが、移設が効かないと実測で判明したため本命に昇格。**
2. タイマーポーリングで true→false 遷移を検出し、内部状態をリセット（TextExpander 方式）。
   「解放されたのに直らない」を潰す網。1. と組み合わせる。
3. 済: 検出・ログ・通知（`SecureInputDiagnostics.swift` / `SecureInputNotifier.swift`）、
   fcitx5 方式の正当性判定、死んだ holder の残留検出。
4. 警告文言に rdar://48953777（保持者 PID の誤記録）の但し書きを追加。
5. ~~`/Library/Input Methods` への移設~~ — **2026-07-24 実測で ABC 化を防がないことが判明し、
   SKE wedge 対策としては降格**。配布形態としては妥当（他 IME もほぼ `/Library`、root 所有で
   改竄耐性）なので、pkg 化する場合は「wedge 対策ではなく配布の正道化」として位置づける。

## その他の参考資料

- [espanso: Secure Input troubleshooting](https://espanso.org/docs/troubleshooting/secure-input/)
- [alexwlchan: Finding the app using Secure Input](https://alexwlchan.net/2021/secure-input/)
- iTerm2 `sources/FixBrokenAppleCrap/AppSwitchingPreventionDetector.swift`:
  Secure Input 保持中は他アプリのアクティベーションまで阻害されることを検出して警告
  （キー入力以外も壊れる証拠）
- KeePassXC の解放漏れ対策 safeguard: [#11906](https://github.com/keepassxreboot/keepassxc/issues/11906) →
  [PR #11928](https://github.com/keepassxreboot/keepassxc/pull/11928)
