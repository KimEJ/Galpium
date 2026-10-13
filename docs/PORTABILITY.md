# Shell access and platform ports

**English** · [한국어](PORTABILITY.ko.md) · [日本語](PORTABILITY.ja.md)

[Back to README](../README.md)

## Scope

Galpium's Swift 6 core is shared by the native app, stdio MCP server and embedding
worker. The supported product is macOS 14 or later on Apple silicon. The bundled
MCP executable can run from a macOS shell without an open app window. Linux and
Windows ports and a human-facing `galpium` CLI are not implemented.

| Component | Source |
| --- | --- |
| Storage, citations, revisions and retrieval | [GalpiumCore](https://github.com/KimEJ/Galpium/tree/main/Sources/GalpiumCore) |
| stdio MCP entry point | [GalpiumMCP](https://github.com/KimEJ/Galpium/blob/main/Sources/GalpiumMCP/main.swift) |
| Shared embedding worker | [GalpiumEmbedder](https://github.com/KimEJ/Galpium/blob/main/Sources/GalpiumEmbedder/main.swift) |
| Native macOS interface | [GalpiumApp](https://github.com/KimEJ/Galpium/tree/main/Sources/GalpiumApp) |

Swift supplies [Linux](https://www.swift.org/install/linux/) and
[Windows](https://www.swift.org/install/windows/) toolchains. A Galpium port also
needs changes to the package targets, Apple-framework dependencies and
Darwin-specific process and IPC code described below.

## Use the MCP server from a macOS shell

After installing Galpium in Applications, use this example to initialize MCP and
list its tools. It creates an empty temporary library and deletes it on exit.

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

For a development bundle, substitute the absolute checkout path to
`dist/Galpium.app/Contents/MacOS/galpium-mcp`. For ongoing use, supply a persistent
library with `--library /absolute/path`. Omitting the argument uses the selected
or default library.

The [MCP stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
exchanges one JSON-RPC message per line. stdout carries protocol responses and
stderr carries diagnostics. A reusable client should initialize the session,
match responses by request ID and handle errors before issuing dependent requests.
The example is a protocol demonstration; it does not provide interactive commands.

## Build a command-line client

A thin CLI can expose search, read, import and export operations with readable
output or JSON. This interface can be developed against the current macOS MCP
server independently of platform porting.

Use `GalpiumCore` directly or launch `galpium-mcp` and follow its advertised tool
schemas. Obtain the current revision before a write, submit `expected_revision`
and surface conflicts to the caller. Direct writes to SQLite or stored JSON
bypass revision guards, citation validation and search-index maintenance.

The CLI should handle presentation, argument parsing and protocol errors. Storage,
original preservation and retrieval remain in the shared service contract.

## Platform boundaries

The adapters below are proposed porting work, not existing cross-platform support.

| Area | Current implementation | Porting work |
| --- | --- | --- |
| Package targets | macOS package with SwiftUI/AppKit app targets | Separate headless build targets and select platform adapters without building the macOS interface. |
| Storage | `CSQLite`, SQLite WAL, JSON functions, `STRICT` tables and FTS5 trigram search | Provide the system-library binding and required SQLite features. Preserve transactions, foreign keys and revision guards. |
| Hashes and vector math | CryptoKit and Accelerate | Isolate SHA-256 and vector operations behind portable implementations, retaining byte identities and ranking behavior. |
| PDF text | PDFKit extraction with preserved extraction IDs and page positions | Add a page-aware extractor with its own method identity. Retain existing snapshots and citations; different output receives a new extraction ID. |
| Media preprocessing | CoreGraphics, ImageIO, PDFKit and AVFoundation | Implement image decoding, page rendering and audio conversion with an explicit preprocessing policy and cache namespace. |
| Worker IPC and process supervision | Darwin calls, Unix sockets, private directories, startup locks and worker leases | Use Linux equivalents or protected Windows IPC. Preserve per-user ownership, authentication, duplicate-worker prevention and child-process cleanup. |
| Paths and asset lookup | Absolute POSIX paths, macOS library location and `.app` assets | Support native library locations, Windows drive/UNC paths and assets outside app bundles. Preserve canonical-path identity and review link handling. |
| Model runtime | Pinned llama.cpp, model/projector files and macOS libraries | Package the runtime and its `.so`/`.dll` dependencies for each OS/architecture. Establish resource requirements on the target environment. |
| Interface | SwiftUI, AppKit and native macOS viewers | Build a separate desktop or web front end after the headless service is available. |

Media adapters must preserve page and time positions. The current policy produces
JPEG images with a maximum edge of 2,048 pixels, renders every PDF page, and
converts consecutive 20-second audio segments to mono 16 kHz PCM16 WAV. A changed
policy requires a new embedding-cache namespace; see
[semantic search](SEMANTIC-SEARCH.md) for the full input contract.

The current worker uses `0700` directories and `0600` sockets, locks and key files.
A Windows implementation needs equivalent user-specific ACLs and an IPC endpoint
that other users cannot impersonate. Preserve both the startup lock and the
worker lease, runtime authentication, and termination of inference children when
the worker stops.

## Recommended sequence

1. **Extract headless platform boundaries.** Separate storage, extraction, media,
   math, paths and worker communication while preserving the existing macOS adapters.
2. **Implement Linux headless support.** Start with originals, revisions, citations
   and keyword search, then add the embedding runtime and media adapters. Expose
   unsupported formats explicitly.
3. **Implement native Windows headless support.** Add native paths, process launch,
   protected IPC and runtime packaging. A future Linux port running under WSL is
   a separate support target from a native Windows application.
4. **Add interfaces.** Reuse the headless contract in a CLI, desktop or web client.
   Keep presentation outside storage and retrieval.

## Compatibility and support criteria

A port must preserve original bytes and hashes, source/material IDs, extraction
snapshots, exact quotations, page/time positions and revision history. Keep older
extractions when a new platform produces different text. Derived keyword and
vector indexes can be rebuilt independently.

Use a backup copy or disposable library to check the changed boundary: data
round-trips and migrations for storage, write conflicts for concurrency, page and
quotation preservation for extraction, and cache identity and worker lifecycle
for search. Verify the packaged executable, MCP initialization and advertised
operations on each OS/architecture before declaring it supported. Record any
unsupported features and the runtime's resource requirements.

See [architecture](ARCHITECTURE.md) for the shared contracts,
[build and release](RELEASE.md) for the current macOS workflow, and
[change history](CHANGELOG.md) for released changes.
