# Aurora releases

Each publish run produces:

- `Aurora-<version>.dmg` — the installer (gitignored).
- `appcast.xml` — the Sparkle feed (tracked in git so you can see the history).

`scripts/publish.sh` uploads both as assets of a GitHub Release on the
**`aurora-releases`** repository, and the Production app's Sparkle picks up the
new version from
`https://github.com/<you>/aurora-releases/releases/latest/download/appcast.xml`.

## One-time setup

These steps are needed once per machine before the publish pipeline works
end-to-end:

1. **Add Sparkle to the Xcode project**
   `File > Add Package Dependencies > https://github.com/sparkle-project/Sparkle`
   (Up to Next Major Version → 2.0.0). Add the `Sparkle` product to the
   `commanderonev2` target. Build once (⌘B) so the SwiftPM tools download to
   DerivedData.

2. **Install the GitHub CLI and sign in**
   ```sh
   brew install gh
   gh auth login
   ```

3. **Create the public releases repo** (one of these is enough)
   ```sh
   # via gh:
   gh repo create aurora-releases --public --description "Aurora updates"
   # or create it manually at https://github.com/new
   ```
   It MUST be public so Sparkle can fetch the appcast.xml without auth.

4. **Generate the Sparkle signing keys**
   ```sh
   scripts/setup-sparkle-keys.sh
   ```
   Stores the private key in the macOS Keychain and prints (+ copies to
   clipboard) the public key.

5. **Wire the keys + URL into `commanderonev2/Info.plist`**
   - Replace `YOUR_GITHUB_USER` in `SUFeedURL` with your GitHub login.
   - Paste the public key from step 4 as the value of `SUPublicEDKey`.

   Build the Production scheme once after this so the new Info.plist values
   are baked into `Aurora.app`.

## Publishing a new version

```sh
scripts/publish.sh                  # 1.0.1 → 1.0.2  (default)
scripts/publish.sh --minor          # 1.0.4 → 1.1.0
scripts/publish.sh --major          # 1.4.2 → 2.0.0
scripts/publish.sh --local-only     # skip GitHub upload, useful for testing
```

The script bumps `MARKETING_VERSION`, archives the Release configuration,
adhoc-signs the `.app`, builds the DMG, signs it with the Sparkle EdDSA key,
prepends a new `<item>` to `appcast.xml`, and uploads both assets to a new
GitHub Release (`v<version>`). Re-running for an existing version replaces
the assets (`--clobber`).

The Production Aurora user then sees `Aurora N.N.N available — Update Now`
on next launch (or when they pick `Aurora ▸ Check for Updates…`).

## Environment overrides

| Variable          | Default                       | Purpose                                                         |
|-------------------|-------------------------------|-----------------------------------------------------------------|
| `GITHUB_OWNER`    | `gh api user --jq .login`     | Owner of the releases repo.                                     |
| `GITHUB_REPO`     | `aurora-releases`             | Releases repo name.                                             |
| `RELEASE_BASE_URL`| derived from owner/repo/tag   | URL prefix written into `<enclosure url="…">`. Override rarely. |
| `APPCAST_TITLE`   | `Aurora`                      | `<title>` element in the appcast.                               |
| `PROJECT_NAME`    | `Aurora`                      | Must match `PRODUCT_NAME` in the Release config.                |
