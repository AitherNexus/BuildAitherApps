# BuildAitherApps

One place to build and download the Aither Nexus apps.

This repository uses **GitHub Actions** to clone the Aither Nexus projects from GitLab, run their available build scripts, and publish downloadable bundles.

## One-time setup (required for private projects)

Most Aither Nexus repositories are private on GitLab. Without a token, the workflow still packages the public AitherNexus portal and AitherBackend, and marks private projects as skipped. To build the complete app list, create a GitLab Personal Access Token with **read_repository** scope, then add it to this GitHub repository:

1. Open **Settings → Secrets and variables → Actions**.
2. Choose **New repository secret**.
3. Name it exactly `GITLAB_TOKEN`.
4. Paste the GitLab token as the value and save.

The token is only used by the workflow to clone your GitLab projects. It is not written into the generated archives or logs. Do not put it in a file or commit it. After saving the secret, run the workflow again to build all private projects too.

## Run a build

- Open the **Actions** tab.
- Select **Build All Aither Nexus Apps**.
- Choose **Run workflow**.

The workflow also runs when the build configuration or build scripts are updated on `main`.

## Where downloads appear

Every run publishes two ways to get the files:

- **Actions artifact**: a complete bundle named `aither-nexus-all-apps-<run>`, including all app folders, source archives, generated build outputs, build logs, and the build report. Actions artifacts are retained for 30 days.
- **GitHub Release**: a permanent release for that run with a separate `<app>-app.zip` download for every successfully cloned app, plus separate source and generated-output ZIPs.

Open the [latest release downloads](../../releases/latest). The release notes contain direct links to each individual app. You do not have to download the all-apps bundle to get just one app.

Open [latest builds](../../actions/workflows/build-all-apps.yml) or [releases](../../releases).

## What gets included

The build list is in [apps.json](apps.json). It currently includes the active Aither Nexus apps and supporting projects: AitherCore, AitherHomeOS, AitherCloud, AitherChat, AitherSignIn, AitherNexus, AitherWeb, AitherGaming, AitherMail, AitherAppDownloads, AitherApps, AitherFiles, AitherError404, AitherClock, AitherAI, AitherCalculator, AitherMaps, AitherDashboard, AitherNotes, AitherWeather, AitherBackend, AitherPrivacy, and AitherTerms.

For each project, the workflow creates an individual app ZIP, a source ZIP, and (when generated) a separate build-output ZIP. It attempts the project's npm build and desktop packaging scripts, and collects generated `dist`, `build`, `out`, `public`, `desktop`, `artifacts`, and `release` folders.

For projects that already use Electron Builder, it also attempts Windows portable ZIP and Linux AppImage/DEB desktop packages. Electron Forge and Tauri projects are packaged when their project configuration supports those build commands. These native installers are not magically created for projects that are only websites or APIs: those projects still receive their own app/source bundle, and need a desktop wrapper or native project configuration before they can produce a Windows/macOS installer.

A project build error is recorded in its log and report without preventing the other apps from being packaged.

## Cost

The workflow uses GitHub-hosted Actions runners and GitHub's artifact/release storage. GitHub's usage limits and retention policies apply; this repository does not create a Render service or other paid hosting resource.
