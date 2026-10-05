# Galpium

## Platform and purpose
macOS 14+ native personal wiki. Preserve original material and let the user or
connected AI compile linked Markdown, inspect provenance, compare changes and
restore history. The application works offline without accounts or a server.

## Confirmed direction
SwiftUI shell, AppKit/TextKit editing, shared Swift core, SQLite storage and a
bundled stdio MCP executable. No third-party Swift packages. Bundled llama.cpp and EmbeddingGemma provide offline retrieval. User explicitly
selected the native implementation. Keep grouped pins/recent pages, unified materials
(text/files with immutable originals and extraction snapshots), tags, archives,
footnote citations, backlinks, revision comparison and focused
split editing within native macOS controls.

## Completion criteria
Run a packaged app; write Korean Markdown and preview; save/reopen; retain drafts;
import originals and attachments; search and filter; archive/restore; compare
history; Markdown export and source-preserving Galpium backup/restore;
connect the same library through MCP with revision guards; pass core and protocol
regressions and inspect the running native UI. Release artifacts and setup docs
must be reproducible. Public signing/notarization needs a publisher certificate.

## Product boundaries
Single local personal library, multiple safe SQLite writers. AI composition is
done by connected clients. Direct authored pages need no source. Original citations
validate exact quotes and preserve immutable extraction/page locations. Active-page search combines keyword matches with local multilingual EmbeddingGemma
paragraph retrieval. Model/runtime assets are bundled; no runtime downloads occur. No account identity, Docker service,
server OAuth, public hosting, cloud sync or built-in AI chat in the native app.

## Data principles
Originals and past revisions are immutable. Writes require expected revisions.
Conflicts preserve drafts and require explicit comparison. Attachments live
separately and are never removed by archive/cancel. Backup imports are
additive; no destructive replacement of an existing library.
