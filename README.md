# Application de prise de rendez-vous

Application complète : calendrier public de réservation + espace administrateur protégé par code,
notifications email automatiques (Nodemailer), base de données MySQL, à déployer derrière Apache.

## Fonctionnalités
- Calendrier responsive (mobile / tablette / desktop)
- Blocage de journées fixes de la semaine (ex: dimanche)
- Blocage d'une **période** précise (date début → date fin) ou d'une **journée unique**, avec motif
- **Règles spéciales par date ou période** : sur une date ou une période précise, définir un nombre
  max de rendez-vous différent du réglage global, et/ou un **responsable dédié** (nom + email) qui
  recevra les notifications pour ces jours-là. Si rien n'est défini, le réglage global s'applique.
- Accès admin protégé par **code secret** (hashé en bcrypt, jamais stocké en clair), avec bouton pour
  quitter l'écran de connexion sans se connecter
- Boîtes de confirmation avant toute suppression (rendez-vous, période bloquée, règle spéciale) et
  avant la déconnexion, plus des notifications de succès à la connexion / déconnexion
- Envoi automatique d'email au responsable à chaque demande + accusé de réception au client
- L'admin peut **accepter** ou **refuser** une demande → email automatique envoyé au client
- Bouton "Tester l'envoi d'email" dans l'espace admin pour vérifier la configuration SMTP en un clic
- Filtrage des rendez-vous par jour précis, par période, par statut, avec un bouton "Aujourd'hui"
- Stockage MySQL (aucune donnée en localStorage côté client, tout passe par l'API)

## 1. Base de données MySQL

```bash
mysql -u root -p < backend/db/schema.sql
# créez un utilisateur dédié (recommandé) :
mysql -u root -p -e "CREATE USER 'rdv_user'@'localhost' IDENTIFIED BY 'un_mot_de_passe_fort';
GRANT ALL PRIVILEGES ON rdv_app.* TO 'rdv_user'@'localhost'; FLUSH PRIVILEGES;"
```

Si votre base existe déjà (mise à jour d'une installation précédente), `schema.sql` peut être rejoué
sans risque : toutes les tables utilisent `CREATE TABLE IF NOT EXISTS`, y compris la nouvelle table
`date_overrides` qui sera simplement ajoutée sans toucher aux données existantes.

## 2. Backend (API Node/Express)

```bash
cd backend
cp .env.example .env
# éditez .env : identifiants MySQL, SMTP, ADMIN_CODE (code admin initial), JWT_SECRET
npm install
npm start        # ou: npm run dev pendant le développement
```

Au tout premier démarrage, si `admin_code_hash` est vide en base, le serveur hache automatiquement
la valeur de `ADMIN_CODE` et l'enregistre. C'est ce code que vous utiliserez pour accéder à
l'espace Administration. Pour le changer ensuite, appelez (une fois connecté) :
`POST /api/admin/change-code` avec `{ "newCode": "..." }`.

### SMTP
Renseignez un compte SMTP réel dans `.env` (ex: un compte dédié, ou un service comme celui de votre
hébergeur/registrar). Sans SMTP valide, les emails échoueront **silencieusement côté client/serveur**
(l'erreur est juste loguée côté serveur avec `console.error`, ça ne bloque jamais une réservation).

**Erreur `Invalid login: 535-5.7.8 Username and Password not accepted` (Gmail) :**
C'est presque toujours l'une de ces deux causes, dans cet ordre de fréquence :
1. **Le mot de passe d'application contient encore des espaces.** Google l'affiche en 4 groupes de
   4 caractères (ex. `abcd efgh ijkl mnop`) pour la lisibilité, mais si vous le recopiez tel quel
   (avec les espaces, éventuellement entre guillemets) dans `SMTP_PASSWORD`, Gmail le refuse. Le
   serveur nettoie maintenant automatiquement les guillemets et les espaces de `SMTP_USER` /
   `SMTP_PASSWORD` avant de s'en servir (voir `cleanEnv()` dans `server.js`), donc ce cas précis est
   corrigé même si vous ne changez rien au `.env` — mais il est plus propre de le corriger directement :
   `SMTP_PASSWORD=abcdefghijklmnop` (sans espaces, sans guillemets).
2. **Le mot de passe d'application n'est plus valide** (révoqué, mal copié, ou la validation en 2
   étapes n'est pas activée sur le compte Gmail — les mots de passe d'application n'existent que si
   la 2FA est active). Retournez sur https://myaccount.google.com/apppasswords, supprimez l'ancien et
   regénérez-en un nouveau spécifiquement pour "Mail", puis recollez-le dans `.env`.

**Pour vérifier que c'est résolu, dans cet ordre :**
1. **Au redémarrage du serveur**, un message `SMTP OK : connexion...` ou `SMTP INDISPONIBLE : ...`
   s'affiche automatiquement dans les logs (`npm start` / `journalctl -u rdv-api -f` en systemd).
2. Utilisez le bouton **"Tester l'envoi d'email"** dans Administration → Responsable & capacité : il
   envoie un email réel et affiche l'erreur précise si ça échoue encore, sans jamais faire planter
   l'API (la réponse reste HTTP 200 même en cas d'échec, pour éviter les faux "502 Bad Gateway" dans
   la console du navigateur).
3. **L'email du responsable doit être renseigné** dans Administration → Responsable & capacité. S'il
   est vide, aucun email de nouvelle demande n'est envoyé — c'est la cause la plus fréquente d'un
   "responsable qui ne reçoit rien" une fois le SMTP réparé.
4. Vérifiez que `SMTP_PORT=465` va avec `SMTP_SECURE=true`, et `SMTP_PORT=587` avec `SMTP_SECURE=false`
   (mélanger les deux est une autre source classique d'échec de connexion).

## 3. Frontend

`frontend/index.html` est un fichier statique, sans build. Servez-le simplement avec Apache :

```apache
# /etc/apache2/sites-available/rdv.conf
<VirtualHost *:80>
    ServerName rdv.votre-domaine.tld
    DocumentRoot /var/www/rdv-app/frontend

    <Directory /var/www/rdv-app/frontend>
        AllowOverride All
        Require all granted
    </Directory>

    # Reverse proxy vers l'API Node (doit tourner sur 127.0.0.1:4000)
    ProxyPreserveHost On
    ProxyPass /api http://127.0.0.1:4000/api
    ProxyPassReverse /api http://127.0.0.1:4000/api
</VirtualHost>
```

Activez les modules nécessaires puis rechargez Apache :
```bash
sudo a2enmod proxy proxy_http
sudo a2ensite rdv.conf
sudo systemctl reload apache2
```

Pensez au HTTPS (ex: `certbot --apache`) pour protéger le code admin en transit.

## 4. Garder l'API en vie (systemd)

```ini
# /etc/systemd/system/rdv-api.service
[Unit]
Description=API prise de rendez-vous
After=network.target mysql.service

[Service]
WorkingDirectory=/var/www/rdv-app/backend
ExecStart=/usr/bin/node server.js
Restart=always
EnvironmentFile=/var/www/rdv-app/backend/.env
User=www-data

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now rdv-api
```

## Sécurité
- Le code admin n'est jamais stocké en clair (bcrypt).
- Les routes `/api/admin/*` exigent un token JWT valide (12h), obtenu via `/api/admin/login`.
- Limitation de débit (`express-rate-limit`) sur la connexion admin et sur la création de rendez-vous
  pour limiter les abus / brute-force.
- Pensez à mettre `FRONTEND_ORIGIN` dans `.env` à l'URL exacte de votre site en production (CORS).

## Pistes d'amélioration possibles
- Rappel automatique par email 24h avant un rendez-vous accepté (via une tâche cron qui interroge `/api/admin/bookings`)
- Export CSV des rendez-vous depuis l'espace admin
- Plusieurs comptes admin nominatifs (au lieu d'un code partagé) si plusieurs personnes gèrent l'agenda
- SMS de rappel (Twilio ou autre) en plus de l'email