# RepForge 🏋️

App iOS native de suivi de musculation, pensée pour la salle : saisie au pavé numérique, chrono de repos
dans la Dynamic Island, pause séance, analyse de progression, sync Supabase offline-first et Apple Santé.

| | |
|---|---|
| **Cible** | iPhone 15 Pro · iOS 18+ (optimisé iOS 27) · Swift 6 · SwiftUI · `@Observable` |
| **Local** | SwiftData (offline-first) |
| **Cloud** | Supabase (Auth Google + Apple, PostgreSQL + RLS) |
| **Apple** | ActivityKit, WidgetKit, App Intents (bouton Action), HealthKit, UserNotifications, Swift Charts |

## Arborescence

```
App/                    Cible application
  Models/               Entités SwiftData (session, série, biométrie, profil, template)
  Program/              Types du programme + chargement de program.json
  Services/             WorkoutController (chrono/pause), SyncEngine, Auth, HealthKit, Live Activity, audio
  Features/             Écrans SwiftUI (Entraînement, Séance, Analyse, Profil, Connexion)
  DesignSystem/         Thème noir OLED, cartes .ultraThinMaterial, SF Pro Rounded
  Resources/            program.json (généré), Assets
Shared/                 Compilé dans l'app ET l'extension (attributs Live Activity, App Intents, App Group)
Widgets/                Extension : Live Activity (Dynamic Island + écran verrouillé) + widget "Prochaine séance"
supabase/               Migration SQL (tables + RLS) et seed du programme
scripts/                generate_program.py · deploy.sh · git-backup.sh · update_source.py
sidestore/source.json   Source SideStore/AltStore (mise à jour automatique)
project.yml             Projet Xcode (XcodeGen) — le .xcodeproj n'est pas versionné
```

## 1. Supabase

1. Dashboard › SQL Editor : exécuter `supabase/migrations/20261105000000_init.sql` puis `supabase/seed.sql`
   (ou `supabase link && supabase db push && psql … -f supabase/seed.sql`).
2. Authentication › URL Configuration › **Redirect URLs** : ajouter `repforge://auth-callback`.
3. Authentication › Providers :
   - **Google** : Client ID/Secret OAuth (type *Web*) de Google Cloud.
   - **Apple** : ajouter le bundle ID `com.charbelfadel.repforge` dans *Client IDs* (connexion native par jeton).
4. Copier `Config/Secrets.example.xcconfig` → `Config/Secrets.xcconfig` et renseigner
   `SUPABASE_HOST` (sans `https://`) et `SUPABASE_ANON_KEY`.

Sans clés, l'app fonctionne entièrement en local (« Continuer hors ligne »).

## 2. Build & installation sur l'iPhone

### Option A — sans Mac : GitHub Actions + SideStore (recommandé)
Chaque `git push` sur `main` déclenche `.github/workflows/build-ipa.yml` : build sur un Mac GitHub,
IPA non signé publié en Release, `sidestore/source.json` mis à jour.

1. Repo GitHub › Settings › Secrets › Actions : `SUPABASE_HOST`, `SUPABASE_ANON_KEY`.
2. Dans SideStore › Sources › **+** :
   `https://raw.githubusercontent.com/<owner>/<repo>/main/sidestore/source.json`
3. À chaque nouvelle version : SideStore › Mes apps › RepForge › **Mettre à jour**.

### Option B — avec un Mac
```bash
brew install xcodegen
./scripts/deploy.sh                       # auto
DEPLOY_MODE=devicectl ./scripts/deploy.sh # installation directe Wi-Fi/USB (DEVELOPMENT_TEAM requis)
DEPLOY_MODE=serve ./scripts/deploy.sh     # IPA servi en HTTP local pour SideStore
```

### ⚠️ Limites d'un Apple ID gratuit (SideStore)
- **Sign in with Apple** et l'entitlement **Time-Sensitive** exigent un compte développeur payant.
  Si SideStore refuse l'installation, retirer `com.apple.developer.applesignin` et
  `com.apple.developer.usernotifications.time-sensitive` de `project.yml` (la connexion Google suffit ;
  les notifications deviennent « actives » au lieu de « urgentes »).
- L'app + son extension widget consomment **2 App IDs** (limite : 10 par semaine, 3 apps actives).
- Re-signature tous les 7 jours (automatique via SideStore + LocalDevVPN).

## 3. Fonctionnement clé

- **Chrono de repos** : démarre automatiquement au check d'une série, durée propre à chaque série
  (3 min = changement d'exercice). `+10 s` illimité dans l'app et la Live Activity.
- **Pause séance** : fige le temps actif et le repos restant, reprise exacte (pauses envoyées à Santé
  comme évènements pause/reprise).
- **00:00** : app ouverte → bandeau + vibration marquée ; iPhone déverrouillé → la Dynamic Island s'étend
  (alerte Live Activity) ; iPhone verrouillé → notification Time-Sensitive. Le bip baisse la musique
  (`.duckOthers`) sans la couper. Un flux audio silencieux mixé maintient le chrono actif en arrière-plan
  (désactivable dans Profil).
- **Bouton Action** : Réglages › Bouton Action › Raccourci › RepForge › « Valider la série » (coche la
  prochaine série avec les valeurs de la séance précédente et lance le repos).
- **Placeholders gris** : valeurs de la séance précédente ; si les champs sont vides au moment du check,
  ces valeurs sont reprises.
- **Délestage** : moins d'aide = progression (badge vert, axe des graphiques inversé). Avec le poids du
  corps renseigné, la charge réelle (poids du corps − aide) est utilisée pour le volume.
- **Sync** : push des lignes modifiées puis pull incrémental sur `updated_at` ; après réinstallation,
  restauration complète à la connexion. Suppressions propagées par tombstone (`deleted_at`).

## Modifier le programme
Éditer `scripts/generate_program.py`, puis `python3 scripts/generate_program.py` (régénère
`App/Resources/program.json` et `supabase/seed.sql` avec les mêmes UUID).
