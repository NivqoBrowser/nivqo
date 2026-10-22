# NIVQO iPhone — v0.8.5 alpha (build 12)

The native SwiftUI / WKWebView app lives in this folder. `mobile/ios` is the build source used by GitHub Actions; the repository ZIP and older patch files are retained as historical inputs and are no longer applied during builds. The minimum deployment target is iOS 17.

## Bottom browser controls

Websites fill the available screen, with a floating bottom address/search pill and thin 3-point bars that retain the active Space colour. The controls are **Back | Address/Search | Flow | Spaces | Tabs | Menu**. Narrow iPhones use two rows to preserve readable address text and at least 44-point controls. Flow and Spaces remain directly accessible in the compact scrolling state.

Scroll down a long website to compact the controls; scroll up or tap the compact domain pill to reveal them. The home page, active address editor, website keyboard and VoiceOver keep controls expanded. Reduce Motion disables the chrome transition animation. The keyboard and bottom safe area are respected.

Tapping the address pill opens search. It shows up to six previously submitted search phrases and filters those phrases as you type. Website URLs and bookmarks are not autocomplete suggestions. **Edit current website address** remains available separately. Search history stays local, is scoped to its Space, and is neither displayed nor recorded in private tabs. Turning off Save browsing history also disables search history. Clear it through **Menu → History**.

## Web content recovery

A blank/home tab does not reload or display a process-termination alert. A selected, foreground HTTP(S) page receives at most one automatic recovery attempt until a new user navigation or explicit retry. Repeated termination, a failed automatic recovery, or an inactive tab produces a non-blocking retry message instead of repeated modal alerts. Closing or leaving the tab cancels its scheduled recovery. This reduces reload loops; it does not prevent WebKit from terminating under memory pressure.

Existing standards-compliant WebKit settings remain: JavaScript is enabled, the normal WebKit user agent is used, normal Spaces keep their persistent website data stores, and standard about/blob/data subframe navigation remains allowed. This is compatibility work, not a Cloudflare bypass. Sites that reject embedded browsers can be opened with **Menu → Open in default browser**.

## Build and download from GitHub

The [Build NIVQO iPhone IPA workflow](../../.github/workflows/build-iphone-ipa.yml) runs on macOS for relevant main-branch pushes, pull requests to main, and manual runs. It installs the approved icon from `branding/NIVQO-AppIcon.jpg.b64`, runs the Swift package tests, compiles for iPhone Simulator, builds a Release iPhone app without signing, then verifies the packaged IPA. The verifier checks `dev.nivqo.iphone`, version/build, iPhoneOS platform, arm64 executable, compiled app icon and absence of a signature/provisioning profile.

1. Open **NivqoBrowser/nivqo → Actions → Build NIVQO iPhone IPA**.
2. Select a successful run for the desired commit. To rebuild, select **Run workflow**, choose the branch and run it.
3. Under **Artifacts**, download **NIVQO-iPhone-for-Sideloadly** while signed in to GitHub. Artifacts are retained for 14 days.
4. Extract the downloaded ZIP. It contains `NIVQO-iPhone-v0.8.5-unsigned.ipa`, `SHA256SUMS.txt`, `BUILD-VERIFICATION.txt` and `READ-ME.txt`.
5. Open that `.ipa` in Sideloadly and sign/install it using your existing Apple account and installed bundle identifier. The app's source identifier remains `dev.nivqo.iphone`.

Do not delete the installed NIVQO app before updating if you want to preserve its local browsing data. Keep the same signing account and installed bundle identifier. Sideloadly must sign the IPA before installation; an unsigned artifact cannot run directly. A successful workflow establishes compilation, unit-test and packaging results, not physical-device behaviour.

## Build locally on a Mac

Open `NIVQO.xcodeproj` in Xcode. Choose your development team under **NIVQO → Signing & Capabilities**, keeping the existing app identifier stable. Select your connected iPhone and run. Handle device trust, provisioning and Developer Mode requests on your own devices when prompted.

For command-line checks, run from this folder:

```sh
swift test
xcodebuild -project NIVQO.xcodeproj -scheme NIVQO -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project NIVQO.xcodeproj -scheme NIVQO -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
```

GitHub Actions installs the approved icon and homepage branding before building. Local builders should use that same branding step when preparing a distributable. No third-party Swift package or cloud service is required.

## Verification on a real iPhone

The automated checks cover transfer protocol interoperability, import parsing, search-history filtering and the process-recovery policy. Simulator compilation does not exercise live keyboard layout, scrolling, website challenges or device memory pressure. Before treating this alpha as a device-tested release:

1. Check the home page on a narrow iPhone, with large text and VoiceOver. Open and close the keyboard; verify the address editor and every bottom control stay reachable above the keyboard and home indicator.
2. Browse a long article. Scroll down and up; verify compact/reveal behaviour, one-tap Flow and Spaces, and stable top/bottom Space accents. Test Back, Forward (in Menu), Tabs, new/private tabs, bookmarks and page sharing.
3. Submit search phrases, relaunch and filter previous searches. Confirm direct URLs are not added as searches and private tabs neither display nor save normal search phrases.
4. Switch normal Spaces and verify their cookies remain separate and survive relaunch. Confirm private cookies are isolated from normal tabs and are released after the last private tab in that Space closes.
5. Under Xcode, simulate termination of a page's WebContent process. Check one bounded recovery on the foreground page, a non-blocking retry after another termination, safe handling while backgrounded/switched/closed, and no reload or repeated alert on blank tabs.
6. Test a Cloudflare-protected website using normal WebKit behaviour; compare with Safari on the same network if the site rejects the embedded browser. A successful build is not evidence of challenge acceptance.
7. Check the approved cyan-to-blue N icon and update over an existing installation using the same signing identity. Verify existing bookmarks, Spaces, saved accounts and search history remain.

## Pair with the Windows desktop

1. Connect the devices to the same trusted private Wi-Fi network. Guest Wi-Fi/client isolation, VPNs, firewalls and network-adapter choice can affect reachability.
2. On desktop NIVQO, open **Flow + Drop → Create pairing QR**. The QR expires after two minutes.
3. Tap the iPhone's **Flow** control, then **Scan desktop QR**. Camera scanning is optional; pasting the pairing code also works. Review the detected LAN address and tap **Pair with computer**.
4. Allow local-network access when iOS requests it. Send a normal tab, text or a file up to 4 MiB in either direction. Incoming items require explicit acceptance. Private tabs cannot be sent.

Keep the iPhone app in the foreground. Backgrounding disconnects Flow and clears its pending transfer queue; pair again after returning. The desktop hosts the connection. Phone-to-phone hosting, background transfers, internet relay and cookie/session transfer are not included. Unit tests validate protocol fixtures, tampering/replay handling, pairing addresses and payloads; actual QR scanning, permissions and desktop-to-iPhone transfers still need device testing.

## Local data and current limits

Spaces retain separate persistent cookies, cache and website storage. Bookmarks, website history, search history and saved accounts are local and scoped to a Space. Private tabs share temporary storage only within the same Space until that Space's last private tab closes. Existing storage keys and Space data identifiers are retained by this update.

The app includes bookmark/password export import and saved-account access; it does not import browser sessions or passkeys and does not provide browser sync, full password autofill or desktop Chromium extensions. Shield does not implement the desktop tracker's filter lists. Ordinary HTTP webpages are allowed by WebKit and do not provide HTTPS transport protection. Flow encrypts its LAN payloads; neither the native app nor its protocol has received an independent security audit.

Camera input decodes pairing codes locally. Pairing accepts literal private LAN IPv4 addresses. Pairing secrets are temporary; incoming text is copied only on acceptance, with a local-only clipboard and two-minute expiry.
