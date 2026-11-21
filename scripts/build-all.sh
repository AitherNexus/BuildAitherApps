#!/usr/bin/env bash
set -uo pipefail
set +x

ROOT="$(pwd)"
OUT="$ROOT/release-files"
ASSETS="$ROOT/release-assets"
WORK="$ROOT/.build-work"
REPORT="$ROOT/BUILD-REPORT.md"
mkdir -p "$OUT" "$ASSETS" "$WORK"
: > "$REPORT"

cat > "$REPORT" <<EOF
# Aither Nexus Apps — Build Report

- Build: ${BUILD_NUMBER:-local}
- Commit: ${BUILD_COMMIT:-unknown}
- Date: $(date -u +"%Y-%m-%d %H:%M UTC")

This build publishes individual app files. It does not create source-code archives or ZIP downloads.
EOF

# Display name | exact GitLab project path
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

ok=0
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
  echo "- GitLab project: https://gitlab.com/$project" >> "$REPORT"

  rm -rf "$src"
  if [[ -z "${GITLAB_TOKEN:-}" && "$project" != "aithernexus/AitherNexus" ]]; then
    echo "- Result: **SKIPPED** — GITLAB_TOKEN is missing." >> "$REPORT"
    skipped=$((skipped+1))
    echo >> "$REPORT"
    continue
  fi

  if [[ -n "${GITLAB_TOKEN:-}" ]]; then
    clone_url="https://oauth2:${GITLAB_TOKEN}@gitlab.com/$project.git"
  else
    clone_url="https://gitlab.com/$project.git"
  fi

  if ! git -c advice.detachedHead=false clone --quiet --depth 1 "$clone_url" "$src" 2>"$WORK/$slug-clone.log"; then
    echo "- Result: **DOWNLOAD FAILED** — see build artifact logs." >> "$REPORT"
    cp "$WORK/$slug-clone.log" "$dest/download-error.txt" 2>/dev/null || true
    failed=$((failed+1))
    echo >> "$REPORT"
    continue
  fi

  build_status="No build configuration detected"
  build_ok=1
  if [[ -f "$src/package.json" ]]; then
    pushd "$src" >/dev/null
    if [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
      npm ci --no-audit --no-fund >"$WORK/$slug-install.log" 2>&1 || build_ok=0
    else
      npm install --no-audit --no-fund >"$WORK/$slug-install.log" 2>&1 || build_ok=0
    fi

    if [[ "$build_ok" == "1" ]]; then
      if node -e "const p=require('./package.json');process.exit(p.scripts?.build?0:1)" 2>/dev/null; then
        npm run build >"$WORK/$slug-build.log" 2>&1 || build_ok=0
        build_status="npm build completed"
      else
        build_status="No npm build script; checking for deployable app files"
      fi
      # Only run desktop packaging scripts that the project explicitly defines.
      if node -e "const p=require('./package.json');process.exit(p.scripts?.dist?0:1)" 2>/dev/null; then
        npm run dist >>"$WORK/$slug-build.log" 2>&1 || build_ok=0
      fi
      if node -e "const p=require('./package.json');process.exit(p.scripts?.make?0:1)" 2>/dev/null; then
        npm run make >>"$WORK/$slug-build.log" 2>&1 || build_ok=0
      fi
      if node -e "const p=require('./package.json');process.exit(p.scripts?.package?0:1)" 2>/dev/null; then
        npm run package >>"$WORK/$slug-build.log" 2>&1 || build_ok=0
      fi
    else
      build_status="Dependency installation failed"
    fi
    popd >/dev/null
  fi

  # Collect only deployable output, never the repository/source tree or node_modules.
  picked=0
  for folder in dist build out release artifacts; do
    if [[ -d "$src/$folder" ]]; then
      while IFS= read -r -d '' file; do
        rel="${file#"$src/$folder/"}"
        mkdir -p "$dest/$(dirname "$rel")"
        cp "$file" "$dest/$rel"
        picked=$((picked+1))
      done < <(find "$src/$folder" -type f \
        ! -path '*/node_modules/*' ! -name '.env' ! -name '.env.*' \
        ! -name '*.pem' ! -name '*.key' ! -name '*.p12' ! -name '*.pfx' -print0)
    fi
  done

  # Static sites without a build output are still publishable from their public web root.
  if [[ "$picked" -eq 0 ]]; then
    for folder in public; do
      if [[ -d "$src/$folder" ]]; then
        while IFS= read -r -d '' file; do
          rel="${file#"$src/$folder/"}"
          mkdir -p "$dest/$(dirname "$rel")"
          cp "$file" "$dest/$rel"
          picked=$((picked+1))
        done < <(find "$src/$folder" -type f \
          ! -path '*/node_modules/*' ! -name '.env' ! -name '.env.*' \
          ! -name '*.pem' ! -name '*.key' ! -name '*.p12' ! -name '*.pfx' -print0)
      fi
    done
  fi
  if [[ "$picked" -eq 0 && -f "$src/index.html" ]]; then
    while IFS= read -r -d '' file; do
      rel="${file#"$src/"}"
      mkdir -p "$dest/$(dirname "$rel")"
      cp "$file" "$dest/$rel"
      picked=$((picked+1))
    done < <(find "$src" -maxdepth 3 -type f \
      ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/desktop/*' \
      ! -name 'package.json' ! -name '*lock*' ! -name '.env' ! -name '.env.*' \
      ! -name '*.pem' ! -name '*.key' ! -name '*.p12' ! -name '*.pfx' -print0)
  fi

  # Copy every deliverable as its own uniquely named GitHub Release asset.
  if [[ "$picked" -gt 0 ]]; then
    while IFS= read -r -d '' file; do
      rel="${file#"$dest/"}"
      safe_rel="$(printf '%s' "$rel" | sed 's#[/ ]#_#g')"
      cp "$file" "$ASSETS/${slug}__${safe_rel}"
    done < <(find "$dest" -type f -print0)
    echo "- Result: **$build_status** — $picked individual app files published." >> "$REPORT"
    echo "- Files: `release-files/$slug/` (also published individually in the release)." >> "$REPORT"
    ok=$((ok+1))
  else
    echo "- Result: **NO APP OUTPUT FOUND** — no deployable files were generated." >> "$REPORT"
    failed=$((failed+1))
  fi

  [[ -f "$WORK/$slug-build.log" ]] && cp "$WORK/$slug-build.log" "$dest-build.log"
  [[ -f "$WORK/$slug-install.log" ]] && cp "$WORK/$slug-install.log" "$dest-install.log"
  echo >> "$REPORT"
done

cat >> "$REPORT" <<EOF

## Totals

- Apps with files generated: $ok / ${#APPS[@]}
- Apps with build/download problems: $failed
- Apps skipped because token was missing: $skipped

The Actions artifact keeps each app's folder structure. GitHub Release assets are separate individual files named `appname__relative_path`. No ZIPs or source-code archives are created.
EOF

echo "Generated files for $ok apps; $failed failed; $skipped skipped."
