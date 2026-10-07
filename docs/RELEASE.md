# Build and release

## Local build

Requirements: macOS 14+, Xcode/Swift 6 and Python 3. Build assets are downloaded
from pinned model/runtime revisions and verified against SHA-256 values in
`scripts/prepare-embedding.py`. Galpium code uses system SQLite and CryptoKit;
there are no third-party Swift package dependencies.

```sh
sh scripts/build-app.sh
open dist/Galpium.app
```

The app contains `Galpium`, `galpium-mcp`, `galpium-embedder`, EmbeddingGemma 2
Q8_0, its Q8_0 image/audio projector, llama.cpp and the complete license/notice
files. Runtime use needs no model download.

## Verification

Run tests appropriate to the change. For release preparation, the available
checks include:

```sh
sh scripts/check.sh
python3 scripts/test_semantic.py
python3 scripts/test-material-semantic.py
```

The protocol and model checks use disposable temporary libraries. Tests never
replace a user's library. `test-plugin-install.py` additionally requires an
installed ChatGPT desktop app. It verifies the packaged plugin's actual MCP
startup and 21-tool discovery through the desktop runtime, using unchanged
command/arguments and an explicitly configured disposable library. Discovery
metadata alone or manually expanded launcher paths do not count as a startup test.

## Package

```sh
sh scripts/package-release.sh
```

Outputs in `dist/`:

- `Galpium.app`
- `Galpium-<version>-<architecture>.dmg`
- `Galpium-Codex-Plugin-<version>.zip`
- `SHA256SUMS`

The first public version is **0.0.1**. Its public assets and tag remain immutable.
The current release is **0.0.2**, build **2**. Packaging reads the version from
`Resources/Info.plist` and produces new `0.0.2` asset names. The app and plugin
manifest versions must agree. Public download links point to the fixed
`v0.0.2` tag, with `Galpium-0.0.2-arm64.dmg`, `Galpium-Codex-Plugin-0.0.2.zip`
and `SHA256SUMS` uploaded as release assets. If the local checksum file is kept
under a versioned filename, upload it using the release asset name `SHA256SUMS`.

Version 0.0.2 adds EmbeddingGemma 2 text/image/audio retrieval, visual indexing of
all PDF pages, original page/time provenance in material results and automatic
rebuilding of the derived model index. It does not generate OCR text or
transcripts, and does not change originals, exact citations or revision history.

The published binary is arm64/Apple silicon.
Build Intel releases on an Intel host or cross-build and independently validate
before publishing. Do not label an arm64 file universal.

Checksums use plain asset basenames so downloaded files can be verified together:

```sh
shasum -a 256 -c SHA256SUMS
```

## Signing

Without `GALPIUM_SIGN_IDENTITY`, builds are ad-hoc signed. The initial public
release is not Apple-notarized; the release notes and README state this explicitly.

For a notarized build, supply the publisher's existing Developer ID identity and
notarytool keychain profile:

```sh
export GALPIUM_SIGN_IDENTITY='Developer ID Application: Publisher (TEAMID)'
sh scripts/package-release.sh
export GALPIUM_NOTARY_PROFILE='galpium-notary'
sh scripts/notarize.sh
```

Never commit signing credentials. A valid signature is not evidence of Apple
notarization; accepted submission, stapling and Gatekeeper assessment are required.

## Public release policy

1. Commit and validate the final source. Exclude libraries, developer captures,
   benchmark results and local paths from the public tree.
2. Create a version-specific tag such as `v0.0.2` pointing to that commit.
3. Enable GitHub immutable releases for the repository.
4. Create a draft release and upload the DMG, plugin ZIP and `SHA256SUMS`.
5. Verify uploaded names, sizes and SHA-256 digests, then publish the draft.
6. Confirm the release is immutable and update download links to its fixed tag.

Published assets and tags are never replaced. A correction receives a new version.
The tag locks the source revision; `SHA256SUMS` locks artifact bytes. The separate
Application, model and runtime license scopes are documented in [third-party notices](../THIRD-PARTY-NOTICES.md).
