# Splitcast site

Static info pages for Splitcast, ready for GitHub Pages: plain HTML and CSS, no build step, no
Jekyll (`.nojekyll`), relative links only, light and dark mode.

| Page | Content |
|---|---|
| `index.html` | Landing page: what the app does, screens, privacy |
| `how-it-works.html` | The markers, the prediction maths, Riegel, accuracy, limits |
| `help.html` | Getting started and FAQ |
| `privacy.html` | Privacy policy (the public URL TestFlight and the App Store need) |

## Images

- `assets/icon.png`, `apple-touch-icon.png`, `favicon.png`: resized from the app icon
  (`Splitcast/Assets.xcassets/AppIcon.appiconset/AppIcon.png`).
- `assets/screens/*.svg`: app screens drawn with made-up sample data, so no real health data is
  published. Regenerate with `python3 tools/make_splitcast_screens.py site/assets/screens`.
  Real simulator screenshots can replace them later (same 390 × 800 shape works best).

## Preview

```bash
python3 -m http.server -d site 8000   # then open http://localhost:8000
```

## Publishing

GitHub Pages can only deploy from a branch's `/ (root)` or `/docs` folder, so publish this folder
with a GitHub Actions Pages workflow (Settings › Pages › Source: GitHub Actions), or rename it to
`docs` and deploy from branch `main`, folder `/docs`.

Before publishing, fill in the placeholders: `[contact email]` (help and privacy pages),
`[date of first release]` (privacy) and the TestFlight link (`href="#"` in `index.html`).
Keep `privacy.html` in step with `../PRIVACY.md`.
