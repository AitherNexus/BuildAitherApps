#!/usr/bin/env bash
set -uo pipefail
set +x

ROOT="$(pwd)"
PLATFORM="${BUILD_PLATFORM:-linux}"
OUT="$ROOT/release-files"
ASSETS="$ROOT/release-assets"
WORK="$ROOT/.build-work"
REPORT="$ROOT/BUILD-REPORT.md"
mkdir -p "$OUT" "$ASSETS" "$WORK"
: > "$REPORT"

cat > "$REPORT" <<EOF
# Aither Nexus Native App Build Report

- Build: ${BUILD_NUMBER:-local}
- Platform: $PLATFORM
- Commit: ${BUILD_COMMIT:-unknown}

Only installable application packages are published. Repository source files, website files, source archives, and ZIP bundles are excluded.
EOF

APPS=(
  "AitherCore|aithernexus/aithercore"
  "AitherHomeOS|aithernexus/aitherhomeos"
  "AitherCloud|aithernexus/aithercloud"
  "AitherChat|aithernexus/aitherchat"
  "AitherSignIn|aithernexus/aithersignin"
  "AitherNexus|aithernexus/AitherNexus"
  "AitherWeb|aithernexus/AitherWeb"
  "AitherGaming|aithernexus/AitherGaming"
  "AitherMail|aithernexus/AitherMail"
  "AitherAppDownloads|aithernexus/AitherAppDounloads"
  "AitherApps|aithernexus/AitherApps"
  "AitherFiles|aithernexus/AitherFiles"
  "AitherError404|aithernexus/AitherError404"
  "AitherClock|aithernexus/AitherClock"
  "AitherAI|aithernexus/AitherAI"
  "AitherCalculator|aithernexus/AitherCalculator"
  "AitherMaps|aithernexus/AitherMaps"
  "AitherDashboard|aithernexus/AitherDashboard"
  "AitherNotes|aithernexus/AitherNotes"
  "AitherWeather|aithernexus/aitherweather"
  "AitherPrivacy|aithernexus/privacy"
  "AitherTerms|aithernexus/terms"
)

success=0
failed=0
skipped=0

for entry in "${APPS[@]}"; do
  app="${entry%%|*}"
  project="${entry#*|}"
  slug="$(printf '%s' "$app" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
  src="$WORK/$slug"
  dest="$OUT/$slug"
  mkdir -p "$dest"
  echo "## $app" >> "$REPORT"
  echo "- Source project: https://gitlab.com/$project" >> "$REPORT"

  rm -rf "$src"
  if [[ -z "${GITLAB_TOKEN:-}" && "$project" != "aithernexus/AitherNexus" ]]; then
    echo "- Result: **SKIPPED** — GitLab token unavailable." >> "$REPORT"
    skipped=$((skipped+1)); echo >> "$REPORT"; continue
  fi
  if [[ -n "${GITLAB_TOKEN:-}" ]]; then
    clone_url="https://oauth2:${GITLAB_TOKEN}@gitlab.com/$project.git"
  else
    clone_url="https://gitlab.com/$project.git"
  fi
  if ! git -c advice.detachedHead=false clone --quiet --depth 1 "$clone_url" "$src" 2>"$WORK/$slug-clone.log"; then
    echo "- Result: **DOWNLOAD FAILED**." >> "$REPORT"
    failed=$((failed+1)); echo >> "$REPORT"; continue
  fi

  status="No native packaging configuration found"
  if [[ -f "$src/package.json" ]]; then
    pushd "$src" >/dev/null
    if [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
      npm ci --no-audit --no-fund >"$WORK/$slug-install.log" 2>&1 || true
    else
      npm install --no-audit --no-fund >"$WORK/$slug-install.log" 2>&1 || true
    fi

    # Build the web bundle only as an input to a declared native wrapper.
    node -e "const p=require('./package.json');process.exit(p.scripts?.build?0:1)" 2>/dev/null && npm run build >"$WORK/$slug-build.log" 2>&1 || true

    # Electron Builder produces platform-native installers, not source bundles.
    if node -e "const p=require('./package.json');process.exit(p.devDependencies?.['electron-builder']||p.dependencies?.['electron-builder']?0:1)" 2>/dev/null; then
      case "$PLATFORM" in
        windows) npx electron-builder --win nsis portable >>"$WORK/$slug-native.log" 2>&1 && status="Windows EXE installer/portable app built" || status="Windows EXE packaging failed" ;;
        macos) npx electron-builder --mac dmg >>"$WORK/$slug-native.log" 2>&1 && status="macOS DMG installer built (contains the .app)" || status="macOS packaging failed" ;;
        linux) npx electron-builder --linux AppImage deb >>"$WORK/$slug-native.log" 2>&1 && status="Linux AppImage/DEB packages built" || status="Linux packaging failed" ;;
      esac
    fi

    # Tauri builds natively for the current runner OS.
    if node -e "const p=require('./package.json');process.exit(p.devDependencies?.['@tauri-apps/cli']||p.dependencies?.['@tauri-apps/cli']?0:1)" 2>/dev/null; then
      npm run tauri -- build >>"$WORK/$slug-native.log" 2>&1 && status="Tauri native package built" || status="Tauri native packaging failed"
    fi
    popd >/dev/null
  fi

  # Android projects with a Gradle wrapper can produce APK/AAB files.
  if [[ -f "$src/gradlew" ]]; then
    chmod +x "$src/gradlew" 2>/dev/null || true
    (cd "$src" && ./gradlew assembleDebug bundleDebug) >"$WORK/$slug-android.log" 2>&1 || true
    status="Android Gradle build attempted"
  fi

  # Collect ONLY actual installable binaries. Never copy source, HTML, JS, CSS or ZIPs.
  count=0
  while IFS= read -r -d '' file; do
    ext="${file##*.}"
    ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
    case "$ext" in
      exe|msi|dmg|appimage|deb|rpm|apk|aab|ipa|pkg)
        base="$(basename "$file")"
        cp "$file" "$dest/$base"
        cp "$file" "$ASSETS/${slug}__${PLATFORM}__${base}"
        count=$((count+1))
        ;;
    esac
  done < <(find "$src" -type f \
    ! -path '*/node_modules/*' ! -path '*/.git/*' \
    \( -path '*/dist/*' -o -path '*/build/*' -o -path '*/out/*' -o -path '*/release/*' -o -path '*/artifacts/*' -o -path '*/app/build/*' -o -path '*/android/app/build/*' \) -print0)

  # Preserve a native macOS .app directory in the Actions artifact; GitHub releases get its DMG.
  if [[ "$PLATFORM" == "macos" ]]; then
    while IFS= read -r -d '' appdir; do
      mkdir -p "$dest/$(basename "$appdir")"
      cp -R "$appdir/." "$dest/$(basename "$appdir")/"
      count=$((count+1))
    done < <(find "$src" -type d -name '*.app' -print0)
  fi

  if [[ "$count" -gt 0 ]]; then
    echo "- Result: **$status** — $count native installer/app deliverable(s)." >> "$REPORT"
    success=$((success+1))
  else
    echo "- Result: **NO NATIVE INSTALLER** — $status. This project needs a desktop/mobile wrapper and platform build configuration before it can produce an EXE, APP/DMG, APK, etc." >> "$REPORT"
    failed=$((failed+1))
  fi
  echo >> "$REPORT"
done

cat >> "$REPORT" <<EOF

## Totals
- Apps with native deliverables: $success / ${#APPS[@]}
- Apps without a native deliverable or with build errors: $failed
- Apps skipped because token was missing: $skipped

No source code or ZIP files are included. A website-only project cannot become an installable native app until it has a native wrapper (for example Electron, Tauri, Capacitor, or a native Android project).
EOF
echo "Native packages generated for $success apps; $failed without native packages; $skipped skipped."
