# Releasing the direct-sale Mac app (Developer ID + notarization)

Customers who buy through Lemon Squeezy download a DMG. macOS only opens it without warnings if the app is signed with a
**Developer ID Application** certificate and **notarized** by Apple. `scripts/release.sh` does the whole build once the one-time setup below is done.
The script has not been run yet (no signing identity is installed on this Mac); everything up to the Apple steps was checked: the Release build
works with the hardened runtime on and starts, and the script passes a syntax check.

## One-time setup (needs you)

1. **Enroll** in the Apple Developer Program at developer.apple.com/programs (about $99 a year). An organisation account also needs a D-U-N-S number; an individual account does not. Approval can take a few hours to a couple of days.
2. **Create the certificate.** In Xcode: Settings → Accounts → select your team → Manage Certificates → **+** → **Developer ID Application**.
   Check it landed: `security find-identity -v -p codesigning` should list "Developer ID Application: Your Name (TEAMID)".
3. **Find your Team ID** (10 characters): developer.apple.com → Account → Membership details.
4. **Store notarization credentials.** At appleid.apple.com → Sign-In and Security, create an **app-specific password** (not your Apple ID password). Then:

   ```bash
   xcrun notarytool store-credentials "permylast-notary" --apple-id "you@example.com" --team-id "YOURTEAMID"
   ```

   It asks for the app-specific password at a hidden prompt and keeps it in your Keychain. Do not put it in a file or in chat.

## Every release

1. In `App/PerMyLast/AppConfig.swift` set `releaseDate` to today, and `isPatchBuild` if it is a compatibility fix. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Decide `paymentsLiveInRelease` (see `docs/ACCEPTANCE.md`, launch checklist).
3. Run:

   ```bash
   TEAM_ID=YOURTEAMID NOTARY_PROFILE=permylast-notary scripts/release.sh
   ```

   It runs the secret scan and tests, archives a universal (Apple silicon + Intel) Release build signed with the hardened runtime, verifies the signature,
   notarizes and staples the app, builds and signs the DMG, notarizes and staples that, and ends with the same Gatekeeper checks a customer's Mac makes.
   The result is `dist/PerMyLast-<version>.dmg`.
4. Test the DMG on a Mac that has never run a development build: open it, drag to Applications, launch. There must be no "unidentified developer" warning.
5. Upload the DMG. Lemon Squeezy can deliver the file with the product, or host it yourself and link it.

## What changes once the app is properly signed

- The Keychain stops asking for your login password after every rebuild. The key saved by earlier ad-hoc builds asks once more, then not again (as long as the signing identity stays the same).
- Sign in with Apple and the Mac App Store build also need capabilities and provisioning profiles tied to your team. They are a separate step from Developer ID.
- "Check for Updates…" is still a placeholder. Auto-update (for example Sparkle) is a good next addition before many people have the app.
