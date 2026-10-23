# NIVQO

**The Web. Your Way.**

A smarter, faster, more connected browsing experience within The Willard Group Ltd.

## iPhone v0.9.0 — Mockup Match (build 13)

This is an actual SwiftUI interface implementation, not a static visual prototype.
The authoritative source is under `mobile/ios`; historical ZIPs and patch files
are not reapplied during GitHub Actions builds.

- NIVQO branded gradient home screen with approved N mark, search and quick sites.
- A dynamic, full-height WKWebView browser with Safari-inspired compact bottom
  toolbar (Back / Address / Flow / Spaces / Tabs / Menu); smaller devices adapt.
- Full-screen address/search mode, with private-aware local search history,
  per-Space filtering, Clear All and one-tap search reuse.
- Visual two-column tab overview, with WebKit snapshots where available,
  independent normal/private lists and tab close/open actions.
- Colour-coded Personal, Work, Gaming and Shopping Spaces, preserving historical
  cookie stores and bookmarks; existing users receive Gaming via migration.
- Functional Flow quick actions for tabs, URL links, files and connection status.
- Existing local history, private-mode isolation, bounded WebKit recovery and
  ordinary website verification compatibility remain in place.

Morrisons in the earlier concept image was only an example webpage; no Morrisons
page is embedded or required. All real websites render dynamically in WebKit.

Version **0.9.0** is an alpha. Passing Swift tests, Xcode compilation and IPA
validation does **not** guarantee the UI, website sign-ins, Flow pairing, or WebKit
recovery have passed hands-on testing on a physical iPhone.

## Official visual identity

The approved cyan-to-blue **N** on midnight blue is preserved byte-for-byte in
`branding/NIVQO-AppIcon.jpg.b64`, including the artwork correction committed in
`5ba473c`. That asset was installed after the earlier README warning about an
outdated logo. It supplies both the app icon and homepage image. Do not redesign
or replace the mark.

## Build and install

Open [Build NIVQO iPhone IPA](https://github.com/NivqoBrowser/nivqo/actions/workflows/build-iphone-ipa.yml).
Choose a successful v0.9.0 run and download **NIVQO-iPhone-for-Sideloadly** from
its **Artifacts** section. Extract the ZIP and open
`NIVQO-iPhone-v0.9.0-unsigned.ipa` in Sideloadly. Keep the same Apple signing
account and installed bundle identifier as the previous installation. Keep the
existing app installed to retain its local data.

The workflow tests Swift logic, builds simulator/device targets, and verifies the
packaged IPA. This is an unsigned iPhone build for Sideloadly, not an App Store
release. A successful build does not establish physical-device functionality.
See [iPhone build and verification notes](mobile/ios/README.md).
