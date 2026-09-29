# `.ortupack` v1

An `.ortupack` is a single ZIP file used to distribute an Örtü motif. After validation, Örtü expands it into its private Application Support directory. It is a data-only plugin: it cannot contain or execute code.

## Create a pack

Start with a high-resolution PNG whose background is transparent and whose lace is one connected component. Prepare the normalized assets and manifest:

```sh
./scripts/ortu-pack prepare artwork.png MyLace.ortupack-src \
  dev.example.mylace "Benim Dantelim" "My Lace" 0.46
```

Review `manifest.json`, the generated images, authorship, and license. Then build the distributable file:

```sh
./scripts/ortu-pack build MyLace.ortupack-src MyLace.ortupack
./scripts/ortu-pack validate MyLace.ortupack
```

`build` first validates the source directory, writes a deterministic metadata-free ZIP, and validates the resulting file again. It refuses to overwrite an existing output.

## Install a pack

- In Örtü settings, choose **Paket Ekle…**.
- Drop the `.ortupack` file onto the **Örtü Paketleri** box.
- Or double-click the file in Finder after macOS has associated the type with Örtü.

Installation is atomic: Örtü inspects the archive before expansion, validates it in a private staging directory, and moves it into place only after every check succeeds.

## Root files

The ZIP has no enclosing folder and may contain only these root-level data files:

- `manifest.json` — required, UTF-8 JSON, at most 64 KiB
- `LICENSE.txt` — optional license text
- `texture@1x.png` — required
- `texture@2x.png` — required
- `mask.png` — required
- `preview.png` — optional

Asset names may differ when declared in the manifest, but only `.png`, `.heic`, and `.heif` image files are allowed. Nested paths, hidden files, symbolic links, scripts, executables, encrypted ZIPs, ZIP64, duplicate names, and unknown entries are rejected.

## Manifest v1

```json
{
  "schemaVersion": 1,
  "id": "dev.example.mylace",
  "version": "1.0.0",
  "name": { "tr": "Benim Dantelim", "en": "My Lace" },
  "author": "Your Name",
  "license": "CC0-1.0",
  "canvas": { "width": 2400, "height": 720 },
  "anchor": "topCenter",
  "defaultDrop": 0.46,
  "defaultWidth": 0.98,
  "tintMode": "multiply",
  "assets": {
    "texture1x": "texture@1x.png",
    "texture2x": "texture@2x.png",
    "mask": "mask.png",
    "preview": "preview.png"
  },
  "sha256": {
    "texture@1x.png": "...",
    "texture@2x.png": "...",
    "mask.png": "...",
    "preview.png": "..."
  }
}
```

Rules:

- `id` is stable across releases; use reverse-DNS form.
- `version` is semantic versioning.
- Allowed licenses in v1: `CC0-1.0`, `CC-BY-4.0`, `MIT`.
- `defaultDrop` is `0.20...0.85`; `defaultWidth` is `0.20...1.0`.
- `anchor` is `topCenter` in v1.
- `tintMode` is `multiply` or `original`.
- Images are at most 8192 px on either axis; the archive is at most 25 MB and expanded content at most 80 MB.
- SHA-256 entries are verified when supplied. The official creator supplies them.

## Update policy

The package manager exposes explicit **Update**, **Show in Finder**, and **Remove** actions for user-installed packs. An update must keep the same `id` and increase the semantic `version`; same-version replacements and downgrades are rejected. The incoming package is fully validated before it atomically replaces the installed version. Built-in packs cannot be updated or removed by external files.
