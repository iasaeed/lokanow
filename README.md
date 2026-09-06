# Lokanow

A native macOS app for localizing Swift projects with Lokalise.

- Find untranslated UI strings across modules.
- Review editable keys and per-module Swift replacements.
- Update `.xcstrings` and `Localizable.strings`.
- Import existing translations by English value, cache them locally, and export missing translations.
- Preview changes and undo local edits. API tokens stay in Keychain.

## Install

Requires macOS 14+ and Xcode 26+ already installed. Builds locally into `~/Applications/Lokanow.app`, without sudo.

```sh
curl -fL https://raw.githubusercontent.com/iasaeed/lokanow/v1.0.5/scripts/install-source.sh -o lokanow-install.sh && sh lokanow-install.sh
```

Or use wget:

```sh
wget https://raw.githubusercontent.com/iasaeed/lokanow/v1.0.5/scripts/install-source.sh -O lokanow-install.sh && sh lokanow-install.sh
```

The first build can take several minutes; live output is shown. This is a locally built app. A notarized prebuilt download is not yet available. Company device policies may apply.

## Use

Open a project, select modules, analyze, review and apply changes. Connect Lokalise in Settings, then preview and import translations. Lokanow never uploads source code or writes to Lokalise.

[Build and release](docs/RELEASE.md) · [Supported cases](docs/SUPPORT.md)
