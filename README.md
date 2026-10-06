# Galpium

**English** · [한국어](README.ko.md) · [日本語](README.ja.md)

A native macOS personal wiki that keeps your original materials, linked knowledge,
and AI-assisted writing in one local library.

[Download v0.0.1](https://github.com/KimEJ/Galpium/releases/tag/v0.0.1) ·
[User guide](docs/USER-GUIDE.en.md)

## What it does

- Write and edit Markdown with a native editor, preview, tables and images.
- Keep text, PDFs and files together as materials, with search and reference counts.
- Cite exact original passages with footnotes that retain the original hash,
  extraction snapshot and page location.
- Find related knowledge with offline Korean, English and Japanese hybrid search.
- Connect ChatGPT desktop and other MCP clients to the same library, with revision
  guards, history, archive/restore and full backups.
- Preserve requests and chat provenance. Web URLs and local ChatGPT deep links
  share the same source URL field.

Galpium works offline. AI writing is performed by the connected client; the app
bundles EmbeddingGemma for search, not a chat model. The client you connect may
send the materials you ask it to read to its model provider.

## Install

The published binary targets **Apple silicon, macOS 14 or later**. Intel users
can build from source on an Intel Mac; an Intel binary is not included in this release.

1. Download [Galpium-0.0.1-arm64.dmg](https://github.com/KimEJ/Galpium/releases/download/v0.0.1/Galpium-0.0.1-arm64.dmg).
2. Drag **Galpium.app** to **Applications** and open it.
3. Create a page or add materials. The search model is already bundled.

This release is **ad-hoc signed and not Apple-notarized**. macOS may require
explicit approval in **System Settings → Privacy & Security** before opening it.
A Developer ID/notarized distribution requires publisher signing credentials.

The default library is `~/Library/Application Support/Galpium/`. Choose a different
library in the app's settings. Closing the window keeps the app available to MCP;
reopen it from the Dock or menu bar. Quit with **⌘Q**.

The interface supports Korean, English and Japanese. It follows the system
language by default; choose another language in **Settings → App Settings… →
Language**. Your documents and materials retain their original language.

## Connect ChatGPT desktop

Install Galpium and ChatGPT in Applications. Then:

1. Download [Galpium-Codex-Plugin-0.0.1.zip](https://github.com/KimEJ/Galpium/releases/download/v0.0.1/Galpium-Codex-Plugin-0.0.1.zip) and extract it.
2. Open the extracted **Galpium-Codex** folder. It contains the installer
   **Install Galpium Plugin.command**, the **plugin** folder, and **LICENSE** and
   **NOTICE** files.
3. Double-click **Install Galpium Plugin.command**. A Terminal window opens and
   installs the plugin. Wait for the **Galpium installed.** message.
4. Quit ChatGPT with **⌘Q**, reopen it, and select **@Galpium** in a new local chat.

The installer uses ChatGPT's bundled runtime. A separate CLI installation or
manual configuration edit is not required. This package installs a local
marketplace plugin; use the extracted installer for this distribution.

For another MCP client, configure stdio:

```json
{
  "mcpServers": {
    "galpium": {
      "command": "/Applications/Galpium.app/Contents/MacOS/galpium-mcp"
    }
  }
}
```

Add `"args": ["--library", "/absolute/path/to/library"]` to select another library.
The bundled wiki skill integrates related pages, writes clear prose and static
diagrams, and preserves original citations and the request context.

## Verify the download

Download [SHA256SUMS](https://github.com/KimEJ/Galpium/releases/download/v0.0.1/SHA256SUMS)
into the same directory as the DMG and plugin ZIP, then run:

```sh
shasum -a 256 -c SHA256SUMS
```

Published release assets and the `v0.0.1` tag are immutable. Updates use a new
version and release instead of replacing an existing download.

## Build and test

Requires macOS 14+, Xcode/Swift 6 and Python 3. No third-party Swift packages,
Node or Docker are required. The first build downloads checksum-pinned search
model and runtime assets; subsequent builds reuse the local cache.

```sh
git clone https://github.com/KimEJ/Galpium.git
cd Galpium
sh scripts/build-app.sh
open dist/Galpium.app
```

Run checks appropriate to your change. For example:

```sh
GALPIUM_SEMANTIC_DISABLED=1 swift test --disable-sandbox --filter ChatLinkTests
```

`sh scripts/check.sh` runs the full development checks. Package releases with
`sh scripts/package-release.sh`. See [release instructions](docs/RELEASE.md),
[architecture](docs/ARCHITECTURE.md), [semantic search](docs/SEMANTIC-SEARCH.md)
and [design conventions](DESIGN.md).

## Current limits

- Image/scanned-PDF OCR is not included; searchable PDF text is extracted locally.
- Workspaces are personal local libraries, without built-in cloud sync.
- Public binaries are Apple silicon only and are not yet Apple-notarized.

## License

Galpium source code, plugin and documentation are licensed under
[Apache License 2.0](LICENSE). Bundled EmbeddingGemma weights use the
[Gemma Terms of Use](https://ai.google.dev/gemma/terms); llama.cpp and its vendors
retain their respective licenses. See [third-party notices](THIRD-PARTY-NOTICES.md).
