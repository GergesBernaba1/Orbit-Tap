# Orbit Tap

Suggested public app name: `Orbit Tap`

Flutter foundation for a vault-style mobile app that can:

- import images and videos into encrypted app storage
- copy contact details into an encrypted vault
- maintain a private app list and launch those apps from inside the vault
- disguise the secure area behind a decoy mini-game

## Brand direction

- Public-facing name: `Orbit Tap`
- Cover story: a fast reflex mini-game with player profiles
- Unlock behavior: typing the original secret code into the player/load field opens the vault

## Important platform constraint

True hiding of other installed apps from the system launcher is not generally possible on standard Android/iOS devices without special privileges such as device-owner mode, OEM integrations, or root/jailbreak. This project implements the realistic version:

- encrypted storage for private media and contacts
- a private app launcher list inside the vault
- a decoy game screen where the secret passcode can be typed as a normal player/load code
- clear separation so a future Android device-owner build can extend the app layer

## Project status

This workspace did not include a Flutter SDK, so the app code was created manually. To run it:

1. Install Flutter and add it to `PATH`.
2. From this folder, run `flutter create .` to generate the missing platform folders if needed.
3. Run `flutter pub get`.
4. Run `flutter run`.

## Suggested next iteration

- biometric unlock with `local_auth`
- decoy mode / disguised launcher icon
- secure export / restore flow
- Android device-owner build for managed-device app policies

## Build APK from GitHub

The repo includes a GitHub Actions workflow at `.github/workflows/build-apk.yml`.

After pushing this project to GitHub:

1. Open the repository on GitHub.
2. Go to `Actions`.
3. Run `Build APK` manually, or push to `main` / `master`.
4. Download the `orbit-tap-release-apk` artifact from the workflow run.

