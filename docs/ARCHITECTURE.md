# Architecture

Galpium targets macOS 14+ with Swift 6. The app and bundled stdio MCP server use
one shared Swift core and SQLite library. No third-party Swift packages are used.

## Storage and preservation

SQLite WAL, foreign keys, transactional revision guards and append-only history
protect concurrent writes. Original text, file bytes and extraction snapshots
are preserved separately from authored wiki pages. Sources and materials retain
SHA-256 identities; citations bind an exact quote to a source version, extraction
snapshot and page. Renaming does not change source bytes or existing citations.

Files live outside SQLite. Full backup copies a consistent database snapshot,
files, checksums and notices. Imports are additive and reject divergent data
rather than silently replacing a library. Older library formats migrate with a
local backup; a newer format is rejected by an older application.

## App and MCP

The SwiftUI app uses AppKit/TextKit editing and native macOS menus, PDFKit
extraction and system SQLite/CryptoKit. A closed window can be reopened while
the app stays in the background. The independent MCP process uses the same
selected library and exposes 21 tools for materials, documents, exact citations,
revisions, search and structural inspection. Writes require expected revisions.

The wiki skill controls AI-assisted writing. It uses preserved originals as
factual evidence and keeps generated prose, figures and request context distinct.
Local ChatGPT provenance links are navigation-only URLs in the existing source
URL field; arbitrary app commands are not allowed.

## Retrieval

Keyword retrieval and bundled EmbeddingGemma paragraph vectors are combined.
One private worker per library shares model memory between app and MCP clients,
serves foreground queries between indexing work, and exits after an idle period.
Its runtime listens on loopback with a generated key; clients use a private Unix
socket. The derived index is regenerable and never becomes the authoritative
source for documents, originals or history. See [semantic search](SEMANTIC-SEARCH.md).

## Components

| Path | Responsibility |
| --- | --- |
| `Sources/GalpiumCore` | Storage, originals, citations, retrieval, localization and MCP protocol |
| `Sources/GalpiumApp` | Native app, reader, editor, navigation and menu bar |
| `Sources/GalpiumMCP` | Standalone stdio entry point |
| `Sources/GalpiumEmbedder` | Shared offline embedding worker |
| `plugin` | Local ChatGPT plugin, launcher and wiki authoring skill |
| `scripts` | Pinned assets, packaging, checks and disposable sample generation |
