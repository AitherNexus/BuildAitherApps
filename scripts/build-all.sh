#!/usr/bin/env bash
set -uo pipefail
set +x

ROOT="$(pwd)"
OUT="$ROOT/release-files"
WORK="$ROOT/.build-work"
REPORT="$ROOT/BUILD-REPORT.md"
mkdir -p "$OUT" "$WORK"
: > "$REPORT"

if [[ -z "${GITLAB_TOKEN:-}" ]]; then
  echo "GITLAB_TOKEN is not set. Building public projects only; private projects will be listed as skipped."
fi

cat > "$REPORT" <<EOF
# Aither Nexus Apps — Build Report

- Build: ${BUILD_NUMBER:-local}
- Commit: ${BUILD_COMMIT:-unknown}
- Date: $(date -u +"%Y-%m-%d %H:%M UTC")

This build downloads the app repositories from GitLab, attempts their available build scripts, and packages both source and generated output. Build failures are recorded per app so one broken project does not stop the rest.
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
  "AitherBackend|aithernexus/AitherBackend"
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
  echo "- GitLab: https://gitlab.com/$project" >> "$REPORT"

  rm -rf "$src"
  clone_url=""
  if [[ -n "${GITLAB_TOKEN:-}" ]]; then
    clone_url="https://oauth2:${GITLAB_TOKEN}@gitlab.com/$project.git"
  else
    case "$project" in
      aithernexus/AitherNexus|aithernexus/AitherBackend)
        clone_url="https://gitlab.com/$project.git"
        ;;
      *)
        echo "- Result: **SKIPPED** — private GitLab repository; add the GITLAB_TOKEN Actions secret to include it." >> "$REPORT"
        echo >> "$REPORT"
        printf 'Private project. Add GITLAB_TOKEN to GitHub Actions secrets to download this app.\n' > "$dest/PRIVATE-REPOSITORY-NEEDS-TOKEN.txt"
        skipped=$((skipped+1))
        continue
        ;;
    esac
  fi
  if ! git -c advice.detachedHead=false clone --quiet --depth 1 "$clone_url" "$src" 2>"$WORK/$slug-clone.log"; then
    echo "- Result: **DOWNLOAD FAILED** (check token access and project path)." >> "$REPORT"
    cp "$WORK/$slug-clone.log" "$dest/clone-error.log" 2>/dev/null || true
    failed=$((failed+1))
    echo >> "$REPORT"
    continue
  fi

  build_status="Source packaged; no build command detected"
  if [[ -f "$src/package.json" ]]; then
    pushd "$src" >/dev/null
    if [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
      if npm ci --no-audit --no-fund >"$WORK/$slug-npm-install.log" 2>&1; then
        install_ok=1
      else
        install_ok=0
      fi
    else
      if npm install --no-audit --no-fund >"$WORK/$slug-npm-install.log" 2>&1; then
        install_ok=1
      else
        install_ok=0
      fi
    fi

    if [[ "$install_ok" == "1" ]]; then
      build_ok=1
      npm run build --if-present >"$WORK/$slug-build.log" 2>&1 || build_ok=0
      # Desktop/Electron projects sometimes expose one of these packaging scripts.
      node -e "const p=require('./package.json');process.exit(p.scripts?.dist?0:1)" 2>/dev/null && npm run dist >>"$WORK/$slug-build.log" 2>&1 || true
      node -e "const p=require('./package.json');process.exit(p.scripts?.make?0:1)" 2>/dev/null && npm run make >>"$WORK/$slug-build.log" 2>&1 || true
      node -e "const p=require('./package.json');process.exit(p.scripts?.package?0:1)" 2>/dev/null && npm run package >>"$WORK/$slug-build.log" 2>&1 || true
      if [[ "$build_ok" == "1" ]]; then build_status="Build command completed"; else build_status="Build command failed; source and any generated output still packaged"; fi
    else
      build_status="Dependency installation failed; source still packaged"
    fi
    popd >/dev/null
  elif [[ -f "$src/pyproject.toml" || -f "$src/requirements.txt" || -f "$src"/*.py ]]; then
    if python -m compileall -q "$src" >"$WORK/$slug-python.log" 2>&1; then
      build_status="Python syntax compilation completed (dependencies not installed)"
    else
      build_status="Python syntax compilation failed; source still packaged"
    fi
  fi

  # Preserve the whole project source while excluding credentials and bulky dependencies.
  (
    cd "$src"
    zip -qr "$dest/$slug-source.zip" . \
      -x ".git/*" "node_modules/*" ".venv/*" "venv/*" \
         ".env" ".env.*" "**/.env" "**/.env.*" \
         "*.pem" "*.key" "*.p12" "*.pfx" "id_rsa" "id_ed25519"
  )

  # Publish generated build folders and desktop packages as a second download.
  stage="$WORK/$slug-output"
  rm -rf "$stage"
  mkdir -p "$stage"
  found=0
  for folder in dist build out public desktop artifacts; do
    if [[ -d "$src/$folder" ]]; then
      mkdir -p "$stage/$folder"
      cp -a "$src/$folder/." "$stage/$folder/"
      found=1
    fi
  done
  # Also include the complete static website tree so HTML/CSS/JS/assets are individually accessible.
  if [[ -f "$src/index.html" ]]; then
    mkdir -p "$stage/site"
    cp -a "$src/." "$stage/site/"
    rm -rf "$stage/site/.git" "$stage/site/node_modules" "$stage/site/.venv" "$stage/site/venv"
    find "$stage/site" -type f \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name '*.pfx' \) -delete
    found=1
  fi
  if [[ "$found" == "1" ]]; then
    (cd "$stage" && zip -qr "$dest/$slug-build-output.zip" .)
  else
    printf '%s\n' "No separate build-output directory or static index.html was generated. The complete project is available in the source archive." > "$dest/BUILD-OUTPUT-NOT-FOUND.txt"
  fi

  printf '# %s\n\n- GitLab project: https://gitlab.com/%s\n- Build result: %s\n- Source archive: %s-source.zip\n' "$app" "$project" "$build_status" "$slug" > "$dest/BUILD-INFO.md"
  [[ -f "$WORK/$slug-build.log" ]] && cp "$WORK/$slug-build.log" "$dest/build.log"
  [[ -f "$WORK/$slug-npm-install.log" ]] && cp "$WORK/$slug-npm-install.log" "$dest/install.log"
  [[ -f "$WORK/$slug-python.log" ]] && cp "$WORK/$slug-python.log" "$dest/python-check.log"

  echo "- Result: **$build_status**" >> "$REPORT"
  echo "- Downloads: $slug-source.zip and generated build output when available." >> "$REPORT"
  echo >> "$REPORT"
  if [[ "$build_status" == *failed* || "$build_status" == *Failure* ]]; then
    failed=$((failed+1))
  else
    ok=$((ok+1))
  fi
done

cat >> "$REPORT" <<EOF

## Totals

- Projects packaged: $((ok+failed)) / ${#APPS[@]}
- Completed without reported build errors: $ok
- Projects with build/download issues: $failed
- Private projects skipped because GITLAB_TOKEN is missing: $skipped

Each app folder in release-files/ contains its source archive, generated output archive when available, build information, and relevant logs.
EOF

# Always let the workflow publish successful packages and the report.
echo "Packaged $((ok+failed)) projects; skipped $skipped private projects; $failed had issues."
