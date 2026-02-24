# Build iOS Widget IPA with GitHub Actions (No Mac Required Locally)

This repository now includes:

- `.github/workflows/ios-widget-ipa.yml`
- `project.yml` (XcodeGen spec)
- `ios/App` (SwiftUI app)
- `ios/Widget` (Widget extension)
- `ios/Shared` (JSON model + pagination)

It builds an **unsigned iOS IPA** on GitHub's macOS runner and uploads it as an artifact.

## Widget behavior

- Fetches `poem.json` at runtime from `PoemRemoteURL` in target plist.
- Falls back to cached poem data when offline.
- Falls back to bundled `poem.json` if no network/cached data is available.
- Splits long poems into multiple pages for medium widget display.
- Each widget instance can be configured with a page number.
- Use Smart Stack with multiple instances (Page 1, Page 2, Page 3...) to swipe through pages.

## What you still need

1. AltStore/AltServer on your Windows PC for install/sign flow.
2. GitHub Actions enabled for this repo.
3. A reachable JSON URL in `PoemRemoteURL` (`ios/App/Info.plist` and `ios/Widget/Info.plist`).

## Rebuild frequency

- You do **not** need to rebuild the IPA for daily poem changes.
- Rebuild only when app/widget code changes.
- Keep updating the remote `poem.json` source URL used by `PoemRemoteURL`.

## First run

1. Push this repo to GitHub (including `project.yml` and `ios/*`).
2. Open **Actions** tab on GitHub.
3. Select **Build iOS Widget IPA**.
4. Click **Run workflow**.
5. (Optional) Fill:
   - `project_path`: path to a `.xcodeproj` (optional; usually leave empty)
   - `scheme`: shared scheme name
   - `generate_from_xcodegen`: keep `true` (default)
   - `configuration`: `Release` (default) or `Debug`
6. After it finishes, download artifact **ios-widget-ipa**.

## Install through AltStore

1. Extract/download the `.ipa` from Actions artifacts.
2. In AltStore on iPhone: **My Apps** → **+** → select the `.ipa`.
3. Keep AltServer available on your PC for refresh/re-sign.

## Preview on laptop (no iPhone install)

1. Open GitHub **Actions**.
2. Run **iOS Preview Screenshots**.
3. Download artifact `ios-preview-screenshots`.
4. Review:
   - `app-light.png`
   - `app-dark.png`
   - `home-screen.png`

This preview is generated on a GitHub macOS simulator and can be viewed from your Windows laptop.

## Configure page widgets in Smart Stack

1. Add **Poem Page** widget (medium size) to Home Screen.
2. Long-press widget → **Edit Widget** → set `Page Number`.
3. Add more widget instances with different page numbers.
4. Stack them into a Smart Stack and swipe to read page-by-page.

## Transparent blend setup (iOS 26)

1. Take a screenshot of your Home Screen wallpaper.
2. Open the app and use **Upload Wallpaper Screenshot**.
3. Adjust the **Dark Overlay** slider until the widget visually blends.
4. Edit/add widgets and keep page numbers per instance for Smart Stack flow.

The app stores wallpaper + overlay in App Group storage so the widget can use the same appearance.

## Common failures

- **No .xcodeproj found**: keep `generate_from_xcodegen=true` and ensure `project.yml` exists.
- **No shared schemes found**: in Xcode, mark your app scheme as shared and commit the scheme files.
- **Build succeeds but widget missing**: ensure the widget extension target is included in the same app scheme.
