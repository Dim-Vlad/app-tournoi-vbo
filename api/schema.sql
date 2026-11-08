-- =====================================================================
--  Tournoi VBO — Schéma MySQL / MariaDB (hébergement OVH)
--  Volley-Ball Ollioulais — app de gestion de tournois de volley
--
--  Remplace le backend Supabase : tout est désormais hébergé sur OVH
--  (fichiers de l'app + API PHP + cette base MySQL), sur le même domaine.
--
--  À exécuter UNE fois dans phpMyAdmin (OVH : Hébergement → Bases de
--  données → phpMyAdmin) : onglet « SQL », coller ce fichier, « Exécuter ».
--  (La base elle-même se crée depuis l'espace client OVH ; ici on ne crée
--   que les tables À L'INTÉRIEUR de cette base.)
--
--  Toutes les clés sont des UUID (CHAR(36)) générés par PHP, pour rester
--  compatibles avec l'application (qui reconnaît ce format).
--
--  Modèle de comptes :
--    • Admin            : crée et gère tout (role = 'admin')
--    • Référent gymnase : suit tous les tournois, saisit les scores
--                         (role = 'referent', créé par l'admin)
--    • Capitaine        : AUCUN compte. Rejoint via le code du tournoi
--                         (join_code) — flux ajouté plus tard.
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
--  users : comptes de connexion (admin + référents)
--  password_hash = hachage bcrypt (jamais le mot de passe en clair).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id            CHAR(36)      NOT NULL,
  email         VARCHAR(255)  NOT NULL,
  password_hash VARCHAR(255)  NOT NULL,
  full_name     VARCHAR(255)  NOT NULL DEFAULT '',
  role          ENUM('admin','referent') NOT NULL DEFAULT 'referent',
  status        ENUM('active','suspended') NOT NULL DEFAULT 'active',
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
--  tournaments : un tournoi. config = tout le paramétrage de l'app (JSON
--  stocké en texte pour rester portable MySQL/MariaDB).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tournaments (
  id          CHAR(36)     NOT NULL,
  created_by  CHAR(36)     NULL,
  name        VARCHAR(255) NOT NULL,
  event_date  DATE         NULL,
  place       VARCHAR(255) NULL,
  status      ENUM('draft','live','closed') NOT NULL DEFAULT 'draft',
  archived    TINYINT(1)   NOT NULL DEFAULT 0,
  join_code   VARCHAR(32)  NULL,
  live_phase  VARCHAR(32)  NOT NULL DEFAULT 'brassage',
  config      LONGTEXT     NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  launched_at DATETIME     NULL,
  closed_at   DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_tournaments_join_code (join_code),
  KEY idx_tournaments_status (status, archived),
  CONSTRAINT fk_tournaments_creator FOREIGN KEY (created_by)
    REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
--  gyms : gymnases d'un tournoi
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gyms (
  id            CHAR(36)     NOT NULL,
  tournament_id CHAR(36)     NOT NULL,
  name          VARCHAR(255) NOT NULL,
  position      INT          NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY idx_gyms_tournament (tournament_id),
  CONSTRAINT fk_gyms_tournament FOREIGN KEY (tournament_id)
    REFERENCES tournaments(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
--  teams : équipes. level = poids 1..4 (jeu/dep/reg/nat).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS teams (
  id            CHAR(36)     NOT NULL,
  tournament_id CHAR(36)     NOT NULL,
  name          VARCHAR(255) NOT NULL,
  level         INT          NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_teams_tournament (tournament_id),
  CONSTRAINT fk_teams_tournament FOREIGN KEY (tournament_id)
    REFERENCES tournaments(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
--  pools : poules (par phase + gymnase/terrain)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pools (
  id            CHAR(36)    NOT NULL,
  tournament_id CHAR(36)    NOT NULL,
  letter        VARCHAR(8)  NOT NULL,
  phase         VARCHAR(32) NOT NULL DEFAULT 'brassage',
  gym_id        CHAR(36)    NULL,
  court         INT         NULL,
  PRIMARY KEY (id),
  KEY idx_pools_tournament (tournament_id),
  CONSTRAINT fk_pools_tournament FOREIGN KEY (tournament_id)
    REFERENCES tournaments(id) ON DELETE CASCADE,
  CONSTRAINT fk_pools_gym FOREIGN KEY (gym_id)
    REFERENCES gyms(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
--  pool_teams : appartenance équipe ↔ poule (+ seed de départ)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pool_teams (
  id       CHAR(36) NOT NULL,
  pool_id  CHAR(36) NOT NULL,
  team_id  CHAR(36) NOT NULL,
  seed     INT      NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pool_team (pool_id, team_id),
  CONSTRAINT fk_pt_pool FOREIGN KEY (pool_id)
    REFERENCES pools(id) ON DELETE CASCADE,
  CONSTRAINT fk_pt_team FOREIGN KEY (team_id)
    REFERENCES teams(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
--  matches : horaire, terrain, équipes, arbitre, statut, score.
--  sets = détail JSON (texte) ex. [{"a":25,"b":18},{"a":23,"b":25}]
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS matches (
  id             CHAR(36)    NOT NULL,
  tournament_id  CHAR(36)    NOT NULL,
  pool_id        CHAR(36)    NULL,
  phase          VARCHAR(32) NOT NULL DEFAULT 'brassage',
  round          INT         NULL,
  scheduled_time VARCHAR(32) NULL,
  gym_id         CHAR(36)    NULL,
  court          INT         NULL,
  team_a         CHAR(36)    NULL,
  team_b         CHAR(36)    NULL,
  referee_team   CHAR(36)    NULL,
  status         ENUM('todo','pending','live','valid') NOT NULL DEFAULT 'todo',
  score_a        INT         NULL,
  score_b        INT         NULL,
  sets           LONGTEXT    NULL,
  validated_at   DATETIME    NULL,
  created_at     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_matches_tournament (tournament_id),
  KEY idx_matches_status (tournament_id, status),
  CONSTRAINT fk_matches_tournament FOREIGN KEY (tournament_id)
    REFERENCES tournaments(id) ON DELETE CASCADE,
  CONSTRAINT fk_matches_pool FOREIGN KEY (pool_id)
    REFERENCES pools(id) ON DELETE SET NULL,
  CONSTRAINT fk_matches_gym FOREIGN KEY (gym_id)
    REFERENCES gyms(id) ON DELETE SET NULL,
  CONSTRAINT fk_matches_team_a FOREIGN KEY (team_a)
    REFERENCES teams(id) ON DELETE SET NULL,
  CONSTRAINT fk_matches_team_b FOREIGN KEY (team_b)
    REFERENCES teams(id) ON DELETE SET NULL,
  CONSTRAINT fk_matches_ref FOREIGN KEY (referee_team)
    REFERENCES teams(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
--  score_entries : double saisie des capitaines (validation croisée).
--  Utilisé par le flux capitaines (ajouté plus tard).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS score_entries (
  id         CHAR(36) NOT NULL,
  match_id   CHAR(36) NOT NULL,
  team_id    CHAR(36) NOT NULL,
  score_a    INT      NOT NULL,
  score_b    INT      NOT NULL,
  sets       LONGTEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_entry (match_id, team_id),
  CONSTRAINT fk_se_match FOREIGN KEY (match_id)
    REFERENCES matches(id) ON DELETE CASCADE,
  CONSTRAINT fk_se_team FOREIGN KEY (team_id)
    REFERENCES teams(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

-- =====================================================================
--  Fin du schéma. Créez ensuite le compte admin via api/install.php.
-- =====================================================================
