# Galpium

**English** · [한국어](README.ko.md) · [日本語](README.ja.md)

Galpium is a personal wiki for macOS. Write linked Markdown pages, keep the
materials behind them, and connect an AI client to help organize your knowledge.
Pages, original files and revision history stay in a local library on your Mac.

[Download](https://github.com/KimEJ/Galpium/releases/tag/v0.0.2) ·
[User guide](docs/USER-GUIDE.en.md) · [Changelog](docs/CHANGELOG.md)

![A Galpium wiki page with related links and source citations](docs/images/wiki-page.jpg)

*Read pages with related links and citations.*

## Features

- **Write and connect pages.** Edit Markdown with previews, tables and attachments.
  Link related pages and follow their backlinks.
- **Keep sources close.** Collect text, PDFs, images, audio and other files in
  Materials. Add citation footnotes that open the quoted original passage.
- **Search locally.** Find pages and materials by keywords or meaning, including
  images, PDF page visuals and audio segments, using text queries.
- **Keep a history.** Recover drafts, compare revisions, restore earlier content
  and back up the whole library.
- **Work with AI.** Let ChatGPT desktop or another MCP client read and update the
  same wiki. Keep prompts and chat links as source materials alongside the result.

Writing, storage and search work offline. AI-assisted writing uses the client
you connect; that client's data-sharing policy applies when it reads the wiki.
The interface supports English, Korean and Japanese, with a language choice in settings.

![Galpium materials list with file types and reference counts](docs/images/materials.jpg)

*Find original materials and see their reference counts.*

## Install

The downloadable app supports **Apple silicon Macs running macOS 14 or later**.

1. Download [Galpium-0.0.2-arm64.dmg](https://github.com/KimEJ/Galpium/releases/download/v0.0.2/Galpium-0.0.2-arm64.dmg).
2. Drag **Galpium.app** into **Applications** and open it.
3. Choose **New Page** to start writing, or add files in **Materials**.

The app includes the search model. If macOS blocks the first launch, allow the app
in **System Settings → Privacy & Security**.

## Connect ChatGPT desktop

Install Galpium and ChatGPT in **Applications**, then:

1. Download [Galpium-Codex-Plugin-0.0.2.zip](https://github.com/KimEJ/Galpium/releases/download/v0.0.2/Galpium-Codex-Plugin-0.0.2.zip) and extract it.
2. Open the **Galpium-Codex** folder. It contains **Install Galpium Plugin.command**,
   a **plugin** folder, and **LICENSE** and **NOTICE** files.
3. Double-click **Install Galpium Plugin.command** and wait for the Terminal
   window to display **Galpium installed.**
4. Quit ChatGPT with **⌘Q**, reopen it, and select **@Galpium** in a new local chat.

The installer uses ChatGPT's bundled runtime; it does not require a separate CLI
installation or manual settings edits. See the [user guide](docs/USER-GUIDE.en.md)
for connection status, other MCP clients and day-to-day use.

## Build from source

The app, core and MCP server are written in Swift. On macOS 14 or later with
Xcode/Swift 6 installed, compile the source with:

```sh
git clone https://github.com/KimEJ/Galpium.git
cd Galpium
swift build
```

To create a runnable `.app` bundle with the search model, follow the
[development and release guide](docs/RELEASE.md).
See [Architecture](docs/ARCHITECTURE.md) for the code structure and design rules.
For shell access and work toward Linux or Windows support, see the
[portability guide](docs/PORTABILITY.md).

## Scope

Galpium uses personal local libraries and has no built-in cloud sync.
Image and audio search locates related originals; it does not produce OCR text,
transcripts or verified quotations. PDF text can be quoted when it is readable.
Video indexing is not supported.

## License

Galpium's source code, plugin and documentation use [Apache License 2.0](LICENSE).
Licenses for bundled models and external components are listed in
[Third-party notices](THIRD-PARTY-NOTICES.md).
