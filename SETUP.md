# Mise en route de RepForge, pas à pas

Ordre conseillé : **A → B → C**, puis **D** (avec un Mac) ou **E** (sans Mac).
Compter environ 30 minutes au total.

---

## A. Connecter le Mac à Claude (pour que Claude compile lui-même avec Xcode)

1. Sur le Mac, installer **Xcode** (App Store), l'ouvrir une fois et accepter la licence.
2. Ouvrir l'app **Claude** (desktop) › **Réglages** › **Claude Code** › **Remote Control**.
3. Activer Remote Control et **ajouter un dossier**, par exemple `~/Developer/RepForge`.
   (Ce ne doit pas être le dossier personnel lui-même, ni un dossier caché.)
4. Décompresser `RepForge.zip` dans ce dossier.
5. Laisser l'app Claude ouverte sur le Mac, puis me dire « c'est fait » dans la session :
   je pourrai alors lancer `xcodegen`, `xcodebuild` et `./scripts/deploy.sh` directement sur le Mac.

> Si le dossier n'apparaît pas pour une session cloud, cette fonction n'est peut-être pas encore
> disponible sur ton compte. Dans ce cas, ouvre directement une session **Claude Code sur le Mac**
> (app desktop › Claude Code › choisir le dossier RepForge) : elle aura Xcode et ce projet.

---

## B. GitHub (sauvegarde + build automatique)

1. Sur github.com › **New repository** :
   - Nom : `repforge`
   - Visibilité : **Public**. SideStore doit pouvoir télécharger l'IPA sans identifiant ;
     aucun secret n'est versionné (clés dans `Secrets.xcconfig` ignoré et dans les secrets GitHub).
   - **Ne pas** cocher README / .gitignore (dépôt vide).
2. Sur claude.ai › **Paramètres** › **Connecteurs** › **GitHub** : autoriser le dépôt
   `johncfadel-creator/repforge` pour Claude Code.
3. Me donner l'URL : je pousserai le code.
4. Dépôt › **Settings** › **Secrets and variables** › **Actions** › **New repository secret** :
   - `SUPABASE_HOST` = `xxxx.supabase.co` (sans `https://`)
   - `SUPABASE_ANON_KEY` = la clé *anon public*
5. Dépôt › **Settings** › **Actions** › **General** › *Workflow permissions* : **Read and write**.

---

## C. Supabase

### C1. Option rapide : me laisser faire
claude.ai › **Paramètres** › **Connecteurs** › **Supabase** › **Connecter** (connexion OAuth).
Le plugin est installé mais **pas encore autorisé**, et je ne peux pas lancer cette connexion
moi-même. Une fois autorisé, je peux créer le projet, appliquer le SQL et récupérer les clés.

### C2. Option manuelle (5 min)
1. supabase.com › **New project** (région : *Central EU (Frankfurt)*). Noter le mot de passe de la base.
2. **SQL Editor** › New query › coller tout `supabase/setup_all.sql` › **Run**.
   Vérifier dans **Table Editor** : 5 tables, et 4 lignes dans `workout_templates`.
3. **Project Settings** › **API** : copier *Project URL* et la clé **anon public**.
   ⚠️ Ne jamais utiliser ni partager la clé `service_role`.
4. **Authentication** › **URL Configuration** › *Redirect URLs* › Add : `repforge://auth-callback`

### C3. Connexion Google
1. console.cloud.google.com › créer un projet › **APIs & Services** › **OAuth consent screen**
   (External, nom « RepForge », ton e-mail) › ajoute-toi dans *Test users*.
2. **Credentials** › **Create credentials** › **OAuth client ID** › type **Web application** :
   - *Authorized redirect URI* : `https://<ton-projet>.supabase.co/auth/v1/callback`
3. Copier *Client ID* et *Client secret*, puis dans Supabase › **Authentication** › **Providers** ›
   **Google** › Enable, coller les deux valeurs › Save.

### C4. Connexion Apple (optionnelle)
Nécessite un **compte développeur Apple payant** (99 €/an). Avec un Apple ID gratuit
(SideStore), utilise uniquement Google.
Avec un compte payant : Supabase › Providers › **Apple** › Enable › *Client IDs* :
`com.charbelfadel.repforge`.

---

## D. Installer sur l'iPhone avec un Mac

```bash
cd ~/Developer/RepForge
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # puis renseigner les 3 valeurs
brew install xcodegen
./scripts/deploy.sh
```

- iPhone : **Réglages** › **Confidentialité et sécurité** › **Mode développeur** › activé.
- Le premier branchement se fait en USB (« Faire confiance »). Ensuite, le Wi-Fi suffit.
- `DEVELOPMENT_TEAM` : Xcode › Settings › Accounts › ton Apple ID › *Team ID*.
- Avec un Apple ID gratuit, l'app expire au bout de 7 jours. Relance `./scripts/deploy.sh`.

## E. Installer sur l'iPhone sans Mac (GitHub Actions + SideStore)

1. Une fois l'étape B faite, chaque push compile l'app sur un Mac GitHub (onglet **Actions**, ~10 min).
2. Dans SideStore › **Sources** › **+** :
   `https://raw.githubusercontent.com/johncfadel-creator/repforge/main/sidestore/source.json`
3. Installer RepForge depuis la source. Les mises à jour apparaissent ensuite dans **Mes apps**.

---

## F. Premier lancement sur l'iPhone

1. Autoriser les **notifications** : choisir « Autoriser ». Ensuite, Réglages › Notifications ›
   RepForge › activer **Notifications urgentes** (« Time-Sensitive »).
2. Profil › activer **Apple Santé** et tout autoriser.
3. Réglages › **RepForge** › vérifier que les **Activités en direct** sont activées.
4. **Bouton Action** : Réglages › Bouton Action › **Raccourci** › RepForge › « Valider la série ».
5. Écran verrouillé / d'accueil : ajouter le widget **Prochaine séance**.

## G. Dépannage

| Problème | Solution |
|---|---|
| SideStore refuse d'installer (entitlement) | Me demander de retirer *Sign in with Apple* et *Time-Sensitive* de `project.yml` (limites du compte gratuit) |
| « Limite d'App IDs atteinte » | Compte gratuit : 10 App IDs par semaine, et l'app + le widget en utilisent 2. Attendre ou supprimer d'anciennes apps dans SideStore |
| La Dynamic Island ne s'étend pas à 00:00 | Profil › « Chrono actif en arrière-plan » doit être activé |
| Pas de synchro | Profil › Compte : voir l'erreur affichée. Vérifier la clé anon et l'exécution du SQL |
