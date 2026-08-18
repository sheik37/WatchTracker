# 📚 GitHub Actions - Procédures & Guide Équipe

## 🎯 Pour les développeurs

### ✅ Avant de faire un commit:

1. **Tester localement**:
   ```bash
   # Flutter
   cd flutter_app
   flutter analyze
   flutter test
   
   # Backend
   cd server
   pytest tests/
   ```

2. **Vérifier les line endings** (Windows):
   ```bash
   git config core.autocrlf false
   git config core.safecrlf true
   ```

3. **Messages de commits** (français requis):
   ```bash
   git commit -m "feat: ajouter nouvelle fonctionnalité"
   # Exemples:
   # feat: ajouter...
   # fix: corriger...
   # docs: documentation...
   # style: formatage...
   # refactor: refactorisation...
   # test: ajouter tests...
   # chore: maintenance...
   ```

---

## 🔀 Pour les Pull Requests:

### Créer une PR:
1. Créer une branche: `git checkout -b feature/ma-feature`
2. Coder & committer (commits français)
3. Pousser: `git push origin feature/ma-feature`
4. Créer PR sur GitHub (template auto)

### Vérifier les CI:
1. Aller sur la PR
2. **Checks** → Voir les workflows:
   - 📱 CI Flutter (doit passer)
   - 🔌 CI Backend (doit passer)
   - ✅ Format & Commits (doit passer)

### Corrections suite aux CI failures:

#### Si Flutter analyze échoue:
```bash
cd flutter_app
flutter analyze                # Voir les erreurs
dart format -w .               # Formater auto
flutter analyze                # Vérifier
git add . && git commit -m "fix: corriger flutter analyze"
git push
```

#### Si Backend tests échouent:
```bash
cd server
pytest tests/ -v               # Voir les erreurs
# Corriger le code
pytest tests/                  # Re-tester
git add . && git commit -m "fix: corriger tests backend"
git push
```

#### Si Format validation échoue:
```bash
# Line endings (Windows)
git config core.autocrlf false
dos2unix *.sh                  # Convertir CRLF → LF
# ou via sed:
sed -i 's/\r$//' *.sh

# Whitespace trailing
git diff --check                # Voir où
# Éditer les fichiers

git add . && git commit -m "chore: corriger format"
git push
```

---

## 📤 Pour les releases:

### Processus automatique:
1. PR mergée sur `main`
2. Workflow **04-release.yml** s'exécute automatiquement
3. Crée une **GitHub Release** avec:
   - Notes depuis les commits
   - APK (Android)
   - Docker image

### Vérifier la release:
1. GitHub → **Releases**
2. Voir la dernière release
3. Télécharger l'APK si besoin
4. Vérifier Docker image: `docker pull votre-registry/watchtracker-api:v1.x.x`

---

## 🔔 Pour les alertes:

### Slack notifications:
- ✅ **Succès sur main**: notifié dans #ci-notifications
- 🔴 **Failures**: notifié avec lien direct aux logs

### Email (si configuré):
- 🔴 Failures: Email reçu avec détails

### GitHub Issues (auto-créée):
- Quand un workflow échoue, une issue `🔴 Build Failed` est créée
- Permet de tracker les problèmes de CI

---

## 🛠️ Workflows spéciaux

### Dependency Updates:
- **Lundi 3:00 AM UTC**: Check automatique des updates
- Crée des PRs: `chore/flutter-deps-update` & `chore/python-deps-update`
- À revue + merger quand OK

### Performance Benchmarks:
- S'exécute sur chaque push/PR main/develop
- Commente les PRs avec metrics
- Données disponibles dans **Actions → Artifacts**

---

## 🔐 Secrets & Configurations

### Ajouter un secret:
1. GitHub → **Settings → Secrets and variables → Actions**
2. **New repository secret**
3. Name: `SLACK_WEBHOOK`
4. Value: copier l'URL complète
5. Add secret

### Voir les secrets configurés:
1. **Settings → Secrets**
2. Voir la liste (valeurs cachées)
3. Cliquer sur un secret → Update/Delete

### Note importante:
- Les secrets sont **never** loggés dans les CI (masqués auto par GitHub)
- Ne pas essayer de les afficher avec `echo`
- Utiliser uniquement dans les actions officielles

---

## 📊 Monitoring & Métriques

### Coverage:
- Reports disponibles sur **Codecov** (si connecté)
- Voir les métriques: https://codecov.io/gh/sheik37/WatchTracker

### Artifacts:
1. GitHub → **Actions**
2. Voir un workflow récent
3. **Artifacts** en bas → télécharger les données:
   - `flutter-app-apk` (APK)
   - `flutter-app-ios` (iOS build)
   - `api-benchmarks` (données perf)

### Logs:
1. GitHub → **Actions**
2. Cliquer sur un workflow
3. Voir les **Jobs** & leurs logs détaillés

---

## 🐛 Débogage courant

### Workflow ne s'exécute pas:
```
Check:
1. Le workflow est-il enable? (Actions → workflow name → Enable si grisé)
2. Les conditions `on:` sont-elles correctes?
3. Le commit touche-t-il les paths spécifiés?
4. Y a-t-il assez de credits (GitHub Actions gratuit = 2000 min/mois)
```

### Tests échouent en CI mais pas localement:
```
Causes possibles:
1. Versions différentes (pip install vs pip install -r requirements.txt)
2. Fichiers manquants (git ignore ou .gitattributes)
3. Env vars différentes (DATABASE_URL, etc)
4. OS différent (Windows vs Ubuntu)

Solution: Tester dans Docker:
docker build -t test . && docker run test
```

### APK build échoue:
```bash
# Tester localement:
cd flutter_app
flutter clean
flutter pub get
flutter build apk --release -v

# Si ça passe localement, check:
- Les SDK versions dans pubspec.yaml
- Les permissions dans android/app/build.gradle
- Les code signing (pour release)
```

---

## 🚀 Optimisations & Best Practices

### Accélérer les CI:
1. **Caching**: Les workflows utilisent `cache: true`
   - À chaque run, réutilise les dépendances cached
   - Gain: ~30-50% plus rapide

2. **Parallélisation**: Certains jobs s'exécutent en parallèle
   - `analyze`, `test`, `build_apk` run en même temps
   - Note: `build_ios` attend `test`

3. **Paths-ignore**: Ne trigger que si fichiers pertinents changent
   - Exemple: Flutter CI ignore `server/`

### Meilleurs commits:
- ✅ Commits atomiques (une feature = un commit)
- ✅ Messages descriptifs (français)
- ✅ Prefix avec type (feat:, fix:, etc)

### Code quality:
- ✅ Faire passer flutter analyze localement avant PR
- ✅ Ajouter des tests pour chaque feature
- ✅ Vérifier coverage (voir Codecov)

---

## 📞 Questions fréquentes

### Q: Combien ça coûte?
**A**: GitHub Actions gratuit jusqu'à 2000 min/mois (assez pour ce projet)
Après: $0.25 par 1000 minutes

### Q: Quand le workflow s'exécute exactement?
**A**: 
- `push`: à chaque commit
- `pull_request`: quand PR créée/updated
- `schedule`: à l'heure spécifiée en cron

### Q: Peux-je déclencher manuellement?
**A**: Oui! Via GitHub Actions UI:
1. **Actions** → choisir workflow
2. **Run workflow** → branche → Go

### Q: Comment ajouter une notification Discord?
**A**: 
1. Créer webhook Discord
2. Ajouter secret `DISCORD_WEBHOOK`
3. Utiliser `rjstone/discord-webhook-notify@v1` dans les workflows

### Q: Mon test échoue uniquement sur Ubuntu, pas Windows?
**A**: Check:
```yaml
os: [ubuntu-latest, windows-latest, macos-latest]  # Matrix
# ou tester:
if: runner.os == 'Windows'
```

---

## 📖 Ressources

- **GitHub Actions Docs**: https://docs.github.com/en/actions
- **Marketplace**: https://github.com/marketplace?type=actions
- **Flutter Testing**: https://flutter.dev/docs/testing
- **Pytest Docs**: https://docs.pytest.org/
- **Cron Format**: https://crontab.guru/

---

**Dernière mise à jour**: 2026-08-18

Pour questions → créer une issue ou demander à votre lead dev!
