# Architecture

Galpium is a native macOS wiki application with a shared Swift 6 core. The app,
stdio MCP server and embedding worker use the same storage and retrieval code.
The supported release targets macOS 14 or later on Apple silicon. Platform
boundaries and a headless porting plan are described in [portability](PORTABILITY.md).

## Components

| Component | Responsibility |
| --- | --- |
| [GalpiumCore](https://github.com/KimEJ/Galpium/tree/main/Sources/GalpiumCore) | Library storage, originals, citations, revisions, retrieval, localization and MCP protocol |
| [GalpiumApp](https://github.com/KimEJ/Galpium/tree/main/Sources/GalpiumApp) | SwiftUI interface, AppKit/TextKit editor, native viewers, navigation and menu bar |
| [GalpiumMCP](https://github.com/KimEJ/Galpium/tree/main/Sources/GalpiumMCP) | Independent stdio server entry point |
| [GalpiumEmbedder](https://github.com/KimEJ/Galpium/tree/main/Sources/GalpiumEmbedder) | Shared offline embedding worker |
| [plugin](https://github.com/KimEJ/Galpium/tree/main/plugin) | ChatGPT plugin, launcher and wiki authoring skill |
| [scripts](https://github.com/KimEJ/Galpium/tree/main/scripts) | Asset preparation, packaging and development utilities |

The Swift package uses the system SQLite library and Apple frameworks; it has no
third-party Swift package dependencies. The embedding runtime and model assets
are bundled separately.

## Library model

`wiki.sqlite3` is the authoritative database. Original file bytes live in the
library's `attachments` directory. The data model separates preserved evidence
from authored knowledge:

| Record | Contract |
| --- | --- |
| Source | Immutable imported text with its provenance URL and SHA-256 identity |
| Material | Unified metadata for text or a file, including title, kind, archive state and original hash |
| Extraction | Preserved readable text with an extraction-method identity and original page numbers |
| Wiki page | Authored Markdown, relationships, citations, tags and current revision |
| Revision | Immutable historical page snapshot |
| Citation | Exact quotation bound to a material, original hash, extraction snapshot and page |

Material titles and archive states can change without replacing original bytes.
Deleting a material requires it to have no references in current pages, history
or drafts. A material link can denote an attachment; it does not by itself assert
that the attachment supports a claim.

Citation validation checks both the original identity and the exact quotation
in the preserved extraction page. An image or audio search match identifies a
location to inspect; it does not create verified quotation text.

## Writes and concurrency

SQLite uses WAL, foreign keys and transactions. Page writes append a revision
and update current content and relationships together. The `expected_revision`
guard rejects a write when another client has changed the record. Restoring a
page creates a new revision rather than rewriting its history.

The app and MCP process may access the same library concurrently. Both write
through `WikiStore`; integrations should use the core API or MCP tools rather
than modify database tables or stored JSON directly.

Older supported library formats migrate transactionally after a local database
backup. An application rejects a library format newer than it understands.
Full backups include a consistent database snapshot, original files, checksums
and notices. Import verifies identities and rejects conflicting records instead
of silently replacing existing data.

## App and MCP access

The app provides native reading, editing and material management. It can remain
running after its window closes, and reopening it restores a window. The bundled
`galpium-mcp` executable works independently of an open app window. Library
selection can be supplied with `--library /absolute/path`; otherwise it uses
the selected or default library.

The MCP service exposes materials, pages, exact citations, revisions, search and
structural inspection through the same core. The plugin's authoring skill guides
AI clients to read originals, integrate related pages and preserve citations and
request provenance. Generated wiki prose remains distinct from original evidence.

Provenance URLs accept HTTP(S) and constrained `codex://threads/<UUID>` links.
These links provide navigation back to a source or chat; they are not commands
or additional evidence content. The local server stores and retrieves data from
the library. An attached AI client determines how the content it receives is used.

## Search and derived data

Keyword search is available independently of model inference. Semantic search
uses bundled EmbeddingGemma 2 assets to index text, images, PDF pages and audio
segments in a shared 768-dimensional vector space. The app and MCP clients share
one private embedding worker per library. The worker schedules foreground queries
between indexing operations and releases idle model processes.

The semantic index is a regenerable cache outside `wiki.sqlite3`. Its identity
includes model and projector hashes and the preprocessing policy. Changing those
inputs creates a separate cache; originals, citations and revision history retain
their identities. Search results are checked against current revisions and filters
before being returned.

See [semantic search](SEMANTIC-SEARCH.md) for preprocessing, ranking and worker
lifecycle, [build and release](RELEASE.md) for development, and
[change history](CHANGELOG.md) for release-specific changes.
Product boundaries are described in [product scope](https://github.com/KimEJ/Galpium/blob/main/PRODUCT.md); interface
conventions are documented in [interface design](../DESIGN.md).
