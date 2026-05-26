# Release guide

## Local release artifact

```sh
npm test
npm run package:macos
```

Output:

- `dist/CodexUsageStatus.app`
- `dist/CodexUsageStatus-<version>-macos-<arch>.zip`
- `dist/SHA256SUMS.txt`

## Signing

By default, the local build is ad-hoc signed:

```sh
CODESIGN_IDENTITY=- npm run build:macos
```

For a public release, use a Developer ID certificate and notarization:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" npm run package:macos
```

Notarization is intentionally not automated in this repository because it requires Apple developer credentials.

## Architecture

The local package builds for the current Mac architecture. GitHub Actions can produce a macOS artifact on the runner architecture. If universal releases are needed, build separate `arm64` and `x86_64` artifacts or add a universal build step after confirming both targets compile in CI.

## User install flow

For a release ZIP:

1. Download and unzip the release artifact.
2. Move `CodexUsageStatus.app` to `/Applications`.
3. Open the app.
4. Optional: add it to macOS System Settings > General > Login Items.

For source:

```sh
npm run install:macos
```
