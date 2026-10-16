# API Pilot launcher icon

The mark is a code bracket pair `</>` whose slash is a heading arrow: a request
in flight, steered by a pilot. Electric-blue brackets, a cyan arrow, and a deep
navy background.

![Icon](icon-1024.png)

## Files

| File | What it is |
| --- | --- |
| `icon.svg` | **Master icon**: background plus glyph. Used for the legacy icon (Android 7.x) and previews |
| `icon-foreground.svg` | Adaptive icon foreground: glyph only, transparent, kept inside the 66dp safe zone |
| `icon-monochrome.svg` | Themed icon layer (Android 13+): the same glyph in white, tinted by the system |
| `*-1024.png` | Exports of the SVGs above, used as input by `flutter_launcher_icons` |
| `preview-sizes.png` | Check sheet: legacy, circle and squircle masks at 192/96/48/32 px on dark and light wallpapers |

The adaptive background is a flat color, `#0F2A52`. It's set in
[flutter_launcher_icons.yaml](../../flutter_launcher_icons.yaml) and in `BACKGROUND` in
[tool/branding/render.mjs](../../tool/branding/render.mjs).

### Palette

| Role | Color |
| --- | --- |
| Background (adaptive) | `#0F2A52` |
| Background gradient (master) | `#14386B` → `#0A1C36` |
| Brackets | `#5B95FF` → `#2F6BFF` |
| Arrow | `#19C2E6` → `#5EF0FF` |

## Editing

The glyph is the `<g id="glyph">` group: two polylines (`bracket-left`, `bracket-right`) and a
`heading-arrow` group (a `shaft` line plus a `head` polygon). All shapes are plain strokes with round
caps, so you can edit them by hand or in Inkscape or Figma. **Keep the glyph geometry identical in all
three SVGs.** The master scales it by 1.15 because it has no safe-zone crop.

## Regenerating the icons

Requires Node 18+ and Flutter.

```bash
# 1. SVG -> PNG exports, safe-zone check, preview sheet
cd tool/branding
npm install        # first time only (installs @resvg/resvg-js)
npm run render     # fails if the foreground leaves the adaptive safe zone
cd ../..

# 2. PNG -> Android launcher resources
dart run flutter_launcher_icons
```

Step 2 rewrites these files in `android/app/src/main/res/`:

- `mipmap-*/ic_launcher.png`: legacy icon, 48–192 px
- `drawable-*/ic_launcher_foreground.png` and `ic_launcher_monochrome.png`: adaptive layers, 108–432 px
- `mipmap-anydpi-v26/ic_launcher.xml`: the adaptive icon definition
- `values/colors.xml`: `ic_launcher_background`

The manifest already points at `@mipmap/ic_launcher`, so nothing else needs to change. Commit the
generated resources: CI's `setup.sh` runs `flutter create`, which only adds missing files and keeps
these.

To check the result, look at `preview-sizes.png`, then install a build
(`flutter run` or `flutter build apk --release`) and look at the launcher. Try themed icons on
Android 13+ too.
