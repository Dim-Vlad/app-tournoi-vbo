<?php
// =====================================================================
//  Installation — création du PREMIER compte administrateur.
//
//  Page à usage unique : elle ne fonctionne QUE tant qu'aucun compte
//  n'existe dans la table « users ». Dès qu'un admin est créé, elle se
//  désactive d'elle-même (plus personne ne peut l'utiliser).
//
//  Marche à suivre une seule fois, en ligne :
//    1. Créer la base MySQL sur OVH, importer api/schema.sql dans phpMyAdmin.
//    2. Copier api/config.example.php en api/config.php et renseigner la base.
//    3. Ouvrir  https://votre-site/api/install.php  dans le navigateur,
//       saisir nom + e-mail + mot de passe de l'admin, valider.
//    4. SUPPRIMER ce fichier (install.php) du serveur par sécurité.
// =====================================================================

require __DIR__ . '/_bootstrap.php';

// --- La base contient-elle déjà un compte ? --------------------------
$already = false;
try {
  $already = (int)db()->query("SELECT COUNT(*) AS n FROM users")->fetch()['n'] > 0;
} catch (Throwable $e) {
  // Table absente ou base injoignable : message clair plus bas.
  http_response_code(500);
  header('Content-Type: text/html; charset=utf-8');
  echo page("Base non prête",
    "<p class='err'>Impossible de lire la table <code>users</code>.</p>
     <p>Vérifiez que vous avez bien importé <code>api/schema.sql</code> dans phpMyAdmin
     et que <code>api/config.php</code> pointe la bonne base.</p>");
  exit;
}

if ($already) {
  http_response_code(403);
  header('Content-Type: text/html; charset=utf-8');
  echo page("Installation déjà faite",
    "<p class='ok'>Un compte administrateur existe déjà.</p>
     <p>Cette page est désormais désactivée. Vous pouvez (et devriez)
     <strong>supprimer le fichier <code>install.php</code></strong> du serveur.</p>");
  exit;
}

// --- Traitement du formulaire ----------------------------------------
$error = '';
$done  = false;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
  $name  = trim((string)($_POST['name'] ?? ''));
  $email = strtolower(trim((string)($_POST['email'] ?? '')));
  $pass  = (string)($_POST['password'] ?? '');
  if ($name === '') {
    $error = "Le nom est requis.";
  } elseif (!preg_match('/^[^\s@]+@[^\s@]+\.[^\s@]+$/', $email)) {
    $error = "Adresse e-mail invalide.";
  } elseif (strlen($pass) < 8) {
    $error = "Le mot de passe doit faire au moins 8 caractères.";
  } else {
    try {
      db()->prepare(
        "INSERT INTO users (id, email, password_hash, full_name, role, status)
         VALUES (?,?,?,?, 'admin', 'active')"
      )->execute([uuid4(), $email, password_hash($pass, PASSWORD_DEFAULT), $name]);
      $done = true;
    } catch (Throwable $e) {
      $error = "Création impossible (l'e-mail est peut-être déjà utilisé).";
    }
  }
}

header('Content-Type: text/html; charset=utf-8');

if ($done) {
  echo page("Compte admin créé",
    "<p class='ok'>✅ Compte administrateur créé.</p>
     <p>Vous pouvez maintenant vous connecter dans l'application avec cet e-mail
     et ce mot de passe.</p>
     <p class='warn'>⚠️ Dernière étape : <strong>supprimez le fichier
     <code>install.php</code></strong> du serveur pour empêcher toute réutilisation.</p>");
  exit;
}

$e = fn($v) => htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
echo page("Installation — compte admin",
  ($error ? "<p class='err'>" . $e($error) . "</p>" : "") .
  "<form method='post' autocomplete='off'>
     <label>Nom affiché
       <input name='name' value='" . $e($_POST['name'] ?? '') . "' required>
     </label>
     <label>E-mail
       <input name='email' type='email' value='" . $e($_POST['email'] ?? '') . "' required>
     </label>
     <label>Mot de passe (8 caractères min.)
       <input name='password' type='password' minlength='8' required>
     </label>
     <button type='submit'>Créer le compte administrateur</button>
   </form>
   <p class='hint'>Cette page ne fonctionne qu'une seule fois : elle se bloque
   dès qu'un compte existe.</p>");

// --- Gabarit HTML minimal --------------------------------------------
function page(string $title, string $body): string {
  $t = htmlspecialchars($title, ENT_QUOTES, 'UTF-8');
  return "<!doctype html><html lang='fr'><head><meta charset='utf-8'>
  <meta name='viewport' content='width=device-width,initial-scale=1'>
  <title>$t — Tournoi VBO</title>
  <style>
    :root{color-scheme:light dark}
    *{box-sizing:border-box}
    body{font:16px/1.5 system-ui,sans-serif;max-width:420px;margin:40px auto;padding:0 20px}
    h1{font-size:1.3rem}
    form{display:flex;flex-direction:column;gap:14px;margin-top:20px}
    label{display:flex;flex-direction:column;gap:6px;font-weight:600;font-size:.95rem}
    input{padding:10px 12px;font-size:1rem;border:1px solid #999;border-radius:8px;font-weight:400}
    button{padding:12px;font-size:1rem;font-weight:600;border:0;border-radius:8px;
           background:#1f6feb;color:#fff;cursor:pointer}
    .err{color:#b42318;font-weight:600}
    .ok{color:#067647;font-weight:600}
    .warn{color:#b54708}
    .hint{color:#667085;font-size:.85rem;margin-top:18px}
    code{background:rgba(127,127,127,.18);padding:1px 5px;border-radius:4px}
  </style></head><body>
  <h1>$t</h1>
  $body
  </body></html>";
}
