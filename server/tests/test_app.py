import pytest
from fastapi.testclient import TestClient

import app as app_module

client = TestClient(app_module.app)


@pytest.fixture(autouse=True)
def auth_override(monkeypatch):
    async def no_retry(endpoint, ip, email):
        _ = endpoint
        _ = ip
        _ = email
        return 0.0, None

    async def no_failure(endpoint, ip, email):
        _ = endpoint
        _ = ip
        _ = email
        return 0.0, 5, None, 0, False

    async def no_success(endpoint, ip, email):
        _ = endpoint
        _ = ip
        _ = email

    async def limiter_no_retry(endpoint, key):
        _ = endpoint
        _ = key
        return 0.0, None

    async def limiter_no_failure(endpoint, key):
        _ = endpoint
        _ = key
        return 0.0, 5, None, 0, False

    async def limiter_no_success(endpoint, key):
        _ = endpoint
        _ = key

    app_module.app.dependency_overrides[app_module.get_current_user_id] = lambda: 1
    monkeypatch.setattr(app_module, "_get_auth_retry_after", no_retry)
    monkeypatch.setattr(app_module, "_register_auth_failure", no_failure)
    monkeypatch.setattr(app_module, "_register_auth_success", no_success)
    monkeypatch.setattr(
        app_module.auth_rate_limiter, "get_retry_after", limiter_no_retry
    )
    monkeypatch.setattr(
        app_module.auth_rate_limiter, "register_failure", limiter_no_failure
    )
    monkeypatch.setattr(
        app_module.auth_rate_limiter, "register_success", limiter_no_success
    )
    try:
        yield
    finally:
        app_module.app.dependency_overrides.clear()


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_watchlist_endpoints(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "list_watchlist_since",
        lambda user_id, content_category=None, since=None: [
            {"id": 1, "title": "Bleach"}
        ],
    )
    monkeypatch.setattr(
        app_module,
        "list_all_episode_progress_since",
        lambda user_id, since=None: [
            {"media_id": 1, "season_number": 1, "episode_number": 1, "is_watched": True}
        ],
    )
    monkeypatch.setattr(
        app_module, "list_watchlist_tombstones_since", lambda user_id, since=None: []
    )
    monkeypatch.setattr(
        app_module,
        "list_episode_progress_tombstones_since",
        lambda user_id, since=None: [],
    )
    monkeypatch.setattr(
        app_module,
        "upsert_watchlist",
        lambda user_id, item: {"id": item.id, "title": item.title},
    )
    monkeypatch.setattr(app_module, "update_watch_status", lambda *args: {"ok": True})
    monkeypatch.setattr(app_module, "update_watch_total", lambda *args: {"ok": True})
    monkeypatch.setattr(app_module, "delete_watchlist", lambda *args: None)

    response = client.get("/watchlist")
    assert response.status_code == 200
    assert response.json()[0]["title"] == "Bleach"

    snapshot = client.get("/sync/snapshot")
    assert snapshot.status_code == 200
    payload = snapshot.json()
    assert payload["snapshot_at"] > 0
    assert payload["watchlist"][0]["title"] == "Bleach"
    assert payload["episode_progress"][0]["media_id"] == 1


def test_watchlist_movie_rewatch_endpoint(monkeypatch):
    called = {}

    def fake_rewatch(user_id, media_id, media_type, content_category):
        called.update(
            {
                "user_id": user_id,
                "media_id": media_id,
                "media_type": media_type,
                "content_category": content_category,
            }
        )
        return True

    monkeypatch.setattr(app_module, "rewatch_movie", fake_rewatch)

    response = client.post("/watchlist/42/movie/films/rewatch")
    assert response.status_code == 204
    assert called == {
        "user_id": 1,
        "media_id": 42,
        "media_type": "movie",
        "content_category": "films",
    }


def test_watchlist_movie_rewatch_rejects_non_movie():
    response = client.post("/watchlist/42/tv/series/rewatch")
    assert response.status_code == 400
    assert response.json()["detail"] == "Rewatch endpoint is only available for movies"


def test_episode_rewatch_endpoint(monkeypatch):
    called = {}

    def fake_rewatch_episode(user_id, media_id, season_number, episode_number):
        called.update(
            {
                "user_id": user_id,
                "media_id": media_id,
                "season_number": season_number,
                "episode_number": episode_number,
            }
        )

    monkeypatch.setattr(app_module, "rewatch_episode_progress", fake_rewatch_episode)
    response = client.post("/episode-progress/50/2/7/rewatch")

    assert response.status_code == 204
    assert called == {
        "user_id": 1,
        "media_id": 50,
        "season_number": 2,
        "episode_number": 7,
    }


def test_episode_rewatch_season_endpoint(monkeypatch):
    called = {}

    def fake_rewatch_season(user_id, media_id, season_number, episode_numbers):
        called.update(
            {
                "user_id": user_id,
                "media_id": media_id,
                "season_number": season_number,
                "episode_numbers": episode_numbers,
            }
        )

    monkeypatch.setattr(app_module, "rewatch_episode_season", fake_rewatch_season)
    response = client.post(
        "/episode-progress/50/rewatch-season",
        json={"season_number": 2, "episode_numbers": [1, 2, 3]},
    )

    assert response.status_code == 204
    assert called == {
        "user_id": 1,
        "media_id": 50,
        "season_number": 2,
        "episode_numbers": [1, 2, 3],
    }


def test_episode_rewatch_season_endpoint_validates_episode_numbers():
    response = client.post(
        "/episode-progress/50/rewatch-season",
        json={"season_number": 2, "episode_numbers": [1, 0, 3]},
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Invalid episode number"


def test_auth_login(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "authenticate_user",
        lambda email, password: {"user_id": 7, "email": email},
    )
    monkeypatch.setattr(
        app_module,
        "issue_session_tokens_for_user",
        lambda user_id: {
            "access_token": "access-123",
            "refresh_token": "refresh-123",
            "expires_in_seconds": 900,
        },
    )
    response = client.post(
        "/auth/login", json={"email": "alex@example.com", "password": "password123"}
    )
    assert response.status_code == 200
    assert response.json()["token"] == "access-123"
    assert response.json()["access_token"] == "access-123"
    assert response.json()["refresh_token"] == "refresh-123"


def test_auth_login_requires_2fa_for_admin(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "authenticate_user",
        lambda email, password: {"user_id": 7, "email": email},
    )
    monkeypatch.setattr(
        app_module,
        "issue_session_tokens_for_user",
        lambda user_id: (_ for _ in ()).throw(RuntimeError("must_not_issue_token")),
    )
    monkeypatch.setattr(app_module, "ADMIN_2FA_EMAIL", "admin@example.com")
    monkeypatch.setattr(app_module, "ADMIN_2FA_TOTP_SECRET", "JBSWY3DPEHPK3PXP")
    monkeypatch.setattr(app_module, "_verify_admin_totp_code", lambda code: False)
    response = client.post(
        "/auth/login", json={"email": "admin@example.com", "password": "password123"}
    )
    assert response.status_code == 401
    assert response.json()["detail"] == "Two-factor code required"


def test_auth_login_accepts_2fa_for_admin(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "authenticate_user",
        lambda email, password: {"user_id": 7, "email": email},
    )
    monkeypatch.setattr(
        app_module,
        "issue_session_tokens_for_user",
        lambda user_id: {
            "access_token": "access-123",
            "refresh_token": "refresh-123",
            "expires_in_seconds": 900,
        },
    )
    monkeypatch.setattr(app_module, "ADMIN_2FA_EMAIL", "admin@example.com")
    monkeypatch.setattr(app_module, "ADMIN_2FA_TOTP_SECRET", "JBSWY3DPEHPK3PXP")
    monkeypatch.setattr(
        app_module, "_verify_admin_totp_code", lambda code: code == "123456"
    )
    response = client.post(
        "/auth/login",
        json={
            "email": "admin@example.com",
            "password": "password123",
            "otp_code": "123456",
        },
    )
    assert response.status_code == 200
    assert response.json()["access_token"] == "access-123"


def test_auth_login_blocks_admin_when_2fa_secret_missing(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "authenticate_user",
        lambda email, password: {"user_id": 7, "email": email},
    )
    monkeypatch.setattr(app_module, "ADMIN_2FA_EMAIL", "admin@example.com")
    monkeypatch.setattr(app_module, "ADMIN_2FA_TOTP_SECRET", "")
    response = client.post(
        "/auth/login", json={"email": "admin@example.com", "password": "password123"}
    )
    assert response.status_code == 503
    assert (
        response.json()["detail"] == "Admin two-factor authentication is not configured"
    )


def test_auth_register(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "register_user",
        lambda email, password: {"user_id": 1, "email": email, "created_new": True},
    )
    monkeypatch.setattr(
        app_module, "create_email_verification_token", lambda user_id: "verify-token"
    )
    monkeypatch.setattr(
        app_module, "_send_verification_email", lambda email, verify_link: None
    )
    response = client.post(
        "/auth/register", json={"email": "alex@example.com", "password": "password123"}
    )
    assert response.status_code == 201
    assert response.json()["message"] == "Verification email sent"


def test_auth_register_weak_password(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "register_user",
        lambda email, password: (_ for _ in ()).throw(ValueError("password_too_weak")),
    )
    response = client.post(
        "/auth/register", json={"email": "alex@example.com", "password": "password1234"}
    )
    assert response.status_code == 400


def test_auth_register_email_limit_reached(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "register_user",
        lambda email, password: {"user_id": 1, "email": email, "created_new": True},
    )
    monkeypatch.setattr(
        app_module, "create_email_verification_token", lambda user_id: "verify-token"
    )
    monkeypatch.setattr(
        app_module,
        "_send_verification_email",
        lambda email, verify_link: (_ for _ in ()).throw(
            RuntimeError("email_daily_limit_reached")
        ),
    )
    monkeypatch.setattr(app_module, "delete_user_by_id", lambda user_id: None)
    response = client.post(
        "/auth/register", json={"email": "alex@example.com", "password": "password123"}
    )
    assert response.status_code == 503


def test_auth_verify_email(monkeypatch):
    valid_token = "valid-token-abcdefghijklmnopqrstuvwxyz"
    invalid_token = "invalid-token-abcdefghijklmnopqrstuvwxyz"
    monkeypatch.setattr(
        app_module, "verify_email_token", lambda token: token == valid_token
    )
    ok = client.get("/auth/verify-email", params={"token": valid_token})
    assert ok.status_code == 200
    ko = client.get("/auth/verify-email", params={"token": invalid_token})
    assert ko.status_code == 400


def test_auth_logout(monkeypatch):
    monkeypatch.setattr(app_module, "revoke_auth_token", lambda token: True)
    revoked_refresh = {}
    monkeypatch.setattr(
        app_module,
        "revoke_refresh_token",
        lambda token: revoked_refresh.setdefault("token", token),
    )
    response = client.post(
        "/auth/logout",
        headers={"Authorization": "Bearer token-123"},
        json={"refresh_token": "refresh-token-abcdefghijklmnopqrstuvwxyz"},
    )
    assert response.status_code == 204
    assert revoked_refresh["token"] == "refresh-token-abcdefghijklmnopqrstuvwxyz"


def test_auth_refresh(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "rotate_refresh_token",
        lambda token: (
            {
                "access_token": "access-new",
                "refresh_token": "refresh-new",
                "expires_in_seconds": 900,
            }
            if token == "refresh-token-abcdefghijklmnopqrstuvwxyz"
            else None
        ),
    )
    response = client.post(
        "/auth/refresh",
        json={"refresh_token": "refresh-token-abcdefghijklmnopqrstuvwxyz"},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["access_token"] == "access-new"
    assert payload["refresh_token"] == "refresh-new"


def test_auth_me(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "get_user_profile",
        lambda user_id: {
            "user_id": user_id,
            "email": "alex@example.com",
            "display_name": "Alex",
        },
    )
    response = client.get("/auth/me")
    assert response.status_code == 200
    assert response.json()["email"] == "alex@example.com"
    assert response.json()["display_name"] == "Alex"


def test_auth_me_update(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "update_user_display_name",
        lambda user_id, display_name: {
            "user_id": user_id,
            "email": "alex@example.com",
            "display_name": display_name,
        },
    )
    response = client.patch("/auth/me", json={"display_name": "NouveauNom"})
    assert response.status_code == 200
    assert response.json()["display_name"] == "NouveauNom"


def test_auth_change_password(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "change_password_for_user",
        lambda user_id, current_password, new_password: "updated",
    )
    response = client.post(
        "/auth/change-password",
        json={
            "current_password": "ancienMotDePasse123!",
            "new_password": "NouveauMotDePasse123!",
        },
    )
    assert response.status_code == 200
    assert response.json()["message"] == "Password updated"


def test_auth_change_password_invalid_current(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "change_password_for_user",
        lambda user_id, current_password, new_password: "current_password_invalid",
    )
    response = client.post(
        "/auth/change-password",
        json={"current_password": "bad", "new_password": "NouveauMotDePasse123!"},
    )
    assert response.status_code == 400
    assert "Current password is invalid" in response.json()["detail"]


def test_auth_resend_verification_neutral_response(monkeypatch):
    monkeypatch.setattr(
        app_module, "create_verification_token_for_email", lambda email: None
    )
    response = client.post(
        "/auth/resend-verification", json={"email": "alex@example.com"}
    )
    assert response.status_code == 202
    assert "Si un compte" in response.json()["message"]


def test_auth_forgot_password_neutral_response(monkeypatch):
    monkeypatch.setattr(
        app_module, "create_password_reset_token_for_email", lambda email: None
    )
    response = client.post("/auth/forgot-password", json={"email": "alex@example.com"})
    assert response.status_code == 202
    assert "Si un compte existe" in response.json()["message"]


def test_auth_forgot_password_sends_link(monkeypatch):
    sent = {}
    monkeypatch.setattr(
        app_module,
        "create_password_reset_token_for_email",
        lambda email: {
            "email": email,
            "token": "valid-token-abcdefghijklmnopqrstuvwxyz",
        },
    )
    monkeypatch.setattr(
        app_module,
        "_send_password_reset_email",
        lambda email, link: sent.update({"email": email, "link": link}),
    )
    response = client.post("/auth/forgot-password", json={"email": "alex@example.com"})
    assert response.status_code == 202
    assert sent["email"] == "alex@example.com"
    assert "/auth/reset-password?token=" in sent["link"]


def test_auth_forgot_password_limit_reached_stays_neutral(monkeypatch):
    monkeypatch.setattr(
        app_module,
        "create_password_reset_token_for_email",
        lambda email: {
            "email": email,
            "token": "valid-token-abcdefghijklmnopqrstuvwxyz",
        },
    )
    monkeypatch.setattr(
        app_module,
        "_send_password_reset_email",
        lambda email, link: (_ for _ in ()).throw(
            RuntimeError("email_daily_limit_reached")
        ),
    )
    response = client.post("/auth/forgot-password", json={"email": "alex@example.com"})
    assert response.status_code == 202
    assert "Si un compte existe" in response.json()["message"]


def test_auth_reset_password_page():
    token = "valid-token-abcdefghijklmnopqrstuvwxyz"
    response = client.get("/auth/reset-password", params={"token": token})
    assert response.status_code == 200
    assert "Réinitialiser ton mot de passe" in response.text
    assert token in response.text
    assert "/auth/reset-password/confirm" in response.text


def test_auth_reset_password_confirm_page(monkeypatch):
    valid_token = "valid-token-abcdefghijklmnopqrstuvwxyz"
    monkeypatch.setattr(
        app_module,
        "reset_password_with_token",
        lambda token, password: (
            "updated" if token == valid_token else "invalid_or_expired"
        ),
    )
    ok = client.post(
        "/auth/reset-password/confirm",
        data={
            "token": valid_token,
            "password": "password123",
            "confirm_password": "password123",
        },
    )
    assert ok.status_code == 200
    assert "Mot de passe mis à jour" in ok.text
    assert "/auth/reset-password/confirm" not in ok.text
    ko = client.post(
        "/auth/reset-password/confirm",
        data={
            "token": valid_token,
            "password": "password123",
            "confirm_password": "password456",
        },
    )
    assert ko.status_code == 400
    assert "ne correspondent pas" in ko.text


def test_auth_reset_password(monkeypatch):
    valid_token = "valid-token-abcdefghijklmnopqrstuvwxyz"
    invalid_token = "invalid-token-abcdefghijklmnopqrstuvwxyz"
    monkeypatch.setattr(
        app_module,
        "reset_password_with_token",
        lambda token, password: (
            "updated" if token == valid_token else "invalid_or_expired"
        ),
    )
    ok = client.post(
        "/auth/reset-password", json={"token": valid_token, "password": "password123"}
    )
    assert ok.status_code == 200
    ko = client.post(
        "/auth/reset-password", json={"token": invalid_token, "password": "password123"}
    )
    assert ko.status_code == 400


def test_auth_reset_password_reject_same_password(monkeypatch):
    valid_token = "valid-token-abcdefghijklmnopqrstuvwxyz"
    monkeypatch.setattr(
        app_module,
        "reset_password_with_token",
        lambda token, password: "same_as_current",
    )
    response = client.post(
        "/auth/reset-password", json={"token": valid_token, "password": "password123"}
    )
    assert response.status_code == 400
    assert "different from current password" in response.json()["detail"]


def test_auth_reset_password_reject_reused_password(monkeypatch):
    valid_token = "valid-token-abcdefghijklmnopqrstuvwxyz"
    monkeypatch.setattr(
        app_module,
        "reset_password_with_token",
        lambda token, password: "password_reused",
    )
    response = client.post(
        "/auth/reset-password", json={"token": valid_token, "password": "password123"}
    )
    assert response.status_code == 400
    assert "already used recently" in response.json()["detail"]


def test_auth_login_rate_limited(monkeypatch):
    async def fake_retry_after(endpoint, ip, email):
        if endpoint == "login" and email == "alex@example.com":
            return 5.0, 1_700_000_123
        return 0.0, None

    monkeypatch.setattr(app_module, "_get_auth_retry_after", fake_retry_after)
    response = client.post(
        "/auth/login", json={"email": "alex@example.com", "password": "password123"}
    )
    assert response.status_code == 429
    assert response.headers["Retry-After"] == "6"
