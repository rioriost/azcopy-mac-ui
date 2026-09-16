# 設計・コードレビューと修正プラン

レビュー日: 2026-09-16

対象: `3d97ad2d6b2672c97e4a5bd2a5b131cfef1ad1e7` / 開発版 `0.2.0`

レビュー担当: GPT-6 Astra

実装元のモデルではなく、現在のコードと実際の振る舞いを評価対象とする。
以下の指摘は上記コミットの修正前の状態を記録したもの。
0.2.1 では R1-R12 と関連する操作確認・配布条件を実装した。
変更点と設定移行の注意事項は [`releases/0.2.1.md`](releases/0.2.1.md) を参照。

修正後の確認では、Swift の 101 テスト（Core 85、AppModel 16）、
配布スクリプトの 47 テストが成功し、Core の行カバレッジは 96.06%。
arm64 Release build とバージョン整合性も確認した。
これらはローカル・オフラインの確認であり、実 Azure 操作や署名・公証の完了を意味しない。

## 総評

SwiftUI の GUI と独立した Core、型付きの認証モデル、シェルを介さない引数配列による起動という基本構成は維持してよい。
全面的な再実装は不要。一方、**転送範囲・dry-run の保証、プロセスの入出力、認証情報の扱い**には、正常系の単体テストでは検出できていない問題がある。
確認した不具合は **P1 が 4 件、P2 が 8 件**。優先度 P1 の問題は次回配布前に解消する。

優先度の定義:

- **P1**: 操作停止、認証情報の意図しない保存、安全な操作の前提を崩す問題。
- **P2**: 特定の入力・操作・ツールチェーンでの不具合、または運用上必要な機能の欠落。

| ID | 優先度 | 問題 |
| --- | --- | --- |
| R7 | P1 | Recursive を OFF にしても sync が再帰実行される |
| R8 | P1 | Additional flags で Dry run などの安全設定を上書きできる |
| R1 | P1 | 大量出力で子プロセスが停止し、通常時も終了前のログが表示されない |
| R2 | P1 | SAS URL・追加フラグ内の秘密値が設定に保存される |
| R3 | P2 | 転送をキャンセルできない |
| R4 | P2 | 実行結果がプレビュー再生成で上書きされる |
| R5 | P2 | 引用符を含む追加フラグの argv が壊れる |
| R6 | P2 | Xcode 27 で coverage gate が動かず、判定指標も誤っている |
| R9 | P2 | 空白区切りで渡した SAS がプレビュー・ログに露出する |
| R10 | P2 | HTTPS 必須の検証が DFS と大文字のホスト名を取りこぼす |
| R11 | P2 | 既定のユーザー認証からサインインを開始できない |
| R12 | P2 | 対応外になった Managed Identity Object ID を選択できる |

## 確認した問題

### R1 / P1: 出力を終了後にしか読まないため、子プロセスが停止する

対象: `Sources/AzCopyMacUICore/AzCopyProcessRunner.swift:43-61`

関連: `Sources/AzCopyMacUI/AppModel.swift:240-247,378-401`、`Sources/AzCopyMacUI/ContentView.swift:810-817`

stdout/stderr の読み取りが `terminationHandler` 内にある。子プロセスが pipe の容量を超える出力を書き込むと、読み取りを待って停止する。一方、親は子の終了を待っているため、両者が先に進めない。
少量の出力でも、完了までログが表示されないため、進捗やデバイスコード認証の案内を実行中に確認できない。
テナント取得にも `waitUntilExit()` 後に pipe を読む同型の処理がある。

**根拠:** 実際の Runner に stdout/stderr 各 2 MiB を出すローカル fixture を渡すと、3 秒以内に終了しなかった。同じ fixture を両 pipe を継続的に読む親から起動すると、約 0.008 秒で正常終了した。

**修正:** 起動時から stdout/stderr を並行して読み、出力イベントを GUI に届ける。プロセス終了と両 stream の EOF を合流して結果を確定する。UTF-8 の分割、改行なしの認証案内、秘密値が chunk 境界をまたぐ場合を考慮し、redaction 前の断片を画面へ流さない。ログ保持量も制限する。

**完了条件:** 大量の stdout、stderr、両方の同時出力で停止しない。子の終了前に認証案内を表示できる。末尾の未改行データを失わず、失敗・キャンセルとの競合でも完了通知が重複しない。

### R2 / P1: SAS URL と追加フラグ内の秘密値が UserDefaults に保存される

対象: `Sources/AzCopyMacUI/AppModel.swift:15-19,42-43,156-157,166`

`source`、`destination`、`extraFlagsText` をそのまま保存している。通常の転送では SAS を含む URL を入力でき、追加フラグにも SAS を渡せるため、専用の `SecureField` を保存しないだけでは秘密値の非永続化を保証できない。
ログやプレビューの redaction は保存処理には適用されない。

**根拠:** 分離した UserDefaults suite に実際の AppModel からダミー SAS を入力すると、source、destination、追加フラグに原文が保存された。別の AppModel を作り直して source の SAS が復元されることも確認した。実際の利用者の設定・資格情報は読み取っていない。

**修正:** 保存可能な設定を allowlist 化し、URL と認証情報を分離する。既存の保存値についても migration で SAS などの秘密部分を除去し、再入力を求める。redacted placeholder を有効な転送先として復元しない。任意の追加フラグを無条件に保存しない。

**完了条件:** SAS 付き source/destination と追加フラグを入力・再起動しても秘密値が保存されない。既存設定の migration でも秘密値がログやエラーメッセージに出ない。秘密を含まないパスや設定の復元は維持する。

### R3 / P2: Cancel が未実装で、Task をキャンセルしても転送を止められない

対象: `Sources/AzCopyMacUI/ContentView.swift:588-601`、`Sources/AzCopyMacUICore/AzCopyProcessRunner.swift:43-69`

Cancel は空の action のまま常時 disabled。Runner にも cancellation handler や実行中の Process を停止する API がなく、呼び出し側の Task をキャンセルしても子が動き続ける。

**根拠:** 2 秒待機する fixture を Runner で起動し、200 ms 後に Task をキャンセルしても、約 2.1 秒後に exit 0 の成功結果が返った。

**修正:** 実行 Task と子プロセスの寿命を明示的に管理する。Cancel、起動前のキャンセル、起動直後のキャンセル、終了との競合を扱う。まず穏当な停止を要求し、必要なら猶予後の停止を検討する。対象は当該実行の子プロセスに限定する。

**完了条件:** 実行中だけ Cancel を有効化でき、キャンセル後は子が残らず、状態が「成功」にならない。アプリ終了時の転送の扱いも定義する。

### R4 / P2: 実行結果がプレビュー再生成によって上書きされる

対象: `Sources/AzCopyMacUI/AppModel.swift:207-218,248-256`

関連: `Sources/AzCopyMacUI/ContentView.swift:571-576`

終了コードや起動失敗を `statusMessage` に設定した直後、`refreshPreview()` が `Command is ready.` で上書きする。
Operations 画面では、有効なプレビューがある場合に実行状態を独立して表示していないため、失敗の把握には Logs への移動が必要になる。

**根拠:** exit 7 を返す fixture を実際の AppModel から実行すると、ログには失敗が残る一方、最終 status は `Command is ready.` になった。

**修正:** 入力検証・プレビューと実行状態を分離する。少なくとも idle / running / succeeded / failed / cancelled を区別し、最後の結果を入力編集で消さない。実行対象は入力の snapshot として保持する。

**完了条件:** 非ゼロ終了、起動失敗、キャンセルを Operations 画面で区別できる。プレビュー更新で結果を消さず、実行中にフォームを変更しても進行中の対象表示は変わらない。

### R5 / P2: Additional flags の引用符を解釈せず、表示と実際の argv が食い違う

対象: `Sources/AzCopyMacUI/AppModel.swift:354-357`

追加フラグを空白だけで split するため、`--include-path="folder with spaces"` のような値を 1 引数として渡せない。
その後のプレビューでは空白で結合されるため、見た目では問題が分からない。

**根拠:** 実際の AppModel と引数を JSON 出力する fixture で、次の 3 引数に分割されたことを確認した。

```text
--include-path="folder
with
spaces"
```

**修正:** 追加フラグを名前・値の構造化入力にするか、引用符・escape の仕様を限定した tokenizer を実装する。シェル実行で解決しない。不正な引用符は実行前にエラーにする。プレビューも実際の argv の境界を表現する。

**完了条件:** 空白を含む値、引用符、空文字、不正な引用符、Unicode パスで argv が仕様どおりになる。

### R6 / P2: Xcode 27 の標準 SwiftPM 出力で coverage gate が動かず、集計列も違う

対象: `Scripts/check-coverage.sh:11-19`

テスト実行ファイルを `*PackageTests` に固定しているが、今回の Swift 6.4 / 標準 `swiftbuild` は `AzCopyMacUICoreTests.xctest/Contents/MacOS/AzCopyMacUICoreTests` を生成する。
このため coverage data を生成した直後でも、スクリプトは `Coverage data not found` で失敗した。
また、`llvm-cov report` の `$4` は region coverage であり、計画で要求している line coverage ではない。

**根拠:** 同じ成果物を正しい実行ファイルで集計した値は、line coverage 97.04%、region coverage 88.14%。両者は別指標である。古いツールチェーンの CI でも同じ探索失敗が起きる、とは断定しない。

**修正:** 対応ツールチェーンと成果物の探索方法を明確にし、今回の実行の binary と profile を対応付ける。`llvm-cov export` の JSON など、列番号に依存しない方法で line coverage を判定する。複数成果物から単に最初のファイルを選ばない。

**完了条件:** 宣言する対応ツールチェーンで再現可能に動作し、line coverage 80% 未満は失敗、80% 以上は成功する。profile 不在・不整合は明示的に失敗する。

### R7 / P1: Recursive OFF が sync の実行範囲に反映されない

対象: `Sources/AzCopyMacUICore/AzCopyCommandBuilder.swift:235-236`

関連: `Tests/AzCopyMacUICoreTests/AzCopyCommandBuilderTests.swift:57-69`

`recursive: false` の場合に `--recursive` を省略しているが、AzCopy の **sync は recursive の既定値が true**。
そのため UI で Recursive を OFF にしてもサブディレクトリが対象になる。削除ありの sync では、意図した最上位の範囲を超えて宛先の下位ファイルを削除し得る。

**根拠:** 実際の builder が `recursive: false, deleteDestination: true` から次の引数を生成した。インストール済み AzCopy 10.32.8 の `sync --help` で再帰の既定値が true であることを確認した。既存テストは flag の省略を期待しており、CLI の意味との不整合を見逃している。

```text
sync /test-data/source https://example.blob.core.windows.net/container --delete-destination=true
```

**修正:** 対応するコマンドでは `--recursive=true/false` を明示する。コマンドごとに異なる CLI の既定値へ意味を委ねない。

**完了条件:** 各対応 action の true/false を実際の AzCopy の仕様に照合する。特に非再帰・削除ありの sync で `--recursive=false` が必ず生成され、追加フラグでも変更できない。

### R8 / P1: Additional flags が Dry run などの安全設定を無効化する

対象: `Sources/AzCopyMacUICore/AzCopyCommandBuilder.swift:238-247`

関連: `Sources/AzCopyMacUI/AppModel.swift:354-357`

GUI 由来のフラグの後ろに追加フラグを無条件に連結するため、UI の Dry run が ON でも `--dry-run=false` を後置できる。
`--recursive`、`--delete-destination`、`--overwrite` でも、GUI の設定と実効値が食い違う。
追加フラグは Settings 内にあり保存もされるため、Operations 画面の操作時にその影響を見落としやすい。

**根拠:** 実際の AppModel と builder から `--dry-run ... --dry-run=false` の生成を確認した。AzCopy 10.32.8 は重複を構文エラーにしない。同バージョンが使用する pflag 1.0.10 の実装では後の代入が有効になるため、実効 dry-run は false になる。転送・削除そのものは実行していない。

**修正:** GUI が管理する予約フラグとの競合を、正規化した引数列に対して検証し、実行前にエラーにする。単に GUI の値を末尾に再付与して黙って上書きし返すのではなく、競合を利用者に説明する。

**完了条件:** copy / sync / remove / set-properties に対する安全フラグの矛盾を拒否する。`--flag=value` と `--flag value` の双方を扱い、競合しない追加フラグは維持する。

参照: [AzCopy の pflag バージョン](https://github.com/Azure/azure-storage-azcopy/blob/v10.32.8/go.mod#L38)、[pflag の代入処理](https://github.com/spf13/pflag/blob/v1.0.10/flag.go#L486-L509)、[Boolean の代入](https://github.com/spf13/pflag/blob/v1.0.10/bool.go#L20-L23)。

### R9 / P2: 空白区切りの SAS 引数を redaction できない

対象: `Sources/AzCopyMacUICore/CredentialRedactor.swift:38-46,81-85`

`--source-sas=VALUE` の形は隠すが、AzCopy が受け付ける `--source-sas VALUE` の形では、個別の引数に redaction を適用しても対応関係を認識できない。
Additional flags から到達可能で、destination 側も同様の問題になる。

**根拠:** `extraFlags: ["--source-sas", "sv=2025-01-05&sp=rw&sig=FAKE_TEST_SIGNATURE"]` を実際の builder に渡すと、プレビューとログ用 API の出力にダミーの SAS がそのまま残った。

**修正:** 引数列を扱う redactor で、秘密フラグと直後の値を一組として処理する。プレビュー・実行ログで共通化し、stdout/stderr のテキスト redaction と責務を区別する。

**完了条件:** source/destination、等号/空白区切り、重複指定で秘密値が出ない。R1 の stream 化でも分割された秘密値を表示しない。R2 の保存防止だけで本件が解消したと扱わない。

### R10 / P2: HTTPS の検証に Azure endpoint の取りこぼしがある

対象: `Sources/AzCopyMacUICore/SecurityPolicy.swift:52-59`

ホスト名の `.blob.core.` / `.file.core.` を大文字小文字を区別して確認しているため、DFS endpoint や大文字を含む Blob endpoint の HTTP URL を拒否できない。

**根拠:** 実際の policy は以下のダミー URL を受け入れた。AzCopy 自体はホスト名を小文字化し、DFS を BlobFS として認識する。

```text
http://example.dfs.core.windows.net/container?sig=FAKE_TEST_SIGNATURE
http://EXAMPLE.BLOB.CORE.WINDOWS.NET/container?sig=FAKE_TEST_SIGNATURE
```

**修正:** scheme/host を正規化し、対応する endpoint 全体で HTTPS 要件を一貫させる。local/emulator の例外を必要とするなら、それだけを明示的な設定で許可する。

**完了条件:** Blob / File / DFS とホスト名の大文字小文字の組合せで HTTP を拒否し、対応する HTTPS を受け入れる。実通信での漏えいが起きたとは断定せず、ここでは検証の欠落を修正対象にする。

参照: [AzCopy 10.32.8 の endpoint 判定](https://github.com/Azure/azure-storage-azcopy/blob/v10.32.8/azcopy/validationUtil.go#L183-L200)。

### R11 / P2: 既定のユーザー認証にサインインへの導線がない

対象: `Sources/AzCopyMacUICore/AuthenticationMethod.swift:46-51`、`Sources/AzCopyMacUICore/AzCopyCommandBuilder.swift:249-260`

関連: `Sources/AzCopyMacUI/AppModel.swift:221-230`、`Sources/AzCopyMacUI/ContentView.swift:196-218`

既定の `.userIdentity` は任意の tenant ID だけを環境変数に設定し、auto-login を有効にしない。
Core に `buildLogin` はあるが、アプリにはそれを呼ぶ経路がなく、Session の操作も Login status / Logout のみ。
キャッシュされた認証情報も SAS もない環境では、この既定モードから private resource へアクセスするためのサインインを開始できない。

**根拠:** `.userIdentity(tenantID: nil).environment` は空、tenant を指定しても `AZCOPY_TENANT_ID` のみ。AzCopy は `AZCOPY_AUTO_LOGIN_TYPE` が空なら tenant を読む前に auto-login 処理を終了する。別の Device Code モードの存在は、この既定モードの導線欠落を解消しない。また、そのモードの案内表示には R1 の修正が必要。

**修正:** Sign In を明示的に追加して `buildLogin` に接続するか、仕様として device auto-login に統一する。選択 tenant を引き継ぎ、認証案内・失敗・キャンセルを通常の実行状態と一貫させる。

**完了条件:** サインイン操作から認証用 invocation が実際に起動されることを AppModel 側で確認する。ログイン文字列を構築するだけの Core テストを代替にしない。

参照: [AzCopy 10.32.8 の auto-login 処理](https://github.com/Azure/azure-storage-azcopy/blob/v10.32.8/common/oauthTokenManager.go#L270-L283)。

### R12 / P2: AzCopy が拒否する Managed Identity Object ID を対応方法として提示する

対象: `Sources/AzCopyMacUICore/AuthenticationMethod.swift:78-79,103-104`

関連: `Sources/AzCopyMacUI/AppModel.swift:498-500,551-552`

Object ID による Managed Identity を選択でき、旧環境変数・旧フラグを生成するが、インストール済み AzCopy 10.32.8 の資格情報生成処理はこの方式を明示的に拒否する。
legacy flag が help の構文解析を通ることと、認証に使えることは別。

**根拠:** 対応する upstream version に `object ID is deprecated and no longer supported for managed identity` というエラー分岐がある。実 Azure ホストで認証は実行していない。

**修正:** 対応 AzCopy の最低バージョンと capability を定義し、非対応の Object ID は無効化して client ID / resource ID の利用を案内する。保存済みの選択値の移行も扱い、Object ID を client ID として黙って転用しない。

**完了条件:** 非対応の方式で実行を開始せず、変更が必要な設定を利用者に伝える。将来の CLI 変更に備え、引数の文字列一致だけでなく capability を判定するケースを追加する。

参照: [AzCopy 10.32.8 の Object ID 拒否処理](https://github.com/Azure/azure-storage-azcopy/blob/v10.32.8/common/oauthTokenManager.go#L743-L751)。

## 設計上の改善点

### 状態と責務の境界

AppModel はフォーム、永続化、認証モデルの生成、コマンド組み立て、プロセス実行、ログ、Azure CLI によるテナント取得を兼ねている。
問題は単にファイルが長いことではなく、Runner が固定生成され、入力変更が保存・表示・実行状態に直接波及する点にある。

Core/GUI の分割は維持し、必要な部分だけに境界を追加する。

- Runner とテナント取得を差し替えられるようにし、AppModel を実ネットワークなしで検証可能にする。
- 保存可能な設定と実行中だけ保持する認証情報を分離する。
- プレビュー検証結果と実行状態を別々に管理する。
- コマンドごとの対応オプションを Core の共通定義に集約し、UI と AppModel の重複した判定を減らす。

### 破壊的操作の確認

`remove`、削除ありの `sync`、ジョブの削除・全消去に GUI の確認フローがない。特に action や削除設定は再起動後も復元される。
これは本レビューで実データの削除を確認した不具合ではなく、安全な GUI としての設計上の不足である。

操作対象・削除設定・dry-run の有無を示して実行直前に確認し、その確認に使った request と実際に起動する request を一致させる。通常の非破壊操作まで一律に確認させる必要はない。

### リリース条件の強制

`docs/plan.md` では coverage / security review を配布条件としているが、`Scripts/package-release.sh:24-38` はそれらを実行せず archive へ進む。
リポジトリに release workflow はなく、PR/push の CI が手動配布スクリプトを強制的に制約する接続もない。

ローカル配布を続けるならスクリプトに共通 preflight を組み込み、失敗時は署名・notarization 前に停止する。CI 配布を採用するなら、必要なジョブと人手承認を明示的な依存関係にする。両方を無目的に増設しない。
また、`security.yml` の `swift package show-dependencies` は依存一覧の生成であり、脆弱性監査そのものではない。現在は外部 package 依存がないため、名称・保証範囲の是正と、依存追加時の監査導入を分けて扱う。

バージョンの単一管理も配布時の検証対象にする。`Info.plist` の `CFBundleVersion` は `1`、Xcode の `CURRENT_PROJECT_VERSION` は `2` で一致していない。ただし、開発版 0.2.0 に対して cask が既公開版 0.1.1 を指している点は、公開前の状態として単独では不具合と判定しない。

## 修正の進め方

| 順序 | 変更単位 | 内容 | 完了の判断 |
| --- | --- | --- | --- |
| 1 | 操作範囲と安全設定 | R5・R7・R8。再帰の明示、追加フラグの構文・競合検証、破壊的操作の確認 | UI の安全設定と実効 argv が一致する |
| 2 | 認証情報の境界 | R2・R9・R10。保存 allowlist、既存設定 migration、引数 redaction、HTTPS 検証 | 新規保存・旧設定移行・表示のどこにも秘密値を残さない |
| 3 | 入出力と実行状態 | R1・R3・R4。並行読み取り、出力イベント、キャンセル、結果保持、テナント取得の同型処理を修正 | 大量出力・認証案内・起動失敗・停止競合を扱い、R2/R9 の保証を維持する |
| 4 | 認証の到達性・互換性 | R11・R12。サインイン導線、tenant 引継ぎ、非対応方式の明示 | GUI から対応する認証フローを開始でき、非対応の保存設定は移行を促す |
| 5 | 配布条件 | R6。coverage の修正、配布 preflight、version 整合性 | 対応ツールチェーンで gate が動き、失敗時は配布工程へ進まない |

順序 4 の認証案内は順序 3 の出力表示に依存する。順序 5 の coverage 修正自体は早期に並行実施してよいが、配布可否の判断は先行する修正の完了後に行う。

各変更は対応する回帰ケースと同じ単位で実施する。AppModel の検証用 Xcode unit-test target を追加するなど、Core 以外も対象にする。
行カバレッジの維持だけを完了条件にせず、上記の振る舞いを直接判定する。

## レビューの範囲と限界

Swift ソース、既存テスト、Xcode/SwiftPM 構成、CI、配布スクリプト、設計文書を対象にした。AzCopy との境界はインストール済み 10.32.8 の help と、対応する公開 upstream source で照合した。
Core の既存 34 テストは成功し、Xcode 27 / Swift 6.4 で署名を無効化したアプリ build は成功したが、上記の機能上の問題は残る。

不具合の再現にはダミー値、隔離した UserDefaults、ローカル fixture のみを使用した。
実 Azure へのログイン・転送・削除、利用者の実資格情報の参照、Developer ID 署名・notarization、macOS 14/15/26 上での実行は行っていない。それらの動作保証は本レビューに含めない。
