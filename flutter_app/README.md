# WatchTracker Flutter

## Configuration runtime (dart-define)

Variables backend/TMDB :

- `BACKEND_BASE_URL` : URL de l'API backend (ex: `http://10.0.2.2:8000`).
- `TMDB_API_KEY` : clé API TMDB utilisée pour la recherche/détails médias.

## Sources des saisons et épisodes

- Films et séries : découpage et informations TMDB uniquement.
- Animés : saisons et numéros TVDB, mais nom, résumé, illustration, date et
  durée des épisodes exclusivement TMDB. L'association suit l'ordre global :
  TVDB S2E1 peut correspondre à TMDB S1E25. Les spéciaux (saison 0) sont
  associés séparément et ne décalent jamais les épisodes réguliers.
- Seules les saisons TMDB intersectant la saison TVDB demandée sont chargées.
  Un épisode TMDB absent conserve son numéro TVDB avec un libellé explicite,
  sans reprendre les informations d'un autre épisode.
- Le cache hors ligne est versionné par fournisseur ; les anciens caches sans
  source ne sont pas réutilisés pour ces saisons/épisodes (la progression et
  la watchlist restent intactes). En cas d'indisponibilité TVDB, son découpage
  en cache est privilégié ; sans découpage TVDB utilisable, repli TMDB avec
  diagnostic `MediaRepository`.

## Mises à jour hors store

L'app supporte maintenant une vérification de mises à jour côté **Profil > À propos**.

Variables de lancement disponibles :

- `UPDATE_MANIFEST_URL` : URL d'un JSON de version.
- `ANDROID_UPDATE_URL` : lien direct APK (fallback Android).
- `IOS_UPDATE_URL` : lien TestFlight (fallback iOS).
- `UPDATE_DOWNLOAD_URL` : fallback générique (desktop/autres).
- `APP_VERSION` : version locale affichée/comparée (ex: `2.0.0`).
- `APP_BUILD_NUMBER` : build locale affichée/comparée (ex: `1`).

Exemple de manifest JSON :

```json
{
  "latest_version": "2.0.1",
  "latest_build": 2,
  "android_url": "https://example.com/watchtracker-2.0.1.apk",
  "ios_url": "https://testflight.apple.com/join/XXXXXXX",
  "release_notes": "Corrections et améliorations de stabilité."
}
```

Exemple de lancement :

```bash
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:8000 --dart-define=TMDB_API_KEY=YOUR_TMDB_KEY --dart-define=APP_VERSION=2.0.0 --dart-define=APP_BUILD_NUMBER=1 --dart-define=UPDATE_MANIFEST_URL=https://example.com/version.json --dart-define=ANDROID_UPDATE_URL=https://example.com/watchtracker-latest.apk --dart-define=IOS_UPDATE_URL=https://testflight.apple.com/join/XXXXXXX
```

🟠 Mineur
# 
Fonctionnalité
8
Mise à jour : ouvre le navigateur au lieu d'installer l'APK directement