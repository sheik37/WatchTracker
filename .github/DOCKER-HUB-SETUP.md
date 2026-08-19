# 🐳 Docker Hub - Guide de configuration

## 📋 Résumé

Vous allez :
1. Créer un compte **Docker Hub** gratuit
2. Générer un **Access Token**
3. Configurer les **Secrets GitHub**
4. Tester que tout fonctionne ✅

**Temps estimé**: ~10 minutes

---

## 🎯 Étape 1: Créer un compte Docker Hub

### 1.1 - Aller à l'inscription
Ouvrez: https://app.docker.com/signup

### 1.2 - Remplir le formulaire
```
Email:              your-email@example.com
Username:           sheik37             ← Votre username Docker
Password:           YourSecurePassword! ← Fort!
Confirm Password:   YourSecurePassword!
✓ I agree to the Docker Terms of Service
✓ I want to receive emails about Docker (optionnel)
```

### 1.3 - Créer le compte
Cliquez: **Sign Up**

### 1.4 - Confirmer l'email
1. Allez vérifier votre email
2. Cliquez le lien **Verify email**
3. Vous êtes redirigé vers Docker Hub ✅

---

## 🔑 Étape 2: Générer un Access Token

### 2.1 - Aller aux paramètres
1. Connectez-vous à: https://app.docker.com/login
2. Cliquez votre **Profil** (coin haut-droit)
3. Allez à **Account settings**

### 2.2 - Accéder aux tokens
1. Dans la sidebar: **Personal access tokens**
   Ou directement: https://app.docker.com/settings/personal-access-tokens

### 2.3 - Créer le token
1. Cliquez **Generate new token**
2. Remplissez:

```
Token name:
  watchtracker-github-actions

Access permissions:
  ✓ Read & Write

Description:
  Utilisé par GitHub Actions pour pusher les images API
```

3. Cliquez **Generate**

### 2.4 - COPIER LE TOKEN ⚠️

Une modal s'affiche avec votre token:
```
dckr_pat_XXXXXXXXXXXXXXXXXX
```

✅ **COPIER LE TOKEN COMPLET** (ne sera pas remonté après!)

---

## 🔐 Étape 3: Configurer les Secrets GitHub

### 3.1 - Accéder aux secrets
1. Allez à votre repo: https://github.com/sheik37/WatchTracker
2. **Settings** → **Secrets and variables** → **Actions**

### 3.2 - Ajouter le secret DOCKER_USERNAME

Cliquez: **New repository secret**

```
Name:  DOCKER_USERNAME
Value: sheik37           ← Votre username Docker
```

Cliquez: **Add secret**

### 3.3 - Ajouter le secret DOCKER_PASSWORD

Cliquez: **New repository secret**

```
Name:  DOCKER_PASSWORD
Value: dckr_pat_XXXXXXXXXXXXXXXXXX  ← Le token généré
```

Cliquez: **Add secret**

### 3.4 - Vérifier (optionnel)

Retournez à **Secrets**:
```
✓ DOCKER_USERNAME    [Updated less than a minute ago]
✓ DOCKER_PASSWORD    [Updated less than a minute ago]
```

---

## ✅ Étape 4: Tester la configuration

### 4.1 - Via ligne de commande (optionnel)

Testez localement que votre Docker est bien configuré:

```bash
# Login à Docker Hub
docker login --username sheik37

# Entrez votre password (le token)
dckr_pat_XXXXXXXXXXXXXXXXXX

# Test: builder et pusher une petite image
cd WatchTracker\ Flutter/server
docker build -t sheik37/watchtracker-api:test .
docker push sheik37/watchtracker-api:test
```

### 4.2 - Via GitHub Actions

Testez que les secrets sont bien trouvés:

1. Allez à **Actions**
2. Ouvrez un workflow récent (ex: 04-release)
3. Cliquez sur **build_release_docker**
4. Cherchez le step: **🔑 Login to Docker Hub**
5. Les logs doivent montrer: `Logging in to Docker Hub...`

---

## 📊 Vérifier que tout fonctionne

Après un **push sur main** (ou une release), vous devriez voir:

### ✅ Sur GitHub:
1. **Actions** → voir le workflow run
2. Job **build_release_docker** doit passer ✅
3. Logs: `Login successful`, `Pushed successfully`

### ✅ Sur Docker Hub:
1. Allez à votre profil: https://hub.docker.com/
2. Cherchez **watchtracker-api** dans vos repositories
3. Voir les tags (versions):
   ```
   sheik37/watchtracker-api:v1.0.0
   sheik37/watchtracker-api:v1.1.0
   ...
   ```

### ✅ Télécharger l'image (pour vérifier):
```bash
docker pull sheik37/watchtracker-api:latest
docker run -p 8000:8000 sheik37/watchtracker-api:latest
# Visitez: http://localhost:8000
```

---

## 🐛 Troubleshooting

### ❌ "Authentification failed"

**Cause**: Token expiré ou incorrect

**Solution**:
1. Aller à https://app.docker.com/settings/personal-access-tokens
2. Vérifier le token n'a pas expiré
3. Générer un nouveau token si nécessaire
4. Mettre à jour le secret `DOCKER_PASSWORD` sur GitHub

---

### ❌ "Repository not found"

**Cause**: Le repo n'existe pas encore sur Docker Hub (normal!)

**Solution**: 
1. Créer le repo manuellement:
   - Docker Hub → **Repositories** → **Create Repository**
   - Name: `watchtracker-api`
   - Description: `WatchTracker Backend API`
   - Visibility: `Public` (ou Private)
   - Create

2. Ou laisser le workflow le créer automatiquement au premier push

---

### ❌ "Layer too large"

**Cause**: Image > 10 GB

**Solution**:
1. Vérifier le `.dockerignore` (créé ✅)
2. Nettoyer les gros fichiers:
   ```bash
   cd server
   rm -rf __pycache__ .pytest_cache *.egg-info
   ```
3. Optimiser les requirements.txt (enlever les devDeps)

---

### ❌ "Tag invalid"

**Cause**: Caractères invalides dans le tag

**Solution**: Tags Docker doivent être:
- Minuscules
- Pas d'espaces
- Pas de caractères spéciaux (sauf `-` et `_`)

Exemple: ✅ `v1.0.0` ❌ `v1 0 0` ❌ `V1.0.0`

---

## 📖 Infos utiles

### Taille limite gratuit:
- ✅ Storage illimité sur Docker Hub public
- ✅ 1 repo privé gratuit
- ❌ Pas de limite de pulls (public)

### Images populaires:
```bash
docker pull sheik37/watchtracker-api:latest
# Télécharge de Docker Hub
```

### Nettoyer les vieilles images locales:
```bash
docker image prune -a          # Supprimer toutes les images non-utilisées
docker system prune -a          # Nettoyer complet
```

---

## 🎉 Prochaines étapes

Une fois configuré:

1. **Faire un push sur main**
   ```bash
   git push origin feature/flutter-parity-cleanup
   # Puis créer une PR et merger
   ```

2. **Voir la release créée**
   - GitHub → **Releases** → voir v1.x.x

3. **Voir l'image Docker poussée**
   - Docker Hub → **watchtracker-api** → **Tags**
   - Voir le tag `v1.x.x`

4. **Utiliser l'image**
   ```bash
   docker pull sheik37/watchtracker-api:v1.x.x
   docker run -p 8000:8000 sheik37/watchtracker-api:v1.x.x
   ```

---

## 📝 Résumé des secrets configurés

| Secret Name | Valeur | Exemple |
|-------------|--------|---------|
| DOCKER_USERNAME | Votre username | `sheik37` |
| DOCKER_PASSWORD | Votre access token | `dckr_pat_xxx` |
| DOCKER_REGISTRY | (optionnel, default) | `docker.io` |

---

## 🔗 Ressources utiles

- **Docker Hub**: https://hub.docker.com
- **Docker CLI Docs**: https://docs.docker.com/engine/reference/commandline/
- **Dockerfile Reference**: https://docs.docker.com/engine/reference/builder/
- **GitHub Secrets**: https://docs.github.com/en/actions/security-guides/encrypted-secrets

---

**Dernière mise à jour**: 2026-08-18

Besoin d'aide? Vérifiez la section **Troubleshooting** ci-dessus!
