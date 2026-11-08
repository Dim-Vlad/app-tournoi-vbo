# Backend Supabase — Tournoi VBO

Schéma de base de données pour l'application de gestion de tournois du **Volley-Ball Ollioulais**.

> 🧩 **Cohabitation.** Tout l'applicatif VBO vit dans un **schéma dédié `vbo`** (pas `public`). On peut donc l'installer dans un projet Supabase **déjà utilisé** (ex. le portfolio) sans aucun conflit avec ses tables, et sans que ses comptes de connexion obtiennent le moindre accès aux données VBO (voir « Isolation » plus bas).

## Modèle de comptes

| Rôle | Compte ? | Accès |
|------|----------|-------|
| **Admin** | Oui (Supabase Auth, e-mail + mot de passe) | Crée et gère tout : tournois, équipes, poules, matchs, référents. |
| **Référent gymnase** | Oui (créé par l'admin) | Voit tous les tournois, saisit les scores sur place. |
| **Capitaine** | **Non** | Rejoint un tournoi via le **code** (`join_code`) / QR, consulte ses matchs et saisit ses scores — via des fonctions RPC sécurisées, avec la clé **anon**. |

> Le modèle « compte de gymnase partagé » reste possible : c'est simplement un profil référent dont plusieurs personnes connaissent le mot de passe. Le schéma gère des référents individuels (recommandé), ce qui n'empêche pas d'en partager un.

## Isolation vis-à-vis des autres comptes du projet

Le projet Supabase réutilisé (portfolio) a ses propres comptes Auth (ta connexion d'admin). Deux garde-fous les tiennent à l'écart de VBO :

1. **Schéma séparé `vbo`** → les tables du portfolio (dans `public`) ne sont jamais touchées, et aucun conflit de noms même en cas de table homonyme.
2. **Déclencheur prudent** → le trigger `vbo.handle_new_user` ne crée un profil VBO **que** pour les comptes dont le `user_metadata` contient `{ "app": "vbo" }`. Un compte créé par le portfolio n'a donc **aucun** profil VBO → **aucun** accès aux tables `vbo.*` via la RLS. Le trigger porte un nom propre (`on_auth_user_created_vbo`) et ne remplace pas un éventuel trigger d'inscription existant.

## Contenu

```
supabase/
├── migrations/
│   └── 0001_init.sql   ← schéma vbo : types, tables, RLS, RPC capitaines, realtime
└── README.md
```

## Tables (schéma `vbo`)

| Table | Rôle |
|-------|------|
| `vbo.profiles` | 1 ligne par utilisateur VBO (admin / référent). Alimentée par trigger (comptes VBO uniquement). |
| `vbo.tournaments` | Un tournoi. `config` (jsonb) = tout le paramétrage de l'app. `join_code` pour les capitaines. |
| `vbo.gyms` | Gymnases d'un tournoi. |
| `vbo.teams` | Équipes. |
| `vbo.pools` | Poules (par phase + gymnase/terrain). |
| `vbo.pool_teams` | Appartenance équipe ↔ poule. |
| `vbo.matches` | Matchs : horaire, terrain, équipes, arbitre, statut, score. |
| `vbo.score_entries` | Double saisie des capitaines (validation croisée). |

## Sécurité (Row-Level Security)

- **Admin** : accès total à tout (`vbo.is_admin()`).
- **Référent** : lecture de tout + mise à jour des `vbo.matches` (saisie sur place).
- **Capitaine (anon)** : aucune table exposée directement. Passe **uniquement** par ces fonctions, qui valident le `join_code` côté serveur :
  - `join_tournament(code)` → infos du tournoi (si live).
  - `tournament_teams(code)` → liste des équipes.
  - `team_matches(code, team_id)` → matchs de l'équipe.
  - `submit_score(code, match_id, team_id, score_a, score_b, sets)` → enregistre la saisie ; le match passe en `valid` quand les **deux** équipes saisissent le même résultat, sinon `pending`.

Les helpers `vbo.app_role()` / `vbo.is_admin()` / `vbo.is_staff()` sont en `SECURITY DEFINER` pour éviter la récursion RLS sur `vbo.profiles`.

## Mise en place (dans le projet existant — ex. portfolio)

1. **SQL Editor** → coller `migrations/0001_init.sql` → **Run**.
   *(ou, avec la CLI : `supabase db push`)*
2. **Exposer le schéma à l'API** (sinon l'app ne verra pas `vbo`) :
   **Project Settings → API → Exposed schemas** → ajouter **`vbo`** (garder `public`), puis **Save**.
3. Créer le compte **admin** VBO :
   - **Authentication → Users → Add user** (e-mail + mot de passe).
   - Le trigger ne s'applique qu'aux comptes `app='vbo'`, donc fixer le profil admin manuellement dans **SQL Editor** :
     ```sql
     insert into vbo.profiles (id, email, full_name, role, status)
     select id, email, 'Admin VBO', 'admin', 'active'
     from auth.users where email = 'admin@exemple.fr'
     on conflict (id) do update set role = 'admin', status = 'active';
     ```
   > Variante : réutiliser **ton compte portfolio existant** comme admin VBO — même requête, avec son e-mail. Un seul login pour tout. (Sinon, un compte dédié garde les deux apps bien séparées.)
4. Créer les comptes **référents** : depuis l'app (admin → Référents → *Créer un référent*). L'admin saisit prénom, nom, e-mail et un **mot de passe** (avec un générateur). L'app appelle la fonction Edge `create-referent` (voir ci-dessous), qui crée le compte **avec ce mot de passe** (actif immédiatement). L'app affiche ensuite un **message prêt à copier-coller** (lien + identifiants) que l'admin transmet lui-même (mail, SMS…). Le compte est créé avec `user_metadata = { app: 'vbo', full_name, role: 'referent' }`, donc le trigger `vbo.handle_new_user` crée le profil automatiquement. **Le `app: 'vbo'` est indispensable** : sans lui, aucun profil n'est créé.

## Fonction Edge `create-referent` (création du compte référent)

Source : `functions/create-referent/index.ts`. Elle vérifie que l'appelant est **admin VBO**, puis crée le compte référent avec le mot de passe choisi (`auth.admin.createUser`, `email_confirm: true`). **Aucun e-mail n'est envoyé par le serveur** : l'app génère un message copiable que l'admin envoie à la main → **pas de SMTP ni de clé e-mail à configurer**.

**Déploiement (à faire par toi — la clé service_role ne doit jamais passer par l'app ni par l'assistant) :**

1. Définir le secret de la fonction :
   - **Via le dashboard** : Project Settings → Edge Functions → Secrets → ajouter `SUPABASE_SERVICE_ROLE_KEY` (valeur : Project Settings → API → *service_role*).
   - **Ou via la CLI** (connectée au projet) :
     ```bash
     supabase secrets set SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxxxxxxx
     ```
   *(`SUPABASE_URL` et `SUPABASE_ANON_KEY` sont injectés automatiquement.)*
2. Déployer la fonction :
   - **Via le dashboard** : Edge Functions → créer `create-referent` → coller le contenu de `functions/create-referent/index.ts` → Deploy.
   - **Ou via la CLI** :
     ```bash
     supabase functions deploy create-referent
     ```

> Repli sans fonction / sans Supabase : l'app garde un mode démo (référent fictif en local).

> ℹ️ Le SMTP (Authentication → Emails) n'est plus nécessaire pour les référents. Il ne sert qu'aux e-mails d'auth natifs de Supabase (ex. réinitialisation de mot de passe), si tu décides un jour de les activer.

## Côté application (prochaine étape)

Brancher le `state` fictif du prototype sur Supabase :
- `supabase-js` avec l'**URL** + la clé **anon** du projet, en ciblant le schéma `vbo` :
  ```js
  const supabase = createClient(URL, ANON, { db: { schema: 'vbo' } });
  ```
- Admin / référent : `supabase.auth.signInWithPassword(...)`.
- Capitaine : pas d'auth, appels `supabase.rpc('join_tournament', { p_code })`, etc. (le client est déjà sur le schéma `vbo`).
- Direct : `supabase.channel(...).on('postgres_changes', { schema: 'vbo', table: 'matches', ... })` sur `matches` / `pools` / `teams` / `tournaments` pour les scores et le classement en temps réel.

> ⚠️ Ne jamais exposer la clé **service_role** dans l'app front : seulement l'URL et la clé **anon** (publique, protégée par la RLS ci-dessus).
