<?php
// =====================================================================
//  Bootstrap commun de l'API Tournoi VBO
//  - charge la config, ouvre la connexion PDO ($pdo)
//  - démarre la session (cookie), expose des helpers
//  Inclus par index.php et install.php.
// =====================================================================

declare(strict_types=1);

mb_internal_encoding('UTF-8');
error_reporting(E_ALL);
ini_set('display_errors', '0'); // pas de fuite d'erreurs PHP dans les réponses

// --- Config -----------------------------------------------------------
$configFile = __DIR__ . '/config.php';
if (!is_file($configFile)) {
  http_response_code(500);
  header('Content-Type: application/json; charset=utf-8');
  echo json_encode(['error' => "Configuration absente : copiez api/config.example.php en api/config.php."]);
  exit;
}
$CONFIG = require $configFile;

// --- Session (cookie httpOnly, SameSite=Lax) --------------------------
$secure = !empty($CONFIG['https']);
session_set_cookie_params([
  'lifetime' => 0,
  'path'     => '/',
  'httponly' => true,
  'secure'   => $secure,
  'samesite' => 'Lax',
]);
session_name('vbo_sess');
session_start();

// --- Connexion PDO ----------------------------------------------------
function db(): PDO {
  static $pdo = null;
  if ($pdo instanceof PDO) return $pdo;
  global $CONFIG;
  $dsn = sprintf(
    'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
    $CONFIG['db_host'], (int)($CONFIG['db_port'] ?? 3306), $CONFIG['db_name']
  );
  try {
    $pdo = new PDO($dsn, $CONFIG['db_user'], $CONFIG['db_pass'], [
      PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
      PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
      PDO::ATTR_EMULATE_PREPARES   => false,
    ]);
  } catch (Throwable $e) {
    fail(500, "Connexion à la base impossible (vérifiez api/config.php).");
  }
  return $pdo;
}

// --- Helpers de réponse ----------------------------------------------
function send_json($data, int $status = 200): void {
  http_response_code($status);
  header('Content-Type: application/json; charset=utf-8');
  header('X-Content-Type-Options: nosniff');
  echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
  exit;
}
function ok($data = null): void { send_json($data === null ? ['ok' => true] : $data, 200); }
function fail(int $status, string $message): void { send_json(['error' => $message], $status); }

// --- Corps JSON de la requête ----------------------------------------
function body(): array {
  static $b = null;
  if ($b !== null) return $b;
  $raw = file_get_contents('php://input') ?: '';
  $d = json_decode($raw, true);
  $b = is_array($d) ? $d : [];
  return $b;
}
function field($key, $default = null) {
  $b = body();
  return array_key_exists($key, $b) ? $b[$key] : $default;
}

// --- UUID v4 (compatible avec le format attendu par l'app) -----------
function uuid4(): string {
  $d = random_bytes(16);
  $d[6] = chr((ord($d[6]) & 0x0f) | 0x40);
  $d[8] = chr((ord($d[8]) & 0x3f) | 0x80);
  return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($d), 4));
}
function is_uuid($v): bool {
  return is_string($v) && (bool)preg_match(
    '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $v);
}

// Normalise une date/heure (ISO 8601 de JS, « 2026-11-08T12:00:00.000Z »…)
// vers le format DATETIME MySQL « Y-m-d H:i:s ». null si vide/illisible.
function mysql_dt($v): ?string {
  if ($v === null || $v === '') return null;
  $t = strtotime((string)$v);
  return $t ? date('Y-m-d H:i:s', $t) : null;
}

// --- Auth / session courante -----------------------------------------
function current_user(): ?array {
  if (empty($_SESSION['uid'])) return null;
  return [
    'id'    => $_SESSION['uid'],
    'name'  => $_SESSION['uname'] ?? '',
    'email' => $_SESSION['uemail'] ?? '',
    'role'  => $_SESSION['urole'] ?? 'referent',
  ];
}
function set_session_user(array $u): void {
  session_regenerate_id(true);
  $_SESSION['uid']    = $u['id'];
  $_SESSION['uname']  = $u['full_name'] ?? ($u['name'] ?? '');
  $_SESSION['uemail'] = $u['email'] ?? '';
  $_SESSION['urole']  = $u['role'] ?? 'referent';
}
function clear_session_user(): void {
  $_SESSION = [];
  if (ini_get('session.use_cookies')) {
    $p = session_get_cookie_params();
    setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'] ?? '', $p['secure'], $p['httponly']);
  }
  session_destroy();
}
function require_login(): array {
  $u = current_user();
  if (!$u) fail(401, "Non authentifié.");
  return $u;
}
function require_admin(): array {
  $u = require_login();
  if (($u['role'] ?? '') !== 'admin') fail(403, "Action réservée à l'administrateur.");
  return $u;
}
