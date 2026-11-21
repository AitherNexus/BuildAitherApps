# BuildAitherApps

Builds native installable versions of the Aither Nexus apps where the app repository has a supported desktop or mobile wrapper.

## Native build targets

GitHub Actions builds on three operating systems:
- Windows: `.exe` and `.msi` (Electron Builder)
- macOS: `.dmg` installer containing the `.app` bundle (and the raw `.app` directory in the Actions artifact)
- Linux: `.AppImage`, `.deb`, and `.rpm` where supported
- Android: `.apk` and `.aab` when a Gradle Android project exists
- iOS: `.ipa` only when a properly configured iOS project and signing setup are available

**No source code is published. No source-code ZIPs or all-app ZIPs are created.** Only actual native installer/application outputs are published. Website HTML, CSS, JavaScript, repository files, and build source are never copied into the download area.

## Secure GitLab access

BuildAitherApps retrieves the existing `GITLAB_TOKEN` from Aither Backend at build time. GitHub Actions requests a short-lived GitHub OIDC identity token and sends it to `https://aitherbackend.onrender.com/api/build/gitlab-token`. Aither Backend verifies the caller before returning the token. The GitLab token is not stored in this repository or included in downloads.

Aither Backend must have its `GITLAB_TOKEN` environment variable set and the endpoint must authorize this repository's workflow.

## Run a build

Each Aither product has its own workflow in the **Actions** tab. Choose the product you want and select **Run workflow**. Product workflows build only that product's GitLab repository on Windows, macOS, and Linux.

There is also a **Build All Aither Nexus Native Apps** workflow for building the full product list together.

The product workflows call the shared `.github/workflows/build-one-app.yml` workflow, so packaging and secure token handling stay consistent.

## Downloads

- [Latest native app releases](../../releases)
- [Build runs and per-platform reports](../../actions/workflows/build-all-apps.yml)

Every generated installer is uploaded as its own release asset, named with the app and platform. The Actions artifacts retain app-specific output folders and macOS `.app` bundles.

## Important build requirement

A website is not automatically a Windows, Mac, or Android app. Each project must include a native packaging setup such as Electron, Tauri, Capacitor with an Android project, or a native Gradle project. This workflow detects supported configurations and builds them on the correct operating system. Projects without a native wrapper will be reported as having no native installer; the workflow will not disguise website/source files as an app download.

A macOS `.app` is a folder bundle, so the convenient installable download is a `.dmg` containing that `.app`. GitHub Releases receive the `.dmg`; the raw `.app` bundle is retained in the Actions artifact.

## Cost

This workflow uses GitHub-hosted runners and GitHub artifact/release storage. GitHub usage limits and retention policies apply. It does not create a Render service or other paid hosting resource.
