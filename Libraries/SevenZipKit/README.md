# SevenZipKit

Pre-built universal static library for [7-Zip](https://github.com/ARAS-Workspace/7zip) (macOS arm64 + x86_64), with the C interface in `include/7zip_apple.h`.

**Source**: Built from the `apple` branch via the [Release macOS workflow](https://github.com/ARAS-Workspace/7zip/actions/runs/39084717672), published as [mac-v26.04+MacRAR.Patch.5](https://github.com/ARAS-Workspace/7zip/releases/tag/mac-v26.04%2BMacRAR.Patch.5). The same details are recorded in `SOURCE`; the licence and the attribution it carries are in `LICENSE` and `NOTICE`, and the full GNU LGPL 2.1 that `LICENSE` refers to is in `copying.txt`.

### Verify checksum

```bash
shasum -a 256 Libraries/SevenZipKit/lib7zip_apple.a
cat Libraries/SevenZipKit/CHECKSUM.sha256
```

Or in one step:

```bash
(cd Libraries/SevenZipKit && shasum -a 256 -c CHECKSUM.sha256)
```

Expected output:

```
lib7zip_apple.a: OK
LICENSE: OK
copying.txt: OK
```

The paths inside `CHECKSUM.sha256` are relative to this directory, so `shasum -c` has to run from here; the subshell keeps your own working directory where it was.
