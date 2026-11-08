/* Service worker — Tournoi VBO
 * App shell en cache pour un démarrage instantané et un usage hors connexion.
 * Incrémenter CACHE à chaque déploiement pour forcer la mise à jour.
 */
const CACHE = 'vbo-tournoi-v8';

const APP_SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './assets/vbo-logo.png',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
  './icons/apple-touch-icon.png'
];

// Installation : pré-cache de la coquille de l'app.
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((c) => c.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

// Activation : purge des anciens caches.
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// Requêtes :
//  - navigation (ouverture de page)  → réseau d'abord, repli sur index.html en cache (hors connexion).
//  - autres GET même origine          → cache d'abord, puis réseau (et mise à jour du cache).
//  - cross-origin                     → laissé au réseau.
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // ex. polices : réseau direct

  // L'API PHP (./api/...) ne doit JAMAIS être mise en cache : toujours le réseau,
  // sinon on servirait des données périmées (tournois, session, scores…).
  if (url.pathname.includes('/api/')) return;

  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put('./index.html', copy)).catch(() => {});
          return res;
        })
        .catch(() => caches.match('./index.html').then((r) => r || caches.match('./')))
    );
    return;
  }

  event.respondWith(
    caches.match(req).then((cached) => {
      if (cached) {
        // rafraîchit en arrière-plan
        fetch(req).then((res) => {
          if (res && res.ok) caches.open(CACHE).then((c) => c.put(req, res.clone())).catch(() => {});
        }).catch(() => {});
        return cached;
      }
      return fetch(req).then((res) => {
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      });
    })
  );
});
