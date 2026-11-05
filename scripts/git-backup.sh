#!/usr/bin/env bash
# Sauvegarde GitHub : ./scripts/git-backup.sh "feat: message conventionnel"
set -euo pipefail
cd "$(dirname "$0")/.."
MSG="${1:-chore: sauvegarde automatique}"
git add -A
if git diff --cached --quiet; then
  echo "Rien à commiter."
else
  git commit -m "$MSG"
fi
for delay in 0 2 4 8 16; do
  sleep "$delay"
  if git push -u origin main; then exit 0; fi
  echo "Push échoué, nouvelle tentative…"
done
exit 1
