# DazzlingWins — Android app

The official player app for [dazzlingwins.com](https://dazzlingwins.com), built with Flutter.
Same account, same wallet and the same rules as the website: the app only talks to the website's
API over HTTPS, and every rule (spins, mandatory KYC, caps, XP, deposits, withdrawals) is enforced
on the server. Staff (admin/agent) desks are not part of the app.

## What's inside

| Area | What it does | Website API |
|---|---|---|
| Splash | Casino-style animated splash, then the app | — |
| Sign in / sign up | Email + password, referral code, Turnstile check when the site requires it | `/api/auth/login`, `/api/auth/register`, `/app-captcha` |
| Home | Balances, quick actions, XP progress, rewards to claim, top games | `/api/wallet`, `/api/profile`, `/api/xp-levels` |
| Games | The site's brand games: create account, logins, add score, redeem, transfer, play | `/api/app/games`, `/api/game-accounts/*` |
| Spin & Win | Server-drawn wheel ($1–$5), KYC required, $1 extra spin | `/api/wallet` |
| Wallet | Deposit (proof upload, promo code), withdraw (QR), all five histories | `/api/payment-methods`, `/api/deposits`, `/api/withdraws`, `/api/wallet/history` |
| Profile | KYC (optional SSN), deposit/KYC XP rewards, level perks, referral, support chat | `/api/kyc`, `/api/deposits/xp-rewards`, `/api/kyc/xp-reward`, `/api/chat/messages` |
| Notifications | Promo campaigns from Admin → Campaigns appear as Android notifications | `/api/app/notifications` |
| Updates | In-app update prompt for every new release | `/api/app/version` |

## Security

* Login tokens live only in Android Keystore–backed secure storage; never logged.
* Access token refreshes automatically (`/api/auth/token/refresh`); a refused refresh signs out.
* HTTPS only (cleartext traffic disabled), app backups disabled, release builds obfuscated.
* The in-app updater only downloads APKs from this repository's official GitHub Releases.
* All money, spin and KYC logic runs on the server — nothing in the app can change a balance.

## How releases work (no Android Studio needed)

Every push to `main` runs `.github/workflows/android.yml` on GitHub:

1. generates the Android project with the pinned Flutter version and configures it
   (`scripts/prepare_android.py`: app id `com.dazzlingwins.app`, permissions, signing, icon),
2. creates the app icons from the website's brand icon,
3. analyzes, tests and builds a signed, obfuscated release APK,
4. publishes it as the latest GitHub Release `v1.0.<run number>` with `DazzlingWins.apk`.

The website's footer button (`/download/android`) always serves the newest release, and installed
apps see an update prompt on their next launch.

### Release signing (one-time setup)

Add these **repository secrets** (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of the release keystore (`.p12`) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password (same as the keystore password for `.p12`) |

Without them the workflow still builds a test APK (as a workflow artifact) but does not publish it.
**Keep a safe backup of the keystore** — every update must be signed with the same key or Android
refuses to install it over the existing app.

The repository (or at least its Releases) must be **public** so players can download the APK.

## Local development (optional)

```bash
flutter create --platforms=android --org com.dazzlingwins --project-name dazzlingwins .
python3 scripts/prepare_android.py
flutter pub get
flutter run
```
