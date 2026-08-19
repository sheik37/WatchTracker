# 🚀 GitHub Actions - Guide d'utilisation

## 📋 Workflows configurés

### 1. **📱 CI Flutter** (`01-flutter-ci.yml`)
- **Trigger**: Push/PR sur `flutter_app/`
- **Actions**:
  - 🔍 Analyze & Lint (flutter analyze, dart format)
  - 🧪 Tests unitaires & widgets (coverage)

---

### 2. **🔌 CI Backend** (`02-backend-ci.yml`)
- **Trigger**: Push/PR sur `server/`
- **Actions**:
  - 🔍 Lint (black, isort, flake8)
  - 🧪 Tests avec coverage (pytest)
  - 🔐 Security scan (bandit, safety)
  - 🐳 Build Docker (caching optimisé)

**Services**:
- PostgreSQL 15 (pour tests)

---

### 3. **✅ Format & Commits** (`03-format-validation.yml`)
- **Trigger**: Chaque push/PR
- **Validations**:
  - ✅ Line endings LF sur `*.sh`
  - ✅ Taille fichiers (< 50MB)
  - ✅ Pas de trailing whitespace
  - ✅ Messages commits (fr: feat, fix, docs, chore, etc.)

---

### 4. **🚀 Auto-Release** (`04-release.yml`)
- **Trigger**: Push sur tag `v*` ou lancement manuel
- **Actions**:
  - 📦 Crée une release GitHub
  - 🏷️ Utilise le tag comme source de vérité de version (`v2.0.0` → app `2.0.0`)
  - 🏗️ Build APK + upload à la release
  - 🍎 Build iOS sans signature + upload en artefact/release
  - 🐳 Build Docker image

**Secrets requis** (optionnel pour Docker):
```
DOCKER_USERNAME
DOCKER_PASSWORD
DOCKER_REGISTRY (default: docker.io)
```

---

### 5. **🔄 Dependency Updates** (`05-dependencies.yml`)
- **Trigger**: Hebdomadaire (lundi 3:00 AM)
- **Actions**:
  - 🚀 Check Flutter pub updates → créé PR
  - 🐍 Check Python pip updates → créé PR
  - 🔐 Security audit (pip-audit, safety, bandit)

**PRs créées**:
- `chore/flutter-deps-update`
- `chore/python-deps-update`

---

### 6. **⚡ Performance & Benchmarks** (`06-performance.yml`)
- **Trigger**: Push sur main/develop
- **Actions**:
  - 📊 Flutter metrics (dart_code_metrics)
  - 🚀 API benchmarks (pytest-benchmark)
  - 🗄️ Database optimization analysis
  - 📈 Report sur PR

**Rapports générés**:
- `api-benchmarks/benchmark.json`
- Commentaires sur les PRs

---

### 7. **🔔 Notifications** (`07-notifications.yml`)
- **Trigger**: Après les autres workflows
- **Actions**:
  - 📧 Email alerts (optionnel)
  - 💬 Slack notifications (optionnel)
  - 🐛 Create issue automatique si failure

**Secrets requis** (optionnel):
```
SLACK_WEBHOOK=https://hooks.slack.com/...
ALERT_EMAIL=your-email@example.com
MAIL_SERVER=smtp.example.com
MAIL_PORT=587
MAIL_USER=...
MAIL_PASSWORD=...
```

---

## 🔐 Configuration des Secrets

### Pour le Docker registry:
1. Aller à: **Settings → Secrets and variables → Actions**
2. Ajouter:
   ```
   DOCKER_USERNAME = votre_username_docker
   DOCKER_PASSWORD = votre_token_docker
   DOCKER_REGISTRY = docker.io (ou votre registry privé)
   ```

### Pour les notifications Slack:
1. Créer webhook: https://api.slack.com/messaging/webhooks
2. Ajouter secret: `SLACK_WEBHOOK = https://hooks.slack.com/...`

### Pour les emails:
1. Configurer SMTP:
   ```
   MAIL_SERVER = smtp.gmail.com (ou votre serveur)
   MAIL_PORT = 587
   MAIL_USER = your-email@gmail.com
   MAIL_PASSWORD = your-app-password
   ALERT_EMAIL = notifications@example.com
   ```

---

## 📊 Statuts & Badges

Ajouter à votre `README.md`:

```markdown
## Statuts de Build

[![Flutter CI](https://github.com/sheik37/WatchTracker/actions/workflows/01-flutter-ci.yml/badge.svg)](https://github.com/sheik37/WatchTracker/actions/workflows/01-flutter-ci.yml)
[![Backend CI](https://github.com/sheik37/WatchTracker/actions/workflows/02-backend-ci.yml/badge.svg)](https://github.com/sheik37/WatchTracker/actions/workflows/02-backend-ci.yml)
[![Format & Commits](https://github.com/sheik37/WatchTracker/actions/workflows/03-format-validation.yml/badge.svg)](https://github.com/sheik37/WatchTracker/actions/workflows/03-format-validation.yml)
[![Performance](https://github.com/sheik37/WatchTracker/actions/workflows/06-performance.yml/badge.svg)](https://github.com/sheik37/WatchTracker/actions/workflows/06-performance.yml)
```

---

## 🎯 Cas d'usage courants

### ✅ Pour chaque PR:
1. **Automatiquement**:
   - ✅ Flutter analyze & format
   - ✅ Backend tests & lint
   - ✅ Format validation
   - ✅ Metrics reporting

2. **Manuellement** (optionnel):
   - Déclencher sur Actions > choisir workflow > "Run workflow"

### ✅ Avant de merger sur main:
1. Tous les CI doivent être ✅
2. Pas de format issues
3. Pas de security warnings critiques

### ✅ Release sur main:
1. Créé automatiquement une release GitHub
2. Construit APK + iOS
3. Push Docker image (si secrets configurés)
4. Génère release notes depuis commits

### ✅ Maintenance:
1. **Lundi**: Dependency checks + PRs créées
2. **Chaque push main**: Performance benchmarks
3. **Failures**: Slack notifications + GitHub issues

---

## 🔧 Débogage & Troubleshooting

### Workflow ne s'exécute pas:
- Vérifier les `on:` conditions dans le fichier YAML
- Vérifier les `paths:` et `paths-ignore:`
- Aller à **Actions** → chercher le workflow → "Enable workflow"

### Tests échouent localement mais pas sur CI:
```bash
# Tester localement d'abord:
cd flutter_app && flutter analyze
cd flutter_app && flutter test

cd server && pytest tests/
```

### Secrets non trouvés:
1. Vérifier dans **Settings → Secrets**
2. S'assurer que le workflow peut accéder: `${{ secrets.VOTRE_SECRET }}`
3. Note: Secrets ne sont visibles que dans logs si explicitement echo-ed

### Docker build échoue:
1. Vérifier `server/Dockerfile` existe
2. Vérifier authentification Docker Hub
3. Tester localement: `docker build -t watchtracker-api:test ./server`

---

## 📈 Métriques suivies

| Métrique | Collectée | Stockage |
|----------|-----------|----------|
| Code Coverage (Flutter) | ✅ | Codecov |
| Code Coverage (Python) | ✅ | Codecov |
| Lint Results | ✅ | GitHub Actions logs |
| API Benchmarks | ✅ | Artifacts (30j) |
| Build Size (APK) | ✅ | Logs |
| Dependency versions | ✅ | PRs créées |

---

## 🎨 Personnalisation

### Changer les horaires:
```yaml
schedule:
  - cron: '0 3 * * 1'  # Lundi 3:00 AM UTC
  # Syntax: minute hour day month day-of-week
  # Exemples:
  # '0 0 * * *'   = Quotidien à minuit
  # '0 */6 * * *' = Toutes les 6h
  # '0 10 * * 1'  = Lundi 10:00 AM
```

### Ajouter des branches:
```yaml
on:
  push:
    branches: [main, develop, staging, feature/**]
```

### Limiter les chemins:
```yaml
paths:
  - 'flutter_app/**'
  - 'common/**'       # Dépendance Flutter
  - '.github/workflows/01-*.yml'
```

---

## 📞 Support & Questions

Pour ajouter/modifier un workflow:
1. Éditer le fichier `.github/workflows/XX-*.yml`
2. Committer et pousser (auto-test sur PR)
3. Valider sur GitHub Actions dashboard
4. Merger quand OK

**Référence officielle**: https://docs.github.com/en/actions
