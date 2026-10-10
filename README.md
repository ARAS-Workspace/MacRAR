<p align="center">
  <img src="https://raw.githubusercontent.com/ARAS-Workspace/MacRAR/press-kit/assets/macrar-app-icon.png" width="128" alt="MacRAR icon">
</p>

<p align="center">
  <a href="README.md">🇺🇸</a>&nbsp;&nbsp;<a href="README_TR.md">🇹🇷</a>
</p>

<h1 align="center">MacRAR</h1>

<p align="center">
  A WinRAR-style archive manager for macOS. Opens, extracts and creates archives with 7-Zip, built into the app.<br>
  Native AppKit UI · Finder right-click Quick Actions · encrypted archives · multi-volume archives · 30+ formats
</p>

---

An independent distribution by ARAS-Workspace, based on [MacRAR](https://github.com/mstcvk/MacRAR) by Mesut Çevik.

7-Zip is built into the app as a library through an FFI layer. Opening, extracting and creating archives needs no separate tool to download or install, and there is no need to build or sign the app yourself. Releases come signed with Developer ID and notarized by Apple. The update check follows this repository's releases.

The version number carries the original release it is based on and this distribution's patch round: `<original release>+ARAS.Patch.<n>`. The current version and what changed in each round are in [CHANGELOG](CHANGELOG).

## Requirements

- macOS 13 (Ventura) or later, Apple Silicon or Intel
- RARLAB's `rar` tool for creating RAR archives (see the tip below); opening and extracting RAR does not need it

## Installation

| Architecture                | File                          |
|-----------------------------|-------------------------------|
| Apple Silicon (M1/M2/M3/M4) | `MacRAR-<version>-arm64.dmg`  |
| Intel                       | `MacRAR-<version>-x86_64.dmg` |

1. Download the DMG for your architecture from the [Releases](https://github.com/ARAS-Workspace/MacRAR/releases/latest) page
2. Drag **MacRAR** to the **Applications** folder
3. Open it once; the Finder Quick Actions are installed on first launch and you are asked which archive types MacRAR should open

> [!TIP]
> Opening, extracting and testing RAR archives needs nothing else; the 7-Zip inside the app does it. Creating a RAR archive or changing one needs RARLAB's paid "RAR for macOS" tool (there is a 40-day trial). Its licence does not allow bundling it, so MacRAR neither includes the tool nor downloads it.
>
> Download "RAR for macOS ARM" for Apple Silicon or "RAR for macOS x64" for Intel from [rarlab.com](https://www.rarlab.com/download.htm), then point *Settings… → RAR tool → Install RAR Tool…* at the file you downloaded. A `rar` in `/usr/local/bin/rar` or `/opt/homebrew/bin/rar` is found on its own.

## Command-line modes

The Finder Quick Actions launch the app like this:

```bash
open -n -a /Applications/MacRAR.app --args --extract-here /path/archive.rar
```

| Flag                      | In Finder                 | Effect                                                                   |
|---------------------------|---------------------------|--------------------------------------------------------------------------|
| `--extract-here`          | MacRAR: Extract Here      | Extracts next to the archive                                             |
| `--extract-folder`        | MacRAR: Extract to Folder | Extracts into a folder named after the archive                           |
| `--extract-to`            | MacRAR • Extract To…      | Asks for a destination folder once, then extracts                        |
| `--test`                  | MacRAR • Test             | Tests the archive and reports the result                                 |
| `--compress`              | MacRAR • Quick Compress   | Creates an archive in the default format from Settings, without a dialog |
| `--compress-dialog`       | Compress with MacRAR…     | Opens the Create Archive dialog                                          |
| `--set-default`           | —                         | Makes MacRAR the default app for `.rar` files                            |
| `--install-quick-actions` | —                         | (Re)installs the Finder Quick Actions                                    |

Several files can follow the flag. When every part of a multi-volume archive (`.part1.rar`, `.7z.001` …) is passed, the set is still processed once, starting from the first volume.

## Third-party software

- **7-Zip** © Igor Pavlov. GNU LGPL 2.1 or later; the RAR decoder files under the unRAR licence restriction, some files under BSD 3-clause, BSD 2-clause or in the public domain. It is linked into the app as a static library built in the [ARAS-Workspace/7zip](https://github.com/ARAS-Workspace/7zip) fork, where the library's source and build scripts are published; the licence text ships inside the app bundle as `7zip-license.txt`. Details are in [Libraries/SevenZipKit/NOTICE](Libraries/SevenZipKit/NOTICE). See [7-zip.org](https://www.7-zip.org).
- **RAR / UNRAR** © Alexander Roshal, RARLAB. MacRAR does not include RARLAB's tools: RAR archives are read with 7-Zip's unRAR code, and creating RAR runs the `rar` the user installed. See [rarlab.com](https://www.rarlab.com).

Neither project is affiliated with MacRAR. "WinRAR" and "RAR" are trademarks of their owner.

## Author

**Mesut Çevik** · [github.com/mstcvk](https://github.com/mstcvk)

Independent distribution: [ARAS-Workspace](https://github.com/ARAS-Workspace)

## License

The MacRAR source code is released under the [MIT License](LICENSE).
