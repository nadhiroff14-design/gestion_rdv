-- Schéma de la base de données pour l'application de prise de rendez-vous
CREATE DATABASE IF NOT EXISTS rdv_app CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE rdv_app;

-- Réglages généraux (une seule ligne, id=1)
CREATE TABLE IF NOT EXISTS settings (
  id INT PRIMARY KEY DEFAULT 1,
  responsable_nom VARCHAR(255) DEFAULT '',
  responsable_email VARCHAR(255) DEFAULT '',
  max_par_jour INT NOT NULL DEFAULT 3,
  jours_fermes VARCHAR(50) NOT NULL DEFAULT '6',   -- ex: "5,6" (0=Lundi ... 6=Dimanche)
  admin_code_hash VARCHAR(255) NOT NULL,           -- bcrypt du code admin
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Responsables (pour gérer plusieurs responsables)
CREATE TABLE IF NOT EXISTS responsables (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nom VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  actif BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_actif (actif)
);

-- Périodes / journées bloquées (congés, indisponibilités, jours fériés...)
CREATE TABLE IF NOT EXISTS blocked_dates (
  id INT AUTO_INCREMENT PRIMARY KEY,
  date_debut DATE NOT NULL,
  date_fin DATE NOT NULL,
  motif VARCHAR(255) DEFAULT '',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_periode (date_debut, date_fin)
);

-- Surcharges par date ou par période : permet de définir, pour une journée précise
-- ou une période (date_debut -> date_fin), un nombre max de rendez-vous différent
-- du réglage global, et/ou un responsable différent (nom + email) qui recevra les
-- notifications pour ces dates-là. Tous les champs de surcharge sont optionnels :
-- laisser vide = on garde le réglage global (settings.max_par_jour / responsable_*).
CREATE TABLE IF NOT EXISTS date_overrides (
  id INT AUTO_INCREMENT PRIMARY KEY,
  date_debut DATE NOT NULL,
  date_fin DATE NOT NULL,
  max_par_jour INT NULL,                 -- NULL = utilise le réglage global
  responsable_nom VARCHAR(255) NULL,     -- NULL = utilise le responsable global
  responsable_email VARCHAR(255) NULL,   -- NULL = utilise le responsable global
  motif VARCHAR(255) DEFAULT '',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_periode (date_debut, date_fin)
);

-- Demandes de rendez-vous
CREATE TABLE IF NOT EXISTS bookings (
  id INT AUTO_INCREMENT PRIMARY KEY,
  date DATE NOT NULL,
  nom VARCHAR(255) NOT NULL,
  prenom VARCHAR(255) NOT NULL,
  tel VARCHAR(50) NOT NULL,
  email VARCHAR(255) NOT NULL,
  status ENUM('pending','accepted','rejected') NOT NULL DEFAULT 'pending',
  heure_debut TIME NULL,                 -- Heure de début du rendez-vous (ex: '14:30')
  duree INT NULL,                        -- Durée en minutes (ex: 60 pour 1h)
  responsable_id INT NULL,               -- ID du responsable assigné
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_date (date),
  INDEX idx_status (status),
  INDEX idx_responsable (responsable_id),
  FOREIGN KEY (responsable_id) REFERENCES responsables(id) ON DELETE SET NULL
);

-- Ligne de réglages par défaut (sans code admin : il est généré automatiquement
-- au premier démarrage du serveur à partir de la variable d'environnement ADMIN_CODE,
-- voir backend/server.js et README.md)
INSERT INTO settings (id, max_par_jour, jours_fermes, admin_code_hash)
VALUES (1, 3, '6', '')
ON DUPLICATE KEY UPDATE id = id;