# WatchTracker Flutter

## Configuration runtime (dart-define)

Variables backend/TMDB :

- `BACKEND_BASE_URL` : URL de l'API backend (ex: `http://10.0.2.2:8000`).
- `TMDB_API_KEY` : clé API TMDB utilisée pour la recherche/détails médias.

## Mises à jour hors store

L'app supporte maintenant une vérification de mises à jour côté **Profil > À propos**.

Variables de lancement disponibles :

- `UPDATE_MANIFEST_URL` : URL d'un JSON de version.
- `ANDROID_UPDATE_URL` : lien direct APK (fallback Android).
- `IOS_UPDATE_URL` : lien TestFlight (fallback iOS).
- `UPDATE_DOWNLOAD_URL` : fallback générique (desktop/autres).
- `APP_VERSION` : version locale affichée/comparée (ex: `1.0.0`).
- `APP_BUILD_NUMBER` : build locale affichée/comparée (ex: `1`).

Exemple de manifest JSON :

```json
{
  "latest_version": "1.0.1",
  "latest_build": 2,
  "android_url": "https://example.com/watchtracker-1.0.1.apk",
  "ios_url": "https://testflight.apple.com/join/XXXXXXX",
  "release_notes": "Corrections et améliorations de stabilité."
}
```

Exemple de lancement :

```bash
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:8000 --dart-define=TMDB_API_KEY=YOUR_TMDB_KEY --dart-define=APP_VERSION=1.0.0 --dart-define=APP_BUILD_NUMBER=1 --dart-define=UPDATE_MANIFEST_URL=https://example.com/version.json --dart-define=ANDROID_UPDATE_URL=https://example.com/watchtracker-latest.apk --dart-define=IOS_UPDATE_URL=https://testflight.apple.com/join/XXXXXXX
```

🟠 Mineur
# 
Fonctionnalité
8
Mise à jour : ouvre le navigateur au lieu d'installer l'APK directement