#!/usr/bin/env bash
# =============================================================================
# RepForge — build + déploiement iPhone (à lancer sur un Mac avec Xcode 26+)
#
#   ./scripts/deploy.sh                         # auto : devicectl si iPhone joignable, sinon SideStore
#   DEPLOY_MODE=devicectl ./scripts/deploy.sh   # installation directe (USB ou Wi-Fi), signée
#   DEPLOY_MODE=sidestore ./scripts/deploy.sh   # .ipa non signé + source SideStore + GitHub Release
#   DEPLOY_MODE=serve     ./scripts/deploy.sh   # .ipa + serveur HTTP local (SideStore, même Wi-Fi)
#
# Variables optionnelles :
#   DEVICE_ID        UDID/nom de l'iPhone pour devicectl (sinon 1er iPhone en mode développeur)
#   GITHUB_REPO      owner/repo pour publier la release (défaut : déduit de `git remote`)
#   SKIP_RELEASE=1   ne pas publier sur GitHub en mode sidestore
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="RepForge"
SCHEME="RepForge"
BUNDLE_ID="com.charbelfadel.repforge"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
IPA="$BUILD_DIR/$APP_NAME.ipa"
MODE="${DEPLOY_MODE:-auto}"

log()  { printf "\033[1;32m▶ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m⚠ %s\033[0m\n" "$*"; }
die()  { printf "\033[1;31m✖ %s\033[0m\n" "$*"; exit 1; }

[[ "$(uname)" == "Darwin" ]] || die "Ce script nécessite macOS + Xcode (xcodebuild)."
command -v xcodebuild >/dev/null || die "xcodebuild introuvable (installe Xcode)."

# --- 0. Pré-requis -----------------------------------------------------------
if ! command -v xcodegen >/dev/null; then
  log "Installation de XcodeGen (Homebrew)…"
  brew install xcodegen
fi
if [[ ! -f Config/Secrets.xcconfig ]]; then
  warn "Config/Secrets.xcconfig absent → copie de l'exemple (l'app tournera en mode local)."
  cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
fi

# --- 1. Version : build number = nombre de commits ----------------------------
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
MARKETING="$(grep -E '^MARKETING_VERSION' Config/Base.xcconfig | awk -F'= ' '{print $2}')"
log "Version $MARKETING ($BUILD_NUMBER)"

# --- 2. Génération du projet --------------------------------------------------
python3 scripts/generate_program.py >/dev/null
xcodegen generate --quiet

# --- 3. Choix du mode ---------------------------------------------------------
find_device() {
  if [[ -n "${DEVICE_ID:-}" ]]; then echo "$DEVICE_ID"; return; fi
  local json="$BUILD_DIR/devices.json"
  mkdir -p "$BUILD_DIR"
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || return 1
  python3 - "$json" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit(1)
for d in data.get("result", {}).get("devices", []):
    if d.get("hardwareProperties", {}).get("platform") == "iOS" \
       and d.get("deviceProperties", {}).get("developerModeStatus") == "enabled":
        print(d["identifier"])
        break
PY
}

TEAM="$(grep -E '^DEVELOPMENT_TEAM' Config/Secrets.xcconfig 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' ' || true)"
DEVICE=""
if [[ "$MODE" == "auto" ]]; then
  if [[ -n "$TEAM" ]] && DEVICE="$(find_device)" && [[ -n "$DEVICE" ]]; then MODE="devicectl"; else MODE="sidestore"; fi
fi
log "Mode de déploiement : $MODE"

# --- 4a. Installation directe (signée avec ton compte Apple) -----------------
if [[ "$MODE" == "devicectl" ]]; then
  [[ -n "$TEAM" ]] || die "DEVELOPMENT_TEAM manquant dans Config/Secrets.xcconfig."
  [[ -n "$DEVICE" ]] || DEVICE="$(find_device || true)"
  [[ -n "$DEVICE" ]] || die "Aucun iPhone joignable (mode développeur activé + même Wi-Fi ou USB)."
  log "Build signé (team $TEAM)…"
  xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration Release \
    -destination "generic/platform=iOS" -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build
  APP_PATH="$DERIVED/Build/Products/Release-iphoneos/$APP_NAME.app"
  [[ -d "$APP_PATH" ]] || die "Build introuvable : $APP_PATH"
  log "Installation sur ${DEVICE}…"
  xcrun devicectl device install app --device "$DEVICE" "$APP_PATH"
  xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" || true
  log "✅ Installé et lancé sur l'iPhone."
  exit 0
fi

# --- 4b. IPA non signé (SideStore re-signe avec ton Apple ID) -----------------
log "Archive non signée…"
rm -rf "${BUILD_DIR:?}/${APP_NAME:?}.xcarchive" "${BUILD_DIR:?}/Payload" "${IPA:?}"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  -derivedDataPath "$DERIVED" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  archive

mkdir -p "$BUILD_DIR/Payload"
cp -R "$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app" "$BUILD_DIR/Payload/"
(cd "$BUILD_DIR" && zip -qry "$APP_NAME.ipa" Payload)
SIZE=$(stat -f%z "$IPA")
log "IPA : $IPA ($((SIZE / 1024 / 1024)) Mo)"

# --- 5. Source SideStore/AltStore --------------------------------------------
REPO="${GITHUB_REPO:-$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' || true)}"
TAG="v$MARKETING-$BUILD_NUMBER"
if [[ "$MODE" == "serve" ]]; then
  IP="$(ipconfig getifaddr en0 || echo localhost)"
  DOWNLOAD_URL="http://$IP:8787/$APP_NAME.ipa"
else
  DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$APP_NAME.ipa"
fi
python3 scripts/update_source.py --version "$MARKETING" --build "$BUILD_NUMBER" \
  --size "$SIZE" --url "$DOWNLOAD_URL" --repo "$REPO" --notes "$(git log -1 --pretty=%s)"

if [[ "$MODE" == "serve" ]]; then
  cp sidestore/source.json "$BUILD_DIR/source.json"
  log "Serveur local : ajoute http://$IP:8787/source.json dans SideStore (Ctrl-C pour arrêter)"
  (cd "$BUILD_DIR" && python3 -m http.server 8787)
  exit 0
fi

# --- 6. Publication GitHub Release + push de la source ------------------------
if [[ -z "${SKIP_RELEASE:-}" ]] && command -v gh >/dev/null && [[ -n "$REPO" ]]; then
  log "Publication de la release ${TAG}…"
  gh release create "$TAG" "$IPA" --repo "$REPO" --title "RepForge $MARKETING ($BUILD_NUMBER)" \
    --notes "$(git log -1 --pretty=%s)" --latest || warn "Release déjà existante ?"
  git add sidestore/source.json
  git commit -m "chore(release): $TAG" >/dev/null 2>&1 || true
  git push origin HEAD:main || warn "Push de la source impossible."
fi

log "✅ Terminé. Sur l'iPhone : SideStore › Mes apps › RepForge › Mettre à jour"
log "   Source : https://raw.githubusercontent.com/$REPO/main/sidestore/source.json"
