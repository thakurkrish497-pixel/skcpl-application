# SKCPL native releases

Targets: Android APK; Windows x64 ZIP containing SKCPL.exe; universal macOS ZIP containing SKCPL - Connect to Waves.app. The company website remains a download page. No web ERP or Play Store upload is part of this workflow.

## Local package verified on 15 November 2026

- Version 1.0.1, build 2; application ID `com.skumarcreation.skcpl` unchanged.
- Android APK compiled with Flutter 3.47.8 and the existing release signing identity. It can update installations using the same signing certificate. A Google Play installation may use a different Play App Signing certificate; do not uninstall or clear app data to work around an update conflict, because that can remove unsynced drafts.
- Android 7.0 / API 24 or newer; ARM64, ARMv7 and x86_64 libraries included.
- 168 Flutter tests pass; analyzer reports no issues. Six release-manifest safety tests also pass.
- Layout tests cover 320×740, 390×844, 844×390, 1024×768, 1440×1000 and 1920×1080.
- The APK is built from the current working files, including the uncommitted sync/approval fixes. Its manifest records the existing HEAD, a dirty-worktree flag and the shared Flutter source fingerprint. HEAD alone does not identify the uncommitted APK source.

## CI behavior

`.github/workflows/build_releases.yml` replaces the old `build_desktop.yml` publisher.

On a relevant push to `main`, the workflow analyzes/tests the app, then builds all three native targets from that commit. A manual run defaults to artifacts only; select `publish` on `main` to publish. It does not upload an AAB to Google Play.

- Android uses the existing signing key restored from encrypted Actions secrets. It fails rather than silently creating a different key.
- Windows runs on Windows Server 2022 x64 and packages the entire release folder, plugin DLLs, Flutter data and app-local Visual C++ runtime. Extract the whole ZIP; keep its files together. The EXE is not Authenticode-signed.
- macOS runs on a hosted Mac with Xcode and CocoaPods. Its deployment minimum is macOS 12. Both the executable and App.framework must contain arm64 and x86_64 slices. `ditto` preserves the APP bundle and symlinks.
- Publication requires all three builds and matching version, commit, shared-source fingerprint and artifact checksums. It creates a draft, attaches all packages, then marks it public/latest. It refuses to overwrite an existing version. Bump both version and build number in pubspec.yaml for each subsequent publication.
- Uploaded artifacts include `release-manifest.json` and `SHA256SUMS.txt`. Website buttons use GitHub's stable `releases/latest/download/` URLs.

The workflow was checked with actionlint v1.7.12, shell/Ruby syntax checks and embedded Python compilation. Windows and macOS builds have not run yet; they require pushing this workflow and the current source after explicit user approval.

## Android Actions secrets

Required in `thakurkrish497-pixel/skcpl-application`:

- `ANDROID_KEYSTORE_BASE64`: base64 of the existing Android release JKS.
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

All four secret names were configured and verified after the user explicitly approved the encrypted upload. The signing values were encrypted using the repository's GitHub Actions public key before transmission and were not printed or attached to artifacts. The original automatic-review rejection was resolved by the user's explicit approval. No Git push or release publication was performed as part of secret setup.

The existing Android JKS is already tracked by the repository. Ignore rules prevent new signing files from being added, but do not remove tracked files or old history. Keep the local key for compatible updates; remove it from Git tracking before the next push and review access to its historical copies. Never attach keystores/password files to release artifacts.

## Apple signing and notarization

Optional Actions secrets supported:

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY` (Developer ID Application certificate name)
- `APPLE_NOTARY_PRIVATE_KEY_BASE64` (App Store Connect API private key)
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER`

Without these, CI can build the APP/ZIP, but it is not Developer ID signed or notarized. Gatekeeper can block a downloaded copy. The release notes and manifest explicitly report this; the website directs users to company IT rather than instructing them to disable quarantine protections. A smooth trusted Mac download needs the Apple credentials configured.

With credentials configured, the script signs frameworks and the application, submits for notarization, staples the ticket and verifies it before publishing the archive. Credentials are temporary on the hosted runner and are cleaned up.

## Publication order

1. Test the supplied APK on an Android phone, including sign-in, queued drafts, syncing, attachments and approvals. Preserve existing application data.
2. Android signing secrets are configured. Configure Apple signing/notarization if required for the public Mac download.
3. Review and explicitly authorize the app repository push. Include all current fixes, fonts, tests and release scripts; a workflow built from older remote source would miss those fixes. Keep signing credentials out of the commit.
4. Inspect the successful Windows/macOS CI builds and the new complete release. Native device acceptance remains necessary; local widget tests are not a Windows/macOS runtime test.
5. Push only the reviewed `app-download.html` website change after the new release is available. Vercel auto-deploys the website. Existing unrelated website edits must remain untouched.
6. Verify the three website download buttons resolve to the new release and that downloaded files match the published checksums.

No Git push, public release, Vercel deployment or live database change was performed while preparing these files.
