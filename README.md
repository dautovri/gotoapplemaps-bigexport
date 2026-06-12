<div align="center">
  <img src="BigExport/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="BigExport icon">
  <h1>BigExport for Apple Maps</h1>
  <p><strong>Import thousands of saved places from Google Maps, CSV, or KML into Apple Maps guides — in seconds.</strong></p>
</div>

---

BigExport is a native macOS app that turns bulk place data into real Apple Maps **guides** you can share with a single iCloud link. Drop in a Google Maps Takeout export, a spreadsheet, or a KML file and it writes the places straight into Apple Maps.

## Features

- **Any format** — Google Takeout (GeoJSON, CSV, Timeline), KML, KMZ, GPX, WKT
- **Bulk imports** — up to 5,000 places per guide, auto-split into numbered guides when you have more
- **Multiple files at once** — drop a whole folder of lists; import them all with one click
- **Exact coordinates without geocoding** — locations are recovered straight from Google Maps URLs (`!3d!4d`, `@lat,lng`, `?q=lat,lng`, and the S2 cell ID hidden in `data=`/`ftid=` links), entirely offline
- **Smart fallback geocoding** — anything left resolves via Apple's POI search (`MKLocalSearch`), no API key required; shortened `maps.app.goo.gl` links are expanded automatically
- **Real Apple Maps guides** — share a single iCloud link anyone can open in Maps
- **No account, no key, no cloud service** — everything runs locally on your Mac

## Install

### Homebrew (recommended)

```sh
brew install --cask dautovri/tap/bigexport
```

### Manual

Download the latest `BigExport-x.y.z.dmg` from [Releases](https://github.com/dautovri/gotoapplemaps-bigexport/releases), open it, and drag **BigExport** to Applications. The app is signed with a Developer ID certificate. (Release candidates are not yet notarized — if Gatekeeper blocks the first launch, right-click the app → Open.)

## How it works

1. **Drop a file** (GeoJSON / CSV / KML / KMZ / GPX / Timeline JSON / WKT) onto the window, or press ⌘O.
2. BigExport recovers coordinates from the file or its Google Maps URLs; anything left is resolved via Apple's POI search.
3. Name your guide and click **Add to Maps**. Apple Maps is briefly quit so the places can be written, then reopened.
4. In Maps, open **Guides**, select your new guide, and tap **Share → Copy Link** to get one iCloud link for the whole set.

### Supported input formats

| Format | Source | Coordinates |
|--------|--------|-------------|
| GeoJSON | Google Maps Takeout saved places | Embedded; `[0,0]` placeholders recovered from the Google URL (S2 / `?q=`) |
| CSV (Title + URL) | Google Maps saved lists | From the URL (`!3d!4d`, `@`, `/search/`, `?q=`, S2 cell ID), else geocoded |
| CSV (lat/lon columns) | Any spreadsheet | Embedded |
| Timeline JSON | Google Location History (all 3 export shapes) | Embedded, deduped by coordinate |
| KML / KMZ | Google My Maps, Google Earth | Embedded |
| GPX | GPS devices, fitness apps | Embedded waypoints |
| WKT | GIS tools | Embedded `POINT`s |

CSV delimiter (`,` `;` tab), preamble rows before the header, localized headers (e.g. Polish `Tytuł`), and unquoted commas inside URLs are all auto-handled.

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

Part of the [GoToAppleMaps](https://gotoapplemaps.com) family — open Google Maps links in Apple Maps.

## License

[MIT](LICENSE) © Ruslan Dautov
