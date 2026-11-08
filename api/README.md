# API Tournoi VBO — PHP + MySQL (hébergement OVH)

Backend de l'application **Tournoi VBO**, à héberger sur le **même domaine** que
l'application (ex. dans un sous-dossier du site du club chez OVH). Comme tout est
servi par la même origine, l'authentification se fait par **cookie de session**
(pas de clé d'API, pas de token, pas de CORS).

```
votre-site/            ← l'application (index.html, sw.js, manifest, assets, icons)
votre-site/api/        ← ce dossier
```

## Contenu du dossier

| Fichier | Rôle |
|---|---|
| `index.php` | Point d'entrée de l'API. Toutes les requêtes passent par `?action=…`. |
| `_bootstrap.php` | Connexion à la base, session, fonctions communes. **Non public.** |
| `config.example.php` | Modèle de configuration à copier. |
| `config.php` | **À créer vous-même** avec vos identifiants OVH. Jamais versionné. |
| `schema.sql` | Création des tables MySQL. À importer une fois dans phpMyAdmin. |
| `install.php` | Création du premier compte admin. **À supprimer après usage.** |
| `.htaccess` | Protège les fichiers sensibles (config, schéma…). |

## Installation sur OVH (une seule fois)

### 1. Créer la base de données
Dans l'espace client OVH → **Hébergement → Bases de données**, créez une base
MySQL (ou utilisez une base existante). Notez :
- le **serveur** (ex. `mysqlxx-001.privatesql` ou `votrebasesql.mysql.db`) ;
- le **nom de la base** ;
- l'**utilisateur** et son **mot de passe**.

### 2. Importer les tables
Ouvrez **phpMyAdmin** (lien dans l'espace OVH), sélectionnez votre base, onglet
**Importer**, envoyez le fichier `api/schema.sql`, puis exécutez.

### 3. Configurer la connexion
Copiez `config.example.php` en `config.php` et renseignez vos identifiants :

```php
<?php
return [
  'db_host' => 'votrebasesql.mysql.db', // serveur MySQL OVH
  'db_name' => 'votrebase',
  'db_user' => 'votreutilisateur',
  'db_pass' => 'VOTRE_MOT_DE_PASSE',
  'db_port' => 3306,
  'https'   => true,                    // le site est en https (recommandé)
];
```

> `config.php` contient votre mot de passe : il n'est **jamais** mis sur GitHub
> (déjà listé dans `.gitignore`) et le `.htaccess` empêche de le télécharger.

### 4. Envoyer les fichiers sur OVH
Par FTP (FileZilla) ou l'explorateur de fichiers OVH, copiez **tout le projet**
(l'application + le dossier `api/`) dans le dossier voulu du site.

### 5. Créer le compte administrateur
Ouvrez dans le navigateur :

```
https://votre-site/api/install.php
```

Saisissez nom, e-mail et mot de passe (8 caractères min.) de l'admin, validez.

### 6. Supprimer install.php ⚠️
Une fois le compte créé, **supprimez `api/install.php`** du serveur. La page se
bloque d'elle-même dès qu'un compte existe, mais il est plus propre de la retirer.

C'est fini : ouvrez l'application, connectez-vous en tant qu'admin.

## Mises à jour suivantes
Pour publier une nouvelle version de l'app, ré-envoyez les fichiers modifiés
(`index.html`, `sw.js`, etc.). Pensez à incrémenter `CACHE` dans `sw.js` pour
forcer la mise à jour du cache côté navigateur. La base et `config.php` ne
bougent pas.

## Dépannage
- **« Configuration absente »** → `config.php` manque dans `/api`.
- **« Connexion à la base impossible »** → identifiants erronés dans `config.php`,
  ou serveur MySQL incorrect (vérifiez le nom exact du serveur OVH).
- **« Base non prête » sur install.php** → `schema.sql` n'a pas été importé.
- **Page blanche / erreur 500** → PHP < 8 chez OVH : passez la version PHP de
  l'hébergement à **8.x** dans l'espace client OVH.

## Référence des actions (`?action=…`)

| Action | Méthode | Accès | Rôle |
|---|---|---|---|
| `auth.login` | POST | public | Connexion (e-mail + mot de passe). |
| `auth.logout` | POST | connecté | Déconnexion. |
| `auth.me` | GET | public | Utilisateur courant (ou `null`). |
| `auth.changePassword` | POST | connecté | Change son propre mot de passe. |
| `tournaments.list` | GET | connecté | Liste des tournois. |
| `tournaments.save` | POST | admin | Crée/met à jour un tournoi. |
| `tournaments.setArchived` | POST | admin | Archive/désarchive. |
| `tournaments.setStatus` | POST | admin | Statut (draft/live/closed). |
| `tournaments.remove` | POST | admin | Supprime un tournoi. |
| `tournaments.saveStructure` | POST | admin | Enregistre gymnases/équipes/poules/matchs. |
| `tournaments.loadStructure` | GET | connecté | Recharge la structure d'un tournoi. |
| `referents.list` | GET | admin | Liste des référents. |
| `referents.create` | POST | admin | Crée un compte référent. |
| `referents.setStatus` | POST | admin | Active/suspend un référent. |
| `referents.remove` | POST | admin | Supprime un référent. |

> Les comptes **capitaines** (saisie des scores) et le **temps réel** ne sont pas
> encore branchés côté application ; la table `score_entries` est déjà prévue
> pour cette étape ultérieure.
