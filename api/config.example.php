<?php
// =====================================================================
//  Configuration de l'API Tournoi VBO  —  MODÈLE
//
//  👉 COPIE ce fichier en  config.php  (dans le même dossier /api)
//     puis remplace les 4 valeurs par celles de ta base MySQL OVH.
//
//  Où trouver ces infos : Espace client OVH → Hébergement → onglet
//  « Bases de données ». OVH affiche le serveur, le nom de la base et
//  l'utilisateur ; le mot de passe est celui que tu as défini à la
//  création de la base.
//
//  ⚠️ Ne mets JAMAIS ce fichier (ni config.php) en public en .txt :
//     laissé en .php, il est exécuté par le serveur, jamais affiché.
// =====================================================================

return [
  // --- Base de données MySQL OVH ---
  'db_host' => 'xxxxxxxx.mysql.db',   // ex. abcde123-001.privatesql.db ou xxx.mysql.db
  'db_name' => 'nom_de_ta_base',      // nom exact de la base créée sur OVH
  'db_user' => 'utilisateur',         // utilisateur MySQL OVH
  'db_pass' => 'mot_de_passe',        // mot de passe de cet utilisateur
  'db_port' => 3306,                  // 3306 par défaut (35000+ pour PrivateSQL)

  // --- Divers ---
  // Mets true une fois en ligne en HTTPS (cookie de session « secure »).
  'https'   => true,
];
