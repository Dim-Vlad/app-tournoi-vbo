# Tournoi VBO

Application mobile (PWA) de gestion des tournois du **Volley-Ball Ollioulais** : de la création d'un tournoi au classement final, pilotée depuis le gymnase sur téléphone.

## Structure du dépôt

```
.
├── index.html               ← l'application (à déployer, c'est la page d'accueil)
├── manifest.webmanifest     ← métadonnées PWA (nom, couleurs, icônes)
├── sw.js                    ← service worker (démarrage instantané + hors connexion)
├── assets/
│   └── vbo-logo.png         ← logo affiché dans l'app
├── icons/
│   ├── icon-192.png         ← icône 192×192 (Android)
│   ├── icon-512.png         ← icône 512×512 (Android, splash)
│   ├── icon-maskable-512.png← icône « maskable » (Android adaptatif)
│   └── apple-touch-icon.png ← icône 180×180 (iOS, écran d'accueil)
├── prototype.html           ← version de travail (prototype, données fictives)
├── api/                     ← backend PHP + MySQL pour OVH (voir api/README.md)
└── supabase/                ← ancien backend Supabase (abandonné, peut être supprimé)
```

> `prototype.html` est la version d'itération (avec données fictives) ; `index.html` en est la copie prête à déployer, avec le câblage PWA ajouté (manifest, service worker, logo pointant vers `assets/`). Quand le prototype évolue, régénérer `index.html` à partir de lui.

## Mettre en ligne (PWA installable)

Une PWA s'installe uniquement si elle est servie en **HTTPS**. Trois options simples :

### Option A — GitHub Pages
1. Pousser ce dossier sur un dépôt GitHub.
2. **Settings → Pages →** source = branche `main`, dossier `/root`.
3. L'app est publiée sur `https://<utilisateur>.github.io/<dépôt>/`.

### Option B — Netlify / Vercel
1. Importer le dépôt (ou glisser-déposer le dossier sur Netlify).
2. Pas de build : site statique. Dossier de publication = racine.
3. URL HTTPS fournie automatiquement.

Une fois en ligne, le bouton **« Installer »** de l'app déclenche l'installation native (Android/Chrome) ou affiche la marche à suivre (iOS/Safari → Partager → « Sur l'écran d'accueil »).

## Vérifier l'installabilité

Dans Chrome (ordinateur) sur l'URL déployée : **DevTools → Application → Manifest** (icônes + champs valides) et **Service Workers** (enregistré et actif). **Lighthouse → PWA** donne un diagnostic complet.

> ℹ️ Le service worker ne s'enregistre **pas** dans l'aperçu intégré de l'éditeur (restriction des webviews). C'est normal : il fonctionne dès que l'app est servie sur un vrai hébergement HTTPS (ou `http://localhost`).

## Mettre à jour l'app déployée

Le service worker met en cache la coquille de l'app. Après un changement, incrémenter la version du cache dans `sw.js` (`const CACHE = 'vbo-tournoi-v2';`) pour que les appareils récupèrent la nouvelle version au prochain lancement.

## Backend

Le backend est en **PHP + MySQL**, hébergé sur le **même domaine** que l'app (chez
OVH, à côté du site du club) : comptes admin + référents, tournois et structure
(gymnases/équipes/poules/matchs). Même origine → authentification par **cookie de
session**, sans clé d'API ni CORS. Installation et référence des actions dans
[`api/README.md`](api/README.md).

> Le dossier `supabase/` correspond à l'ancienne approche (Supabase), abandonnée au
> profit d'OVH ; il peut être supprimé.
