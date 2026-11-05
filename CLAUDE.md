# RepForge — consignes pour Claude Code

- App iOS SwiftUI/Swift 6, projet généré par XcodeGen (`project.yml`). Ne jamais versionner le `.xcodeproj`.
- Programme d'entraînement : source unique `scripts/generate_program.py` → régénérer `program.json` + `supabase/seed.sql`.
- Toute modif de schéma : nouvelle migration dans `supabase/migrations/`, RLS avec `(select auth.uid())`.
- Interface en français, esthétique Apple Fitness (noir OLED, `.ultraThinMaterial`, `.fontDesign(.rounded)`).

## Workflow à chaque modification validée
1. `./scripts/git-backup.sh "<type>: <message>"` (types : feat, fix, ui, chore, refactor) → commit + push `main`.
2. Le push déclenche le workflow GitHub Actions qui build l'IPA et met à jour la source SideStore.
3. Sur un Mac : `./scripts/deploy.sh` pour une installation directe.
4. Vérifier le résultat du workflow (`gh run list --limit 1`) et corriger les erreurs de compilation.
