# Product scope

Galpium is a personal wiki for macOS. It stores original materials, authored
Markdown pages and their relationships in a local library. Pages can be written
directly or maintained through a connected AI client.

## Main workflows

- Collect text and files as materials, then search and reference them from pages.
- Write and preview Markdown with a native editor, tables and images.
- Connect related pages with links, tags, pins and backlinks.
- Cite exact original passages with footnotes linked to preserved extraction snapshots.
- Compare page revisions, archive pages and restore earlier versions.
- Export Markdown or transfer a complete library through backup and import.
- Use the same library from the app and the standalone MCP server.

## Data model

Original bytes and text are immutable. Extracted text is retained with its method,
hash and page locations. Citations refer to a specific original and extraction;
renaming a material does not change an existing citation.

Page edits create revisions. Expected-revision checks prevent concurrent writers
from silently replacing newer content. Local drafts retain unfinished edits.
Archiving retains originals, attachments and revision history. Backup imports add
compatible records and reject divergent records instead of replacing a library.

Search indexes are derived data. They can be rebuilt without changing originals
or authored pages. Search results identify possible matches; they do not validate
the factual claims made in a page.

## Runtime and platform

The macOS app and MCP server share a Swift core backed by SQLite. The app uses
SwiftUI and AppKit/TextKit. EmbeddingGemma 2 and llama.cpp are bundled for local
text, image, PDF-page and audio retrieval.

Galpium runs without an account or a hosted service. AI composition is performed
by the connected client, which may send requested content to its model provider.
Cloud synchronization, shared libraries and a built-in chat model are outside the
current product scope. OCR, transcription and video indexing are not included.

See the [user guide](docs/USER-GUIDE.en.md) for workflows,
[architecture](docs/ARCHITECTURE.md) for implementation, and
[platform extension guide](docs/PORTABILITY.md) for work toward other environments.
