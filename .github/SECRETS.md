# 🔐 Configuration des Secrets GitHub - Template

## ⚠️ NE PAS COMMITTER CE FICHIER
Utilisez ce template pour configurer les secrets dans **Settings → Secrets and variables → Actions**

---

## 🔷 Secrets optionnels (pour releases & notifications)

### 📱 Mobile release (04-release.yml)
```
BACKEND_BASE_URL = https://api.watchtracker.net
TMDB_API_KEY = your_tmdb_api_key
TVDB_API_KEY = your_tvdb_api_key
```

`BACKEND_BASE_URL` doit être en **HTTPS** pour les APK Android release.

### 📦 Docker Registry (pour 04-release.yml)
```
DOCKER_USERNAME = your_docker_username
DOCKER_PASSWORD = your_docker_token
DOCKER_REGISTRY = docker.io
```

**Comment générer**:
1. Docker Hub: https://hub.docker.com/settings/security
2. Générer "New Access Token"
3. Copier le token dans `DOCKER_PASSWORD`

---

### 💬 Slack Notifications (pour 07-notifications.yml)
```
SLACK_WEBHOOK = https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

**Comment générer**:
1. Aller à: https://api.slack.com/messaging/webhooks
2. "Create New App" → "From scratch"
3. App name: "WatchTracker" → Workspace: votre workspace
4. Enable "Incoming Webhooks"
5. "Add New Webhook to Workspace"
6. Choisir channel: #ci-notifications (ou créer)
7. Copier l'URL dans le secret

---

### 📧 Email Alerts (pour 07-notifications.yml)

#### Avec Gmail:
```
MAIL_SERVER = smtp.gmail.com
MAIL_PORT = 587
MAIL_USER = your-email@gmail.com
MAIL_PASSWORD = your-app-password
ALERT_EMAIL = your-email@gmail.com
```

**Comment générer app password Gmail**:
1. https://myaccount.google.com/security
2. "App passwords" (nécessite 2FA)
3. Sélectionner "Mail" + "Windows Computer"
4. Générer & copier le mot de passe

#### Avec serveur personnalisé:
```
MAIL_SERVER = smtp.your-domain.com
MAIL_PORT = 587
MAIL_USER = notifications@your-domain.com
MAIL_PASSWORD = your-password
ALERT_EMAIL = admin@your-domain.com
```

---

## 🔒 Sécurité des Secrets

### ✅ Bonnes pratiques:
- ✅ Utiliser des app-specific tokens (pas le mot de passe principal)
- ✅ Régulièrement rotate les tokens/passwords
- ✅ Limiter les permissions au minimum nécessaire
- ✅ Monitorer l'usage des tokens
- ✅ Révoquer les tokens inutilisés

### ❌ À ne jamais faire:
- ❌ Ne pas committer les secrets
- ❌ Ne pas les mettre en dur dans les workflows
- ❌ Ne pas utiliser le même token partout
- ❌ Ne pas logger les secrets (GitHub les mask automatiquement)

---

## 🔍 Vérifier les Secrets configurés

### Via CLI (si vous avez gh CLI):
```bash
gh secret list
```

### Via Interface Web:
1. GitHub → Votre repo
2. **Settings** → **Secrets and variables** → **Actions**
3. Vous verrez la liste (les valeurs sont cachées)

---

## 🧪 Tester les Workflows localement

### Avec act (local GitHub Actions):
```bash
# Installer act: https://github.com/nektos/act
act -l                  # Lister les workflows
act push -j analyze     # Tester le job "analyze"
```

### Manuellement:
```bash
# Flutter
cd flutter_app
flutter analyze
flutter test

# Backend
cd server
pip install -r requirements.txt
pytest tests/
```

---

## 🎯 Exemple: Configuration complète

### Étape 1: Docker Hub
1. Créer un token: https://hub.docker.com/settings/security
2. GitHub Settings → Add secret:
   - Name: `DOCKER_USERNAME` | Value: `your_username`
   - Name: `DOCKER_PASSWORD` | Value: `token_generated`

### Étape 2: Slack
1. Créer webhook: https://api.slack.com/messaging/webhooks
2. GitHub Settings → Add secret:
   - Name: `SLACK_WEBHOOK` | Value: `https://hooks.slack.com/...`

### Étape 3: Tester
1. Faire un commit/push sur `main`
2. Aller à **Actions**
3. Voir la release créée
4. Vérifier notification Slack

---

## 📝 Checklist de mise en place

- [ ] Cloner les workflows `.github/workflows/`
- [ ] Créer secret `DOCKER_USERNAME` (optionnel)
- [ ] Créer secret `DOCKER_PASSWORD` (optionnel)
- [ ] Créer secret `SLACK_WEBHOOK` (optionnel)
- [ ] Faire un test commit sur feature branch
- [ ] Vérifier que **01-flutter-ci.yml** passe
- [ ] Vérifier que **02-backend-ci.yml** passe
- [ ] Merger sur main
- [ ] Vérifier que release est créée
- [ ] Vérifier notification Slack (si configurée)
- [ ] Valider que APK est disponible dans release

---

## 🆘 Troubleshooting

### "Secrets not found" error:
```
Solution: Secrets ne sont pas visibles dans les logs.
Vérifier dans Settings → Secrets qu'ils existent.
```

### Docker push échoue:
```yaml
# Vérifier le workflow:
- name: Login to Docker Hub
  uses: docker/login-action@v3
  with:
    username: ${{ secrets.DOCKER_USERNAME }}
    password: ${{ secrets.DOCKER_PASSWORD }}

# username et password sont masqués dans les logs
```

### Slack webhook invalid:
```
Solution: Copier l'URL complète https://hooks.slack.com/...
Tester avec curl:
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test"}' \
  YOUR_WEBHOOK_URL
```

---

**Dernière mise à jour**: 2026-08-18
