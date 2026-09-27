# SpaceLens

**Press Space. See more.**

English · [简体中文](README.md)

[![macOS release check](https://github.com/linzh0632/SpaceLens/actions/workflows/macos.yml/badge.svg?branch=main)](https://github.com/linzh0632/SpaceLens/actions/workflows/macos.yml)

SpaceLens is an open-source Quick Look extension for macOS. It adds previews for folders, archives, source code, structured data, and common developer files while keeping the familiar Finder workflow: select an item and press Space.

All parsing and rendering happens locally. SpaceLens is preview-only: it does not edit files or become their default application.

## Why I Built SpaceLens

SpaceLens is my first open-source project. It began with a simple moment: before sending a compressed copy of my paper to my advisor, I wanted to verify that every file was there. macOS Quick Look could show basic information about the archive, but it could not reveal what was inside. After searching for a solution, I found that most apps offering this capability were paid, so I decided to build one myself with the help of AI. That experiment became SpaceLens.

What started as an archive previewer can now browse folders, source code, documents, structured data, and many common development formats. It keeps the familiar macOS workflow: select an item in Finder and press Space. Files stay on your Mac, and SpaceLens does not replace their default applications.

I hope SpaceLens is useful to others who have the same need. Issues and pull requests are welcome.

## Highlights

- Browse folders and archives as expandable trees with names, kinds, sizes, and modification dates.
- Select an item in a folder or archive and inspect supported content in a detail pane.
- Preview Markdown, source code, configuration, JSON, property lists, SQLite, notebooks, diagrams, and columnar data.
- Keep native Quick Look for images, PDF, audio, video, and other formats already handled by macOS.
- No account, telemetry, uploads, or execution of previewed content. Update checks are optional and off by default.

## Supported content

| Category | Examples |
|---|---|
| Folders and archives | Folders, ZIP, TAR, GZ, TGZ, BZ2, TBZ2, XZ, TXZ |
| Text and code | Markdown, common source and configuration files, logs, diffs, SQL, GraphQL, UTF-8/UTF-16 text |
| Structured data | JSON, JSON Lines, TSV, XML/Binary/OpenStep property lists, SQLite |
| Technical documents | Jupyter Notebook, MDX, Quarto, R Markdown, reStructuredText, AsciiDoc, TeX |
| Diagrams | Mermaid, PlantUML, Draw.io |
| Data engineering | Parquet, Arrow IPC, Feather v2, Avro OCF |
| Spreadsheets in folders | `.xlsx` and `.xlsm`, including worksheet switching |

See the [format matrix](docs/FEATURE-MATRIX.md) for detailed limits and container-preview support.

## Requirements

- **Running a built app:** macOS 12 or later.
- **Building the current source:** macOS 15.6 or later with Xcode 26 or later. The app icon uses the Icon Composer format introduced with Xcode 26.

The project builds a universal arm64/x86_64 app. It has been tested on Apple Silicon with macOS 27; Intel Macs and macOS 12–26 have not yet received hardware testing. Because only source installation is currently available, the build machine must meet the Xcode requirement above.

## Install from source

SpaceLens does not yet provide a Developer ID-signed and notarized binary release.

```sh
git clone https://github.com/linzh0632/SpaceLens.git
cd SpaceLens
./scripts/build.sh
./scripts/install.sh
```

The app is installed to `/Applications/SpaceLens.app`. After the first launch, enable SpaceLens under System Settings → General → Login Items & Extensions → Quick Look if Finder still shows the native information panel.

The detailed [installation guide](docs/INSTALL.md) is currently maintained in Chinese and covers updates, removal, and troubleshooting.

## Use

1. Open SpaceLens to activate its preview extension for the current session.
2. Select a supported item in Finder and press Space.
3. Select a file inside a folder or archive to open the detail pane; use Close to collapse it.

SpaceLens provides previews only while the app is running. A normal quit disables the extension and returns Quick Look to native macOS behavior. Enable Launch at Login in General settings on macOS 13 or later if you want previews available after every sign-in.

## Important boundaries

- SpaceLens declares no document-opening role, so double-clicking a file still uses its existing default app.
- macOS chooses between installed Quick Look providers. CSV, plain text, or another system-supported type may therefore keep using the native preview.
- `.xlsx` and `.xlsm` are supported only in the detail pane for a real folder. Direct Quick Look stays with macOS or Excel, and spreadsheets inside archives are not supported yet.
- Formula cells show cached values stored in the workbook. SpaceLens does not calculate formulas or read and execute macros.

## Privacy and security

SpaceLens does not upload file contents, names, directory structures, or preview results. It does not load remote document resources or execute source code, scripts, notebook cells, or document macros. Its only network feature is an optional update check against GitHub Releases, which is disabled by default.

See the [privacy statement](docs/PRIVACY.md), [security policy](SECURITY.md), and [file association notes](docs/FILE-ASSOCIATIONS.md).

## Contributing

Issues and pull requests are welcome. Do not upload private sample files to public issues; use a minimal synthetic fixture whenever possible. Read [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## License

SpaceLens is available under the [MIT License](LICENSE).
