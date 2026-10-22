# NIVQO

**The Web. Your Way.**

A smarter, faster, more connected browsing experience within The Willard Group Ltd.

## iPhone v0.8.5 — Bottom Bar Refresh

The iPhone app now builds directly from the reviewable Swift source in `mobile/ios`.
The original source ZIP and `mobile/patches` remain historical inputs; the workflow
no longer extracts or reapplies them. The source was reconstructed from the ZIP
plus the active v0.8.2 and v0.8.4 patches. The superseded v0.8.3 URL-completion
patch is deliberately not applied. No prior v0.8.5 recovery patch was present on
`main` or the existing feature branch when this update was prepared.

- Full-width websites with a floating bottom address/search pill.
- Back, Address/Search, Flow, Spaces, Tabs and Menu; two rows on narrow phones.
- Scroll down for compact controls; scroll up or tap the compact domain to reveal.
  Flow and Spaces remain available in the compact strip.
- Keyboard safe-area layout, 44-point controls, VoiceOver labels and Reduce Motion.
- Blank tabs ignore WebKit process termination. Real pages receive at most one
  automatic recovery attempt per explicit navigation; further failures show a
  nonblocking Reload notice. Background and closed tabs never auto-reload.
- The existing per-Space search-phrase history remains; no URL autocomplete.

The bundle identifier remains `dev.nivqo.iphone`. Personal website storage,
Space data identifiers, preferences, bookmarks, history, saved accounts and
normal/private isolation retain their existing storage formats. WebKit uses its
ordinary JavaScript, cookies and user agent; this is not a challenge bypass.

## Official visual identity

The approved cyan-to-blue **N** on midnight blue is preserved byte-for-byte in
`branding/NIVQO-AppIcon.jpg.b64`, including the artwork correction committed in
`5ba473c`. That asset was installed after the earlier README warning about an
outdated logo. It supplies both the app icon and homepage image. Do not redesign
or replace the mark.

## Build and install

Open [Build NIVQO iPhone IPA](https://github.com/NivqoBrowser/nivqo/actions/workflows/build-iphone-ipa.yml).
Choose a successful v0.8.5 run and download **NIVQO-iPhone-for-Sideloadly** from
its **Artifacts** section. Extract the ZIP and open
`NIVQO-iPhone-v0.8.5-unsigned.ipa` in Sideloadly. Keep the same Apple signing
account and installed bundle identifier as the previous installation. Keep the
existing app installed to retain its local data.

The workflow tests Swift logic, builds simulator/device targets, and verifies the
packaged IPA. This is an unsigned iPhone build for Sideloadly, not an App Store
release. A successful build does not establish physical-device functionality.
See [iPhone build and verification notes](mobile/ios/README.md).
