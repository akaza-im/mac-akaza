# Changelog

## [v2026.601.0](https://github.com/akaza-im/mac-akaza/compare/v2026.519.0...v2026.601.0) - 2026-06-01
- fix: スリープ復帰後に変換できなくなる問題を修正 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/92
- perf: 変換が200ms超えた場合にログを出力する by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/94
- update akaza to v2026.530.0 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/95

## [v2026.519.0](https://github.com/akaza-im/mac-akaza/compare/v2026.408.0...v2026.519.0) - 2026-05-19
- fix: throttle learn disk writes to avoid macOS resource limit by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/90
- かなキー押下時にスペースがコミットされてしまう事象の修正 by @piarra in https://github.com/akaza-im/mac-akaza/pull/89
- update akaza to v2026.404.0 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/86

## [v2026.407.0](https://github.com/akaza-im/mac-akaza/compare/v2026.331.0...v2026.407.0) - 2026-04-07
- fix: ユーザー辞書追加ダイアログで Tab キーによるフィールド移動を有効化 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/84

## [v2026.331.1](https://github.com/akaza-im/mac-akaza/compare/v2026.331.0...v2026.331.1) - 2026-03-31
- fix: ユーザー辞書追加ダイアログで Tab キーによるフィールド移動を有効化 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/84

## [v2026.331.0](https://github.com/akaza-im/mac-akaza/compare/v2026.327.0...v2026.331.0) - 2026-03-31
- fix: akaza-server クラッシュ時の SIGPIPE によるIMEプロセス終了を修正 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/80
- fix: 変換リクエストを非同期化してメインスレッドのブロックを解消 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/82
- fix: akaza-server 再起動バックオフの上限を 60 秒から 15 秒に短縮 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/83

## [v2026.325.0](https://github.com/akaza-im/mac-akaza/compare/v2026.308.0...v2026.325.0) - 2026-03-25
- chore: upgrade libakaza to v2026.310.0 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/71
- feat: 複数のSKK辞書をダウンロード可能にする設定UIを追加 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/73
- fix: レビュー指摘対応 - 強制アンラップ除去とアクセス修飾子を修正 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/75
- feat: macOS標準IME互換のファンクションキー・ショートカットキーに対応 by @gunyarakun in https://github.com/akaza-im/mac-akaza/pull/72
- fix: ファンクションキー状態でのBackspace修正・USキーボード対応 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/76
- docs: split README into user-facing README and developer HACKING.md by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/77
- chore: upgrade libakaza to v2026.313.0 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/78
- feat: 設定画面からローマ字テーブルを切り替えられるようにする by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/79

## [v2026.308.0](https://github.com/akaza-im/mac-akaza/compare/v2026.304.0...v2026.308.0) - 2026-03-08
- Add predictive candidate visibility setting by @nyuichi in https://github.com/akaza-im/mac-akaza/pull/63
- fix: remove redundant sources list from test target in Package.swift by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/69
- fix: duplicate candidate navigation jump (#64) by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/70

## [v2026.304.0](https://github.com/akaza-im/mac-akaza/compare/v2026.303.0...v2026.304.0) - 2026-03-04
- fix: converting 状態で Backspace を押すと空文字がコミットされるバグを修正 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/61

## [v2026.303.0](https://github.com/akaza-im/mac-akaza/commits/v2026.303.0) - 2026-03-03
- Rewrite IME frontend in Swift (Phase 1) by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/2
- Add akaza-server (Rust JSON-RPC kana-kanji conversion server) by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/3
- Add clippy and fmt checks to CI and lefthook by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/4
- Connect Swift frontend to akaza-server for kana-kanji conversion by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/5
- Add candidate selection UI with clause navigation by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/6
- Fix character input handling and candidate window mouse events by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/7
- Let akaza-server stderr inherit parent's log file by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/8
- Add clause boundary resize with Shift+arrow keys by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/9
- Add CLAUDE.md with project overview and guidelines by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/10
- Add mise.toml for tool version management by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/11
- Add CLI test scripts for akaza-server by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/12
- Add learn RPC call on conversion commit by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/13
- Add paging support to candidate window by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/14
- Fix number keys not entering preedit in composing state by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/15
- Add settings UI with punctuation style and user dictionary by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/18
- Allow symbols to enter preedit by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/19
- use libakaza a5454ce by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/20
- Change romkan mapping format from YAML to JSON by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/21
- libakaza, that includes #455 https://github.com/akaza-im/akaza/commit/540c64f387f8f7cb348ccb5e85238af545c67cfb by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/22
- Fix control characters appearing in preedit by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/23
- Support Ctrl+H as backspace in composing state by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/24
- Fix arrow keys causing tofu characters in composing state by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/26
- Persist learned user data to disk by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/27
- Fix backspace behavior with input history by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/28
- Update libakaza to v2026.218.0 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/29
- Update akaza-default-model to v2026.218.0 from akaza-im/akaza by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/30
- Fix preedit caret position by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/31
- Add k-best suggest candidates during composing by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/25
- Fix duplicate entries in k-best suggestion candidates by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/32
- Fix duplicate entries in conversion candidate window by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/33
- Fix arrow keys inserting tofu characters in suggesting state by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/34
- Fix Up/Down arrow key navigation in suggesting state by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/35
- Bump akaza library and model to v2026.220.0 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/36
- Show model version info in preferences by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/37
- Fix Enter in suggesting state to commit original hiragana by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/38
- Fix backspace to delete romaji sequence as single character by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/39
- Download SKK-JISYO.L on first launch and load it as dictionary by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/41
- Add user dictionary management and misconversion investigation guide by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/42
- Add lookup_unigram and lookup_bigram JSON-RPC methods by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/40
- Update akaza to v2026.220.3 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/43
- Update akaza to v2026.224.0 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/44
- Update akaza to v2026.225.0 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/45
- Update akaza to v2026.225.2 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/46
- fix: install *.model.scores files for bigram/skip-bigram by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/47
- perf: make suggestMaxPaths configurable, default to 5 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/48
- fix: 子音で終わる入力後のSpace+Enterで候補ウィンドウが消えない問題を修正 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/49
- chore: setup tagpr for automated releases by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/50
- chore: update akaza to v2026.227.0 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/51
- feat: add "she" and "sshe" romaji mappings by @gunyarakun in https://github.com/akaza-im/mac-akaza/pull/52
- chore: update akaza to v2026.303.0 by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/54
- fix: address code review issues across Swift and Rust components by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/55
- feat: treat uppercase ASCII as direct input mode by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/56
- fix: suppress suggest in direct input mode by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/58
- chore: add release workflow and universal binary build support by @tokuhirom in https://github.com/akaza-im/mac-akaza/pull/59
