<div align="center">
  <img src="BigExport/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="BigExport icon">
  <h1>BigExport for Apple Maps</h1>
  <p><strong>Import thousands of saved places from Google Maps, CSV, or KML into Apple Maps guides — in seconds.</strong></p>
</div>

---

BigExport is a native macOS app that turns bulk place data into real Apple Maps **guides** you can share with a single iCloud link. Drop in a Google Maps Takeout export, a spreadsheet, or a KML file and it writes the places straight into Apple Maps.

## Features

- **Any format** — Google Maps Takeout (GeoJSON), CSV spreadsheets, and KML files
- **Bulk imports** — up to 5,000 places per guide, auto-split into numbered guides when you have more
- **Multiple files at once** — drop a whole folder of lists; import them all with one click
- **Automatic geocoding** — place-only exports (`maps/place/…` links with no coordinates) are resolved via Apple's geocoder, no API key required
- **Real Apple Maps guides** — share a single iCloud link anyone can open in Maps
- **No account, no key, no cloud service** — everything runs locally on your Mac

## Install

### Homebrew (recommended)

```sh
brew install --cask dautovri/tap/bigexport
```

### Manual

Download the latest `BigExport-x.y.z.dmg` from [Releases](https://github.com/dautovri/gotoapplemaps-bigexport/releases), open it, and drag **BigExport** to Applications. The app is signed and notarized by Apple.

## How it works

1. **Drop a file** (GeoJSON / CSV / KML) onto the window, or press ⌘O.
2. BigExport parses the places and resolves any that only have a name (no coordinates) via Apple's geocoder.
3. Name your guide and click **Add to Maps**. Apple Maps is briefly quit so the places can be written, then reopened.
4. In Maps, open **Guides**, select your new guide, and tap **Share → Copy Link** to get one iCloud link for the whole set.

### Supported input formats

| Format | Source | Coordinates |
|--------|--------|-------------|
| GeoJSON | Google Maps Takeout | Embedded |
| CSV (Title + URL) | Google Maps saved lists | Parsed from the Google Maps URL, or geocoded by name |
| CSV (lat/lon columns) | Any spreadsheet | Embedded |
| KML / KMZ | Google Earth, other map tools | Embedded |

CSV delimiter (`,` `;` tab) and a leading preamble row are auto-detected.

## Requirements

- macOS 15.0 or later
- Apple Maps opened at least once (so its local database exists)

## Building from source

```sh
brew install xcodegen
xcodegen generate
open BigExport.xcodeproj
```

To produce a signed, notarized DMG locally:

```sh
./scripts/package.sh 1.0.0
```

## Privacy

BigExport processes your files entirely on-device. Place names sent for geocoding go to Apple's geocoding service (the same one Maps uses); nothing else leaves your Mac. No analytics, no accounts, no servers.

## Related

Part of the [GoToAppleMaps](https://gotoapplemaps.app) family — open Google Maps links in Apple Maps.

## License

[MIT](LICENSE) © Ruslan Dautov
