# Galpium

[English](README.md) · [한국어](README.ko.md) · **日本語**

原本資料、リンクでつながる知識、AIを使った文書作成を一つのローカルライブラリで
管理する、macOSネイティブの個人用Wikiです。

[v0.0.1をダウンロード](https://github.com/KimEJ/Galpium/releases/tag/v0.0.1) ·
[ユーザーガイド](docs/USER-GUIDE.ja.md)

## 主な機能

- ネイティブエディタでMarkdownを編集し、表や画像をプレビューできます。
- テキスト、PDF、ファイルを資料としてまとめ、検索や参照数の確認ができます。
- 原文のハッシュ、抽出スナップショット、ページ位置を保持する脚注で、実際の原文を引用できます。
- 韓国語・英語・日本語のオフラインハイブリッド検索で、関連する知識を探せます。
- ChatGPTデスクトップや他のMCPクライアントを同じライブラリに接続できます。
  改訂の競合チェック、履歴、アーカイブと復元、全体バックアップに対応しています。
- 依頼したプロンプトとチャットの出典を保存できます。Web URLとローカルChatGPTの
  ディープリンクは、同じ出典URL欄に入力できます。

Galpiumはオフラインで利用できます。AIによる文書作成は接続したクライアントが
行い、アプリに同梱されたEmbeddingGemmaは検索用のモデルです。接続した
クライアントは、読み取りを依頼した資料をモデルの提供元へ送信する場合があります。

## インストール

公開バイナリの対象は **Apple silicon、macOS 14以降** です。
Intel Macではソースからビルドできますが、今回のリリースにIntel用バイナリは含まれていません。

1. [Galpium-0.0.1-arm64.dmg](https://github.com/KimEJ/Galpium/releases/download/v0.0.1/Galpium-0.0.1-arm64.dmg)をダウンロードします。
2. **Galpium.app**を **Applications** フォルダに移動して起動します。
3. ページを作成するか資料を追加します。検索モデルはアプリに同梱されています。

この配布版は **アドホック署名で、Appleの公証を受けていません**。
macOSで起動の承認を求められた場合は、**システム設定 → プライバシーとセキュリティ**
で確認してください。Developer ID署名と公証を行うには、配布者の署名資格情報が必要です。

既定のライブラリは `~/Library/Application Support/Galpium/` です。アプリ設定で
別のライブラリを選択できます。ウインドウを閉じてもMCP接続のためにアプリは動作を
続けます。Dockまたはメニューバーから再び開き、**⌘Q**で終了できます。

画面は韓国語・英語・日本語に対応しています。既定ではシステムの言語に従い、
**設定 → アプリ設定… → 言語**で変更できます。文書と資料の原文は維持されます。

## ChatGPTデスクトップとの接続

GalpiumとChatGPTをApplicationsにインストールしてから、次の操作を行います。

1. [Galpium-Codex-Plugin-0.0.1.zip](https://github.com/KimEJ/Galpium/releases/download/v0.0.1/Galpium-Codex-Plugin-0.0.1.zip)をダウンロードして展開します。
2. 展開された **Galpium-Codex** フォルダを開きます。中にはインストーラの
   **Install Galpium Plugin.command**、プラグインを含む **plugin** フォルダ、
   **LICENSE** と **NOTICE** ファイルがあります。
3. **Install Galpium Plugin.command**をダブルクリックします。ターミナルが開き、
   プラグインがインストールされます。**Galpium installed.**と表示されるまで待ちます。
4. ChatGPTを **⌘Q** で完全に終了してから再び起動し、新しいローカルチャットで **@Galpium** を選択します。

インストーラはChatGPTに同梱されたランタイムを使います。別途CLIをインストールしたり、
設定を手動で編集したりする必要はありません。このパッケージはローカルマーケットプレイスの
プラグインをインストールするため、展開したインストーラを使用してください。

他のMCPクライアントでは、stdio接続を設定します。

```json
{
  "mcpServers": {
    "galpium": {
      "command": "/Applications/Galpium.app/Contents/MacOS/galpium-mcp"
    }
  }
}
```

別のライブラリを使うには `"args": ["--library", "/absolute/path/to/library"]` を
追加します。同梱のWikiスキルは関連するページを統合し、分かりやすい文章や静的な図表を
作成して、原文の引用と依頼の背景を保存します。

## ダウンロードの検証

DMGとプラグインZIPを保存したフォルダに
[SHA256SUMS](https://github.com/KimEJ/Galpium/releases/download/v0.0.1/SHA256SUMS)を
ダウンロードし、次を実行します。

```sh
shasum -a 256 -c SHA256SUMS
```

公開リリースのファイルと `v0.0.1` タグは変更できないように固定されています。
更新は既存のダウンロードを差し替えず、新しいバージョンとリリースで提供します。

## ビルドと検証

macOS 14以降、Xcode/Swift 6、Python 3が必要です。外部のSwiftパッケージ、
Node、Dockerは不要です。初回ビルドではチェックサムで固定された検索モデルと
ランタイムをダウンロードし、以後はローカルキャッシュを再利用します。

```sh
git clone https://github.com/KimEJ/Galpium.git
cd Galpium
sh scripts/build-app.sh
open dist/Galpium.app
```

変更した箇所に合わせて検証します。例：

```sh
GALPIUM_SEMANTIC_DISABLED=1 swift test --disable-sandbox --filter ChatLinkTests
```

`sh scripts/check.sh` は開発用の全体検証を実行します。リリースパッケージは
`sh scripts/package-release.sh` で作成します。
[リリース手順](docs/RELEASE.md)、[アーキテクチャ](docs/ARCHITECTURE.md)、
[意味検索](docs/SEMANTIC-SEARCH.md)、[デザイン規則](DESIGN.md)も参照してください。

## 現在の制限

- 画像やスキャンPDFのOCRには対応していません。テキストを含むPDFはローカルで抽出します。
- ライブラリは個人用のローカル保存で、クラウド同期機能は含まれていません。
- 公開バイナリはApple silicon用で、まだAppleの公証を受けていません。

## ライセンス

Galpiumのソースコード、プラグイン、ドキュメントは
[Apache License 2.0](LICENSE)で公開しています。同梱のEmbeddingGemmaの重みには
[Gemma利用規約](https://ai.google.dev/gemma/terms)が適用されます。
llama.cppと同梱の外部コードは、それぞれのライセンスを維持します。
[サードパーティに関する告知](THIRD-PARTY-NOTICES.md)を参照してください。
