# シェルアクセスとプラットフォーム移植

[English](PORTABILITY.md) · [한국어](PORTABILITY.ko.md) · **日本語**

[READMEに戻る](../README.ja.md)

## 範囲

GalpiumのSwift 6コアは、ネイティブアプリ、stdio MCPサーバー、埋め込みワーカーで
共有します。対応製品はmacOS 14以降のApple silicon環境です。同梱のMCP実行
ファイルは、アプリのウィンドウを開かずmacOSのシェルで実行できます。
Linux・Windowsへの移植と、人が直接使う `galpium` CLIはまだ実装されていません。

| 構成要素 | ソース |
| --- | --- |
| 保存・引用・リビジョン・検索 | [GalpiumCore](https://github.com/KimEJ/Galpium/tree/main/Sources/GalpiumCore) |
| stdio MCPエントリーポイント | [GalpiumMCP](https://github.com/KimEJ/Galpium/blob/main/Sources/GalpiumMCP/main.swift) |
| 共有埋め込みワーカー | [GalpiumEmbedder](https://github.com/KimEJ/Galpium/blob/main/Sources/GalpiumEmbedder/main.swift) |
| macOSネイティブ画面 | [GalpiumApp](https://github.com/KimEJ/Galpium/tree/main/Sources/GalpiumApp) |

Swiftは [Linux](https://www.swift.org/install/linux/) と
[Windows](https://www.swift.org/install/windows/) のツールチェーンを提供します。
Galpiumの移植には、以下のパッケージターゲット、Appleフレームワークへの依存、
Darwin専用のプロセス・IPCコードも変更する必要があります。

## macOSのシェルからMCPサーバーを使う

GalpiumをApplicationsにインストールした後、次の例でMCPを初期化してツール一覧を
取得できます。空の一時ライブラリを作成し、終了時に削除します。

```sh
(
  galpium_shell_library=$(mktemp -d)
  trap 'rm -rf "$galpium_shell_library"' EXIT
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"galpium-shell","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | /Applications/Galpium.app/Contents/MacOS/galpium-mcp --library "$galpium_shell_library"
)
```

開発バンドルでは、実行ファイルのパスをチェックアウト内の
`dist/Galpium.app/Contents/MacOS/galpium-mcp` の絶対パスに置き換えます。継続して
使うライブラリは `--library /absolute/path` で指定します。省略すると、選択済み
または既定のライブラリを使用します。

[MCP stdioトランスポート](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
では1行につき1つのJSON-RPCメッセージを送受信します。stdoutにプロトコルの応答、
stderrに診断を出力します。再利用するクライアントはセッションを初期化し、
リクエストIDに対応する応答とエラーを処理してから、その応答に依存する次の要求を
送ります。この例はプロトコルの利用例であり、対話型コマンドを提供するものではありません。

## コマンドラインクライアントを作る

小さなCLIで検索・読み取り・インポート・エクスポートを提供し、読みやすい結果や
JSONを出力できます。このインターフェースは、現在のmacOS MCPサーバーを使って
プラットフォーム移植とは独立して開発できます。

`GalpiumCore` を直接使うか、`galpium-mcp` を起動して公開されたツールスキーマに
従います。書き込み前に現在のリビジョンを読み、`expected_revision` を渡し、競合を
呼び出し側に伝えます。SQLiteや保存されたJSONへの直接書き込みは、リビジョン検査、
引用の検証、検索インデックスの更新を迂回します。

CLIは結果の表示、引数の処理、プロトコルエラーを担当します。保存、原本の保持、
検索は共有サービスの契約に従います。

## プラットフォームの境界

以下のアダプターは移植作業の提案であり、既存のクロスプラットフォーム対応ではありません。

| 領域 | 現在の実装 | 移植作業 |
| --- | --- | --- |
| パッケージターゲット | SwiftUI・AppKitのアプリターゲットを含むmacOSパッケージ | macOS画面をビルドせずに済むヘッドレスターゲットを分離し、プラットフォーム別アダプターを選択します。 |
| 保存 | `CSQLite`、SQLite WAL・JSON関数・`STRICT` テーブル・FTS5 trigram検索 | システムライブラリ接続と必要なSQLite機能を提供します。トランザクション・外部キー・リビジョン検査を維持します。 |
| ハッシュ・ベクトル計算 | CryptoKit・Accelerate | SHA-256とベクトル演算を移植可能な実装に分離し、バイト識別値と検索順位を維持します。 |
| PDFテキスト | PDFKitによる抽出と保存済み抽出ID・ページ位置 | ページ境界を維持し、固有の抽出方式IDを使う抽出器を追加します。既存の抽出結果・引用を保持し、出力が違う場合は新しい抽出IDを付けます。 |
| メディア前処理 | CoreGraphics・ImageIO・PDFKit・AVFoundation | 明示的な前処理方針とキャッシュ領域を使い、画像のデコード・ページ描画・音声変換を実装します。 |
| ワーカーIPC・プロセス管理 | Darwin呼び出し・Unixソケット・非公開ディレクトリ・起動ロック・ワーカーリース | Linuxの対応実装または保護されたWindows IPCを使います。ユーザーごとの所有権・認証・重複起動防止・子プロセスの終了処理を維持します。 |
| パス・アセット探索 | POSIX絶対パス・macOSライブラリの場所・`.app` アセット | OS固有の保存先、Windowsドライブ・UNCパス、アプリバンドル外のアセットを扱います。正規化パスの識別を維持し、リンク処理を確認します。 |
| モデル実行 | 固定されたllama.cpp・モデル・プロジェクター・macOSライブラリ | OS・アーキテクチャ別に実行ファイルと `.so`・`.dll` 依存ファイルを同梱します。対象環境でリソース要件を確認します。 |
| 画面 | SwiftUI・AppKit・macOSネイティブビューアー | ヘッドレスサービスの提供後に、別のデスクトップ・Web画面を実装します。 |

メディアアダプターはページ・時間位置を維持する必要があります。現在の方針は、
最大辺2,048ピクセルのJPEG画像、PDFの全ページ描画、連続する20秒の音声区間を
モノラル16 kHz PCM16 WAVに変換する処理です。方針を変える場合は新しい埋め込み
キャッシュ領域が必要です。入力の契約全体は [意味検索](SEMANTIC-SEARCH.md) を
参照してください。

現在のワーカーは `0700` のディレクトリと `0600` のソケット・ロック・キーファイルを
使います。Windowsでは同等のユーザー固有ACLと、他のユーザーがなりすませない
IPCエンドポイントが必要です。起動ロックとワーカーリース、ランタイム認証、
ワーカー停止時に推論用子プロセスを終了する動作を維持します。

## 推奨する実装順序

1. **ヘッドレスのプラットフォーム境界を分離。** 既存のmacOSアダプターを維持しながら、
   保存・抽出・メディア・計算・パス・ワーカー通信を分離します。
2. **Linuxのヘッドレス対応を実装。** 原本・リビジョン・引用・キーワード検索から始め、
   埋め込みランタイムとメディアアダプターを追加します。未対応形式を明示します。
3. **ネイティブWindowsのヘッドレス対応を実装。** ネイティブパス・プロセス起動・
   保護されたIPC・モデル配布を追加します。将来WSLで動かすLinux移植は、
   ネイティブWindowsアプリとは別の対応対象です。
4. **インターフェースを追加。** ヘッドレス契約をCLI・デスクトップ・Webクライアントで
   再利用します。結果の表示を保存・検索から分離します。

## 互換性と対応の基準

移植では原本のバイト・ハッシュ、出典・資料ID、抽出結果、正確な引用文、ページ・
時間位置、リビジョン履歴を維持する必要があります。新しい環境で異なるテキストが
抽出されても、既存の抽出結果を保持します。派生データのキーワード・ベクトル索引は
独立して再生成できます。

バックアップのコピーや一時ライブラリで変更した境界を確認します。保存はデータの
往復・移行、同時アクセスは書き込み競合、抽出はページ・引用の保持、検索はキャッシュ
識別・ワーカーの寿命を確認します。OS・アーキテクチャ別の配布実行ファイル、MCPの
初期化、案内した操作を確認してから対応を表明します。未対応機能とランタイムの
リソース要件も記録します。

共有契約は [アーキテクチャ](ARCHITECTURE.md)、現在のmacOS手順は
[ビルドと配布](RELEASE.md)、配布済みの変更は
[変更履歴](CHANGELOG.ja.md) を参照してください。
