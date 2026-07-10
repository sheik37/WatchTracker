from fastapi.testclient import TestClient
import pytest

import app as app_module


client = TestClient(app_module.app)


@pytest.fixture(autouse=True)
def auth_override():
    app_module.app.dependency_overrides[app_module.get_current_user_id] = lambda: 1
    try:
        yield
    finally:
        app_module.app.dependency_overrides.clear()


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_watchlist_endpoints(monkeypatch):
    monkeypatch.setattr(app_module, "list_watchlist", lambda user_id, content_category=None: [{"id": 1, "title": "Bleach"}])
    monkeypatch.setattr(app_module, "list_all_episode_progress", lambda user_id: [{"media_id": 1, "season_number": 1, "episode_number": 1, "is_watched": True}])
    monkeypatch.setattr(app_module, "upsert_watchlist", lambda user_id, item: {"id": item.id, "title": item.title})
    monkeypatch.setattr(app_module, "update_watch_status", lambda *args: {"ok": True})
    monkeypatch.setattr(app_module, "update_watch_total", lambda *args: {"ok": True})
    monkeypatch.setattr(app_module, "delete_watchlist", lambda *args: None)

    response = client.get("/watchlist")
    assert response.status_code == 200
    assert response.json()[0]["title"] == "Bleach"

    snapshot = client.get("/sync/snapshot")
    assert snapshot.status_code == 200
    payload = snapshot.json()
    assert payload["watchlist"][0]["title"] == "Bleach"
    assert payload["episode_progress"][0]["media_id"] == 1


def test_anime_structure_lookup(monkeypatch):
    monkeypatch.setattr(app_module, "get_anime_structure", lambda normalized_title: {"normalized_title": normalized_title})
    monkeypatch.setattr(app_module, "upsert_anime_structure", lambda item: {"title": item.title})

    response = client.get("/anime-structures/Bleach")
    assert response.status_code == 200
    assert response.json()["normalized_title"] == "bleach"


def test_auth_login(monkeypatch):
    monkeypatch.setattr(app_module, "login_user", lambda username, password: {"token": "token-123"})
    response = client.post("/auth/login", json={"username": "alex", "password": "password123"})
    assert response.status_code == 200
    assert response.json()["token"] == "token-123"


def test_auth_logout(monkeypatch):
    monkeypatch.setattr(app_module, "revoke_auth_token", lambda token: True)
    response = client.post("/auth/logout", headers={"Authorization": "Bearer token-123"})
    assert response.status_code == 204


def test_auth_login_rate_limited(monkeypatch):
    async def fake_retry_after(endpoint, ip):
        if endpoint == "login":
            return 5.0, 1_700_000_123
        return 0.0, None

    monkeypatch.setattr(app_module.auth_rate_limiter, "get_retry_after", fake_retry_after)
    response = client.post("/auth/login", json={"username": "alex", "password": "password123"})
    assert response.status_code == 429
    assert response.headers["Retry-After"] == "6"
