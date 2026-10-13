# Build and release

This guide covers compiling the source, creating a macOS distribution and
publishing release assets. Feature changes are listed in the [changelog](CHANGELOG.md).

## Compile the source

Use macOS 14 or later and Xcode with Swift 6. The package links to system SQLite
and Apple frameworks; it has no third-party Swift package dependencies.

```sh
swift build
```

This compiles the package's app, MCP server and embedding worker. A distributable
app also needs its resources and offline model assets.

## Create the app bundle

From the repository root:

```sh
sh scripts/build-app.sh
open dist/Galpium.app
```

The build prepares pinned model and runtime assets, checks their SHA-256 values
and assembles `dist/Galpium.app`. Downloaded assets are cached under
`.build/vendor/`. The bundle contains the app, MCP server, embedding worker,
EmbeddingGemma 2 model and projector, llama.cpp, localizations and license files.
The installed app does not download a model at runtime.

## Development checks

Use the check that covers the changed behavior. The existing entry points are:

| Area | Command |
| --- | --- |
| Swift tests | `swift test --filter <TestName>` |
| Core, MCP, formatting and package checks | `sh scripts/check.sh` |
| Text retrieval with the bundled model | `python3 scripts/test_semantic.py` |
| Material retrieval with the bundled model | `python3 scripts/test-material-semantic.py` |

Protocol and model checks use temporary libraries. The desktop plugin check in
`scripts/test-plugin-install.py` additionally exercises the installer and launch
path with an installed ChatGPT desktop app.

## Package a distribution

```sh
sh scripts/package-release.sh
```

The output directory contains:

- `Galpium.app`
- `Galpium-<version>-<architecture>.dmg`
- `Galpium-Codex-Plugin-<version>.zip`
- `SHA256SUMS`

The version comes from `Resources/Info.plist`; keep the plugin manifest version
in agreement. The packaging scripts use the host architecture. The public binary
is for Apple silicon. An Intel or other platform build needs its own compatible
runtime and validation; an arm64 build is not a universal binary.

Downloaded files can be checked together by placing the checksum file beside them:

```sh
shasum -a 256 -c SHA256SUMS
```

## Optional signing and notarization

The default build uses an ad-hoc signature. For a Developer ID distribution,
configure an existing signing identity and notarytool keychain profile:

```sh
export GALPIUM_SIGN_IDENTITY='Developer ID Application: Publisher (TEAMID)'
export GALPIUM_NOTARY_PROFILE='galpium-notary'
sh scripts/notarize.sh
```

The script packages, submits, staples and assesses the distribution, then refreshes
the checksums. Keep signing credentials outside the repository. Record the actual
distribution status in the release notes.

## Publish a release

Commit the release source and tag it with its version. Create a GitHub release
draft and upload the DMG, plugin ZIP and checksum file. Check the uploaded asset
names and hashes before publishing, then update the README download links.

Public tags and release assets are immutable. Corrections use a new version;
existing downloads are not replaced. Keep library data, model files, build output
and experiment artifacts out of the source tree. Redistribution must retain the
[third-party notices](../THIRD-PARTY-NOTICES.md) and bundled license files.
