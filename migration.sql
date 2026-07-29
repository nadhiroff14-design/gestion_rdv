-- Migration pour ajouter la gestion des créneaux horaires
-- Exécuter ce script sur la base de données existante

USE rdv_app;

-- Créer la table responsables
CREATE TABLE IF NOT EXISTS responsables (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nom VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  actif BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_actif (actif)
);

-- Ajouter les colonnes à la table bookings
ALTER TABLE bookings 
ADD COLUMN heure_debut TIME NULL COMMENT 'Heure de début du rendez-vous (ex: 14:30)',
ADD COLUMN duree INT NULL COMMENT 'Durée en minutes (ex: 60 pour 1h)',
ADD COLUMN responsable_id INT NULL COMMENT 'ID du responsable assigné',
ADD INDEX idx_responsable (responsable_id);

-- Ajouter la contrainte de clé étrangère
ALTER TABLE bookings 
ADD CONSTRAINT fk_responsable 
FOREIGN KEY (responsable_id) REFERENCES responsables(id) ON DELETE SET NULL;

-- Insérer le responsable par défaut depuis les settings
INSERT INTO responsables (nom, email, actif)
SELECT responsable_nom, responsable_email, TRUE
FROM settings 
WHERE id = 1 
AND responsable_nom IS NOT NULL 
AND responsable_nom != ''
AND NOT EXISTS (SELECT 1 FROM responsables WHERE email = (SELECT responsable_email FROM settings WHERE id = 1));
