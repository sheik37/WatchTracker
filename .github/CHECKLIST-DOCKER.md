# ✅ Checklist de Configuration Docker Hub

## 🐳 Phase 1: Compte Docker Hub

- [ ] Compte Docker Hub créé (https://app.docker.com)
- [ ] Email confirmé
- [ ] Connecté à Docker Hub
- [ ] **Username Docker**: _________________ 
      (notez-le pour l'étape 2)

**Validez**: Vous pouvez vous connecter à https://hub.docker.com

---

## 🔑 Phase 2: Access Token

- [ ] Allez à https://app.docker.com/settings/personal-access-tokens
- [ ] Cliqué: **Generate new token**
- [ ] Token name: `watchtracker-github-actions`
- [ ] Access permissions: ✓ Read & Write
- [ ] Token généré et **COPIÉ**
- [ ] **Token copied**: `dckr_pat_XXXXXXXXXXXXXXXX`
      (collez-le ci-dessous temporairement pour Phase 3)

```
dckr_pat_XXXXXXXXXXXXXXXX
```

⚠️ **IMPORTANT**: Ne perdez pas ce token après cette checklist!

**Validez**: Le token s'affiche dans une modal, commence par `dckr_pat_`

---

## 🔐 Phase 3: Secrets GitHub

### Aller à GitHub Secrets:
- [ ] Repo: https://github.com/sheik37/WatchTracker
- [ ] **Settings** → **Secrets and variables** → **Actions**
- [ ] (OU directement: https://github.com/sheik37/WatchTracker/settings/secrets/actions)

### Ajouter Secret 1 - DOCKER_USERNAME:
- [ ] Cliquer **New repository secret**
- [ ] Name: `DOCKER_USERNAME`
- [ ] Value: _________________ (votre username du Hub)
- [ ] Cliquer **Add secret**
- [ ] Vérifier que le secret apparaît dans la liste

### Ajouter Secret 2 - DOCKER_PASSWORD:
- [ ] Cliquer **New repository secret**
- [ ] Name: `DOCKER_PASSWORD`
- [ ] Value: _________________ (votre token `dckr_pat_...`)
- [ ] Cliquer **Add secret**
- [ ] Vérifier que le secret apparaît dans la liste

### Vérifier les deux secrets:
- [ ] `DOCKER_USERNAME` visible dans la liste
- [ ] `DOCKER_PASSWORD` visible dans la liste
- [ ] Les deux marqués **Updated less than a minute ago**

**Validez**: Allez à https://github.com/sheik37/WatchTracker/settings/secrets/actions
Vous devez voir:
```
✓ DOCKER_USERNAME    [Updated a few seconds ago]
✓ DOCKER_PASSWORD    [Updated a few seconds ago]
```

---

## 🧪 Phase 4: Test Local (OPTIONNEL)

Si vous avez Docker installé localement:

- [ ] Ouvrir terminal
- [ ] Lancer: `docker login --username YOUR_DOCKER_USERNAME`
- [ ] Entrer le token quand demandé
- [ ] Voir: `Login Succeeded`
- [ ] Test build: 
  ```bash
  cd "C:\Users\ptitb\Desktop\WatchTracker\WatchTracker Flutter\server"
  docker build -t votre_username/watchtracker-api:test .
  ```
- [ ] Test push:
  ```bash
  docker push votre_username/watchtracker-api:test
  ```
- [ ] Vérifier sur Docker Hub: https://hub.docker.com/
  Voir le repo `watchtracker-api` et le tag `test`

**Validez**: L'image s'est poussée sans erreur

---

## 🚀 Phase 5: Test via GitHub Actions

### Préparer un commit:
- [ ] Créer/éditer un fichier (ex: `.github/DOCKER-HUB-SETUP.md` ✅)
- [ ] Commit: `git add .github/DOCKER-HUB-SETUP.md`
- [ ] `git commit -m "docs: ajouter guide Docker Hub"`
- [ ] Pousser: `git push origin feature/flutter-parity-cleanup`

### Ou créer une PR et merger:
- [ ] Créer PR sur GitHub
- [ ] Attendre que les workflows passent (5-10 min)
- [ ] Merger sur main
- [ ] Une **Release** devrait être créée automatiquement

### Vérifier les logs:
- [ ] Aller à: https://github.com/sheik37/WatchTracker/actions
- [ ] Chercher le workflow **04-release** le plus récent
- [ ] Cliquer dessus
- [ ] Voir le job **build_release_docker**
- [ ] Les logs doivent montrer:
  ```
  ✅ Login to Docker Hub
  ✅ Build and push
  ✅ Pushed docker.io/your_username/watchtracker-api:vX.X.X
  ```

**Validez**: Pas d'erreur `401` ou `Authentication failed`

---

## 🎉 Phase 6: Vérification finale

### Sur Docker Hub:
- [ ] Allez à: https://hub.docker.com/
- [ ] Cliquez: **Repositories**
- [ ] Vous devez voir: `watchtracker-api`
- [ ] Ouvrez le repo
- [ ] Cliquez: **Tags**
- [ ] Vous devez voir les versions (ex: `v1.0.0`, `v1.0.1`, etc.)
- [ ] Image est accessible (pull count > 0)

### Test d'utilisation (optionnel):
```bash
docker pull sheik37/watchtracker-api:latest
docker run -p 8000:8000 sheik37/watchtracker-api:latest
```

- [ ] Image se télécharge sans erreur
- [ ] Container démarre sans erreur
- [ ] API répond à http://localhost:8000

**Validez**: ✅ Tout fonctionne! 🎉

---

## 📊 Résumé de configuration

| Élément | Statut | Valeur |
|---------|--------|--------|
| Compte Docker Hub | ✅ | `sheik37` |
| Access Token | ✅ | `dckr_pat_XXXX` |
| Secret `DOCKER_USERNAME` | ✅ | Configuré |
| Secret `DOCKER_PASSWORD` | ✅ | Configuré |
| Dockerfile | ✅ | `server/Dockerfile` |
| .dockerignore | ✅ | `server/.dockerignore` |
| Workflow release | ✅ | `.github/workflows/04-release.yml` |

---

## 🆘 Si quelque chose n'a pas fonctionné

### 1️⃣ Vérifier l'erreur exacte:
- [ ] Aller à GitHub Actions
- [ ] Ouvrir le job qui a échoué
- [ ] Lire les logs rouges
- [ ] Copier le message d'erreur

### 2️⃣ Erreurs courantes:

**`authentication failed`**
- ❌ Token incorrect ou expiré
- ✅ Régénérer un nouveau token sur Docker Hub
- ✅ Mettre à jour le secret `DOCKER_PASSWORD` sur GitHub

**`permission denied`**
- ❌ Token n'a pas la permission d'écrire
- ✅ Vérifier que "Read & Write" est coché sur Docker Hub

**`image not found`**
- ❌ Le Dockerfile n'existe pas ou chemin wrong
- ✅ Vérifier `server/Dockerfile` existe

**`layer too large`**
- ❌ Docker image > limite
- ✅ Vérifier `.dockerignore` exclude les fichiers inutiles

### 3️⃣ Demander de l'aide:
- [ ] Créer une GitHub issue: https://github.com/sheik37/WatchTracker/issues/new
- [ ] Titre: `🐳 Docker Hub Configuration Issue`
- [ ] Description: Copier le message d'erreur complet
- [ ] Joindre le lien du workflow qui a échoué

---

## 📝 Notes personnelles

```
Mot de passe Docker Hub:     _________________
Access Token:                 _________________
Username Docker:              _________________
```

⚠️ **À supprimer après configuration!**

---

## ✨ Bravo! Vous avez réussi! 🎉

Votre pipeline CI/CD est maintenant complet:
- ✅ Flutter build automatique
- ✅ Backend tests automatiques
- ✅ Releases automatiques
- ✅ Docker pushes automatiques

**Prochaine étape**: Regarder les releases sur:
- GitHub: https://github.com/sheik37/WatchTracker/releases
- Docker Hub: https://hub.docker.com/r/sheik37/watchtracker-api

---

**Dernière mise à jour**: 2026-08-18
**Créé pour**: sheik37
