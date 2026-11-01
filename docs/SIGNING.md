# Official macOS signing and release

STL Medic 1.0.0 (build 4) is prepared in source. Do not publish the
`v1.0.0` tag or GitHub release until the packaged application has passed
Developer ID signing, Apple notarization, and distribution verification.
The existing `scripts/build.sh` produces an ad-hoc signed local build;
it does not produce an officially signed release.

## Account and certificate

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/enroll/).
2. In Xcode, open **Settings → Accounts**, add your Apple Account, and select
   your paid developer team.
3. Open **Manage Certificates**, click **+**, and create a **Developer ID
   Application** certificate. Apple's Account Holder requirements apply.
   This is the certificate for distributing the app outside the Mac App Store.
4. Verify that its certificate and private key are installed in your keychain:

   ```sh
   security find-identity -v -p codesigning
   ```

The output must include `Developer ID Application: … (TEAMID)`. An Apple
Development or Apple Distribution certificate cannot substitute for it.
Keep the private key and any exported `.p12` file out of Git.

## Build and sign

Run `./scripts/build.sh` and the geometry tests. The app contains a Swift
executable, a complete CPython runtime, Python extension modules, dynamic
libraries, and Qt frameworks. Official signing must cover all nested native
code as well as the outer application.

Sign native code from the inside out, then sign its containing frameworks,
bundles, and finally `dist/STL Medic.app`. Use the Developer ID Application
identity with a secure timestamp; enable hardened runtime for executable
targets. Do not replace the current ad-hoc signing command with a single
`codesign --deep` command and assume this signs every Python dependency.
Inspect the bundled native code and its signing requirements explicitly.

Determine any required runtime entitlements by testing the signed embedded
Python interpreter and mesh operations. Avoid enabling broad exceptions
unless a bundled component requires them. Test the final signed app's
analysis, repair, reconstruction, preview, export, and Bambu Studio handoff.

Verify the resulting signatures before notarization:

```sh
codesign --verify --deep --strict --verbose=2 'dist/STL Medic.app'
codesign --display --verbose=4 'dist/STL Medic.app'
```

## Notarize and staple

Configure notarization credentials locally with `xcrun notarytool
store-credentials STLMedic-notary`. Follow its interactive prompts for an
Apple Account, team ID, and app-specific password, or configure an App Store
Connect API key instead. Do not put passwords or private API keys in Git or
release notes.

Package the signed app for submission, then wait for Apple's result:

```sh
mkdir -p build/notarization
ditto -c -k --keepParent 'dist/STL Medic.app' build/notarization/STL-Medic-1.0.0.zip
xcrun notarytool submit build/notarization/STL-Medic-1.0.0.zip \
  --keychain-profile STLMedic-notary --wait
```

Proceed only if the result is **Accepted**. Inspect the submission log for
warnings or rejected nested binaries with `xcrun notarytool log SUBMISSION_ID
--keychain-profile STLMedic-notary`. Resolve issues and resubmit if needed.

Staple Apple's ticket to the app and validate it:

```sh
xcrun stapler staple 'dist/STL Medic.app'
xcrun stapler validate 'dist/STL Medic.app'
codesign --verify --deep --strict --verbose=2 'dist/STL Medic.app'
spctl --assess --type execute --verbose=4 'dist/STL Medic.app'
```

Create the final download ZIP **after** stapling. Do not modify the app bundle
or run the ad-hoc build script again after signing and stapling it. Test a
downloaded, quarantined copy on a Gatekeeper-enabled Mac before distribution.

## Publish 1.0.0

Include the signed, stapled Apple Silicon app, matching application and
dependency sources, license notices, and SHA-256 checksums. Confirm the app's
Info.plist reports version `1.0.0` and build `4`, and that the source archive
matches the release commit. Remove the pending-release notice in README.md,
then create `v1.0.0` at that commit and publish a stable GitHub release.

The existing `publish-download.yml` workflow only republishes the historical
0.2.1 preview. It must not be used for the 1.0.0 production release.

References: [Developer ID](https://developer.apple.com/developer-id/),
[Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
