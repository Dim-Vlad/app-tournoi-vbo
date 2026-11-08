# Backend Supabase — Tournoi VBO

Schéma de base de données pour l'application de gestion de tournois du **Volley-Ball Ollioulais**.

## Modèle de comptes

| Rôle | Compte ? | Accès |
|------|----------|-------|
| **Admin** | Oui (Supabase Auth, e-mail + mot de passe) | Crée et gère tout : tournois, équipes, poules, matchs, référents. |
| **Référent gymnase** | Oui (créé par l'admin) | Voit tous les tournois, saisit les scores sur place. |
| **Capitaine** | **Non** | Rejoint un tournoi via le **code** (`join_code`) / QR, consulte ses matchs et saisit ses scores — via des fonctions RPC sécurisées, avec la clé **anon**. |

> Le modèle « compte de gymnase partagé » reste possible : c'est simplement un profil référent dont plusieurs personnes connaissent le mot de passe. Le schéma gère des référents individuels (recommandé), ce qui n'empêche pas d'en partager un.

## Contenu

```
supabase/
├── migrations/
│   └── 0001_init.sql   ← types, tables, RLS, fonctions capitaines, realtime
└── README.md
```

## Tables

| Table | Rôle |
|-------|------|
| `profiles` | 1 ligne par utilisateur Auth (admin / référent). Alimentée par trigger. |
| `tournaments` | Un tournoi. `config` (jsonb) = tout le paramétrage de l'app. `join_code` pour les capitaines. |
| `gyms` | Gymnases d'un tournoi. |
| `teams` | Équipes. |
| `pools` | Poules (par phase + gymnase/terrain). |
| `pool_teams` | Appartenance équipe ↔ poule. |
| `matches` | Matchs : horaire, terrain, équipes, arbitre, statut, score. |
| `score_entries` | Double saisie des capitaines (validation croisée). |

## Sécurité (Row-Level Security)

- **Admin** : accès total à tout (`is_admin()`).
- **Référent** : lecture de tout + mise à jour des `matches` (saisie sur place).
- **Capitaine (anon)** : aucune table exposée directement. Passe **uniquement** par ces fonctions, qui valident le `join_code` côté serveur :
  - `join_tournament(code)` → infos du tournoi (si live).
  - `tournament_teams(code)` → liste des équipes.
  - `team_matches(code, team_id)` → matchs de l'équipe.
  - `submit_score(code, match_id, team_id, score_a, score_b, sets)` → enregistre la saisie ; le match passe en `valid` quand les **deux** équipes saisissent le même résultat, sinon `pending`.

Les helpers `current_role()` / `is_admin()` / `is_staff()` sont en `SECURITY DEFINER` pour éviter la récursion RLS sur `profiles`.

## Mise en place

1. Créer un projet sur [supabase.com](https://supabase.com).
2. **SQL Editor** → coller `migrations/0001_init.sql` → Run.
   *(ou, avec la CLI : `supabase db push`)*
3. Créer le compte **admin** :
   - **Authentication → Users → Add user** (e-mail + mot de passe).
   - Dans **SQL Editor**, passer son rôle en admin :
     ```sql
     update public.profiles set role = 'admin'
     where email = 'admin@exemple.fr';
     ```
4. Créer les comptes **référents** : depuis l'app (admin), via l'API admin Supabase (`auth.admin.createUser`) en passant `user_metadata = { full_name, role: 'referent' }` — le trigger `handle_new_user` crée le profil automatiquement.

## Côté application (prochaine étape)

Brancher le `state` fictif du prototype sur Supabase :
- `supabase-js` avec l'**URL** + la clé **anon** du projet.
- Admin / référent : `supabase.auth.signInWithPassword(...)`.
- Capitaine : pas d'auth, appels `supabase.rpc('join_tournament', { p_code })`, etc.
- Direct : `supabase.channel(...).on('postgres_changes', ...)` sur `matches` / `pools` / `teams` / `tournaments` pour les scores et le classement en temps réel.

> ⚠️ Ne jamais exposer la clé **service_role** dans l'app front : seulement l'URL et la clé **anon** (publique, protégée par la RLS ci-dessus).
