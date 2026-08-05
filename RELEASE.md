# Release Process

Pushing a tag like `v1.2.3` triggers CI to build and publish to all stores.

## Quick start

```bash
git tag v1.0.1
git push origin v1.0.1
```

Version format: `v{major}.{minor}.{patch}`. The build number is auto-incremented by GitHub run number.

## One-time store setup

### 1. Google Play Console

1. Sign up at https://play.google.com/console ($25 fee)
2. Create app: package name `hu.jezsuita.ignaciima`
3. Fill store listing (name, description, screenshots, etc.)
4. Create a Service Account:
   - Settings → Developer account → API access
   - Google Play Android Developer API → Enable
   - Google Cloud → IAM → Service Accounts → Create
   - Name: `github-ci`
   - Role: Service Account User
   - Create key → JSON → download
   - Go back to Play Console → Users & permissions → Invite the service account email
   - Role: Admin (all permissions)
5. Add the JSON contents as GitHub secret: `PLAY_SERVICE_ACCOUNT_JSON`

### 2. Apple Developer Program + App Store Connect

1. Enroll at https://developer.apple.com/programs ($99/year)
2. Register your app in App Store Connect:
   - Apps → + → New App
   - Platform: iOS
   - Name: Ignáci imák
   - Bundle ID: `hu.jezsuita.ignaciima`
   - SKU: `ignaci_imak_1`
3. Create an App Store Connect API Key:
   - Users & Access (top of App Store Connect) → Keys → App Store Connect API
   - Generate key → name it `GitHub CI`
   - Download the `.p8` file
   - Note the **Key ID** and **Issuer ID** from the page
4. Add these GitHub secrets:
   - `APP_STORE_KEY_ID` — the key ID from step 3
   - `APP_STORE_ISSUER_ID` — the issuer ID from step 3
   - `APP_STORE_KEY_CONTENT` — the full contents of the `.p8` file

### 3. iOS signing certificate (one-time, needs a Mac)

1. On your Mac, open **Keychain Access** → Keychain Assistant → Certificate Assistant → Request a Certificate
   - User email: your Apple Developer email
   - Saved to disk

2. Go to https://developer.apple.com → Certificates → + → Apple Distribution
   - Upload the CSR → download the `.cer`

3. Double-click the `.cer` to install in Keychain Access

4. Export the private key:
   - Keychain Access → login → My Certificates → right-click the cert → Export
   - Format: `.p12`
   - Set a password

5. Export the provisioning profile:
   - https://developer.apple.com → Profiles → + → App Store
   - Bundle ID: `hu.jezsuita.ignaciima`
   - Download the `.mobileprovision`

6. Add these GitHub secrets:
   - `IOS_CERTIFICATE_BASE64` — base64 of the `.p12` file:
     ```bash
     base64 -i Certificate.p12 | pbcopy
     ```
   - `IOS_CERTIFICATE_PASSWORD` — the p12 password
   - `IOS_PROVISIONING_PROFILE_BASE64` — base64 of the `.mobileprovision`:
     ```bash
     base64 -i profile.mobileprovision | pcbopy
     ```

## GitHub Secrets summary

| Secret | Required for | Source |
|---|---|---|
| `KEYSTORE_BASE64` | Android signing | Already set |
| `KEYSTORE_PASSWORD` | Android signing | Already set |
| `KEY_PASSWORD` | Android signing | Already set |
| `KEY_ALIAS` | Android signing | Already set |
| `GHRC_TOKEN` | Docker push | Already set |
| `SERVER_URL` | .env | Already set |
| `SERVER_CHECK_VERSIONS_PATH` | .env | Already set |
| `SERVER_DOWNLOAD_DATA_PATH` | .env | Already set |
| `SERVER_MEDIA_PATH_PREFIX` | .env | Already set |
| **`PLAY_SERVICE_ACCOUNT_JSON`** | Play Store | Google Play Console → Service Account |
| **`APP_STORE_KEY_ID`** | App Store | App Store Connect → Keys |
| **`APP_STORE_ISSUER_ID`** | App Store | App Store Connect → Keys |
| **`APP_STORE_KEY_CONTENT`** | App Store | App Store Connect → Keys (.p8 file) |
| **`IOS_CERTIFICATE_BASE64`** | iOS signing | Keychain Export (.p12) |
| **`IOS_CERTIFICATE_PASSWORD`** | iOS signing | p12 password |
| **`IOS_PROVISIONING_PROFILE_BASE64`** | iOS signing | Apple Developer → Profiles |

## How it works

On a `v*` tag push, the CI pipeline:

1. **Android** — builds signed `.aab`, uploads to Google Play (production track, 10% staged rollout)
2. **iOS** — builds signed `.ipa` with distribution cert, uploads to App Store Connect (TestFlight, manual release)
3. **Web** — builds web app, pushes Docker image to GHCR
4. **Release** — creates a GitHub Release with `.aab` and `.ipa` as artifacts

If a store secret is missing (e.g. `PLAY_SERVICE_ACCOUNT_JSON` not set), that step is skipped — the build still succeeds and artifacts are uploaded to the GitHub Release.

## Renewing iOS certificates

Distribution certificates expire **every year**. When that happens:

1. Generate new cert + p12 on a Mac (step 3 above)
2. Update `IOS_CERTIFICATE_BASE64` and `IOS_CERTIFICATE_PASSWORD` secrets
3. Generate new provisioning profile
4. Update `IOS_PROVISIONING_PROFILE_BASE64` secret

No code changes needed — the pipeline picks up the new secrets.
