// No Apple Developer ID is configured for this build (see package.json's
// `mac` config — no `identity`), so electron-builder skips its own signing
// step and leaves the app carrying only Electron's original upstream
// "linker-signed" ad-hoc stub. That stub doesn't cover the resources
// electron-builder copies in afterward (app.asar, icons, etc.), so macOS
// sees a signature that no longer matches the bundle's contents — reported
// as "code has no resources but signature indicates they must be present"
// by codesign/spctl, and as "The app is damaged" by Gatekeeper once the
// download's quarantine flag triggers a verification (exactly what a tester
// hits after downloading the DMG from Chrome/Safari/etc.).
//
// Re-signing the whole bundle ad-hoc (`--sign -`) after packaging reseals it
// against its actual current contents, which is enough for the app to launch
// normally on any Mac (including Apple Silicon, which refuses to run
// completely unsigned code). It does NOT remove the separate "Apple could
// not verify this app is free of malware" Gatekeeper prompt an unnotarized
// app still gets on first launch — that one only goes away with a paid
// Apple Developer ID + notarization. Testers can get past that prompt with
// right-click → Open (or System Settings → Privacy & Security → Open Anyway)
// the first time.
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

module.exports = async function afterSign(context) {
  if (context.electronPlatformName !== 'darwin') return;
  const appName = context.packager.appInfo.productFilename;
  const appPath = path.join(context.appOutDir, `${appName}.app`);

  // This project lives under an iCloud Drive-synced folder, which keeps
  // re-tagging files with Finder/FileProvider extended attributes
  // (com.apple.FinderInfo, com.apple.fileprovider.fpfs#P, ...) as part of
  // syncing them — even a plain `xattr -cr` right before signing isn't
  // enough, since touching the files again (which codesign itself does)
  // triggers iCloud to re-tag them mid-signing. codesign refuses to sign
  // anything carrying those attributes ("resource fork, Finder information,
  // or similar detritus not allowed"), including nested helper apps inside
  // Contents/Frameworks. The reliable fix is to sign a copy staged outside
  // iCloud Drive (nothing there re-tags it), then copy the signed result
  // back over the packaged app before electron-builder builds the DMG from
  // it. `ditto` (not `cp -R`) preserves the app bundle's structure exactly,
  // including the embedded code signature once it exists.
  const stagingDir = fs.mkdtempSync(path.join(os.tmpdir(), 'permylast-sign-'));
  const stagedAppPath = path.join(stagingDir, `${appName}.app`);
  try {
    console.log(`[afterSign] Staging ${appPath} outside iCloud Drive at ${stagedAppPath}`);
    execFileSync('ditto', [appPath, stagedAppPath], { stdio: 'inherit' });

    console.log(`[afterSign] Stripping extended attributes from the staged copy`);
    execFileSync('xattr', ['-cr', stagedAppPath], { stdio: 'inherit' });

    console.log(`[afterSign] Ad-hoc re-signing the staged copy to reseal resources (no Developer ID configured)`);
    execFileSync('codesign', ['--deep', '--force', '--sign', '-', stagedAppPath], { stdio: 'inherit' });

    console.log(`[afterSign] Copying the signed app back to ${appPath}`);
    fs.rmSync(appPath, { recursive: true, force: true });
    execFileSync('ditto', [stagedAppPath, appPath], { stdio: 'inherit' });
  } finally {
    fs.rmSync(stagingDir, { recursive: true, force: true });
  }
};
