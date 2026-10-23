"""Tests de caractérisation : figent le comportement ACTUEL de crud.py avant
le refactor (découpage en modules, optimisation des requêtes groupées, etc.).

Ces tests n'utilisent pas de vraie base PostgreSQL (aucune instance n'est
disponible dans cet environnement) : ils remplacent ``cursor()`` par de
petites doublures qui enregistrent les requêtes SQL exécutées, à l'image de
``tests/test_crud.py`` existant.
"""

import contextlib
from datetime import datetime, timezone

import crud
from schemas import EpisodeProgressItemIn


# ---------------------------------------------------------------------------
# replace_episode_progress / rewatch_episode_season : une requête par épisode
# ---------------------------------------------------------------------------


class _EpisodeLoopCursor:
    """Curseur factice générique : compte les requêtes, sans logique métier."""

    def __init__(self):
        self.executed: list[str] = []
        self._last_sql = ""

    def execute(self, sql, params=()):
        self.executed.append(sql)
        self._last_sql = sql

    def fetchone(self):
        if "SELECT is_watched, updated_at, sync_updated_at" in self._last_sql:
            return None  # Aucun épisode existant : pas de "already_watched".
        return None

    def fetchall(self):
        return []


def test_replace_episode_progress_issues_queries_per_episode_before_optimisation(
    monkeypatch,
):
    cur = _EpisodeLoopCursor()
    monkeypatch.setattr(crud, "cursor", lambda: contextlib.nullcontext(cur))

    items = [
        EpisodeProgressItemIn(season_number=1, episode_number=1, is_watched=True),
        EpisodeProgressItemIn(season_number=1, episode_number=2, is_watched=True),
        EpisodeProgressItemIn(season_number=1, episode_number=3, is_watched=False),
    ]
    crud.replace_episode_progress(user_id=1, media_id=99, items=items)

    # Comportement actuel (avant optimisation) : chaque item "watched" émet 4
    # requêtes (SELECT FOR UPDATE, INSERT watch_events, DELETE tombstone,
    # UPSERT progress) et chaque item "unwatched" en émet 2 (DELETE
    # watch_events, UPSERT progress) : une requête par épisode, pas de
    # regroupement SQL.
    assert len(cur.executed) == 4 + 4 + 2


def test_replace_episode_progress_noop_without_db_access_when_no_items(monkeypatch):
    def boom():
        raise AssertionError("cursor() ne doit pas être ouvert si items est vide")

    monkeypatch.setattr(crud, "cursor", lambda: boom())
    crud.replace_episode_progress(user_id=1, media_id=99, items=[])


def test_rewatch_episode_season_dedupes_sorts_and_loops_per_episode(monkeypatch):
    calls: list[int] = []

    def fake_set_watched(
        cur, *, user_id, media_id, season_number, episode_number, allow_rewatch,
        watched_at=None,
    ):
        calls.append(episode_number)

    monkeypatch.setattr(crud, "_set_episode_watched", fake_set_watched)
    monkeypatch.setattr(crud, "cursor", lambda: contextlib.nullcontext(object()))

    crud.rewatch_episode_season(
        user_id=1, media_id=5, season_number=2, episode_numbers=[3, 1, 3, 0, 2]
    )

    # Comportement actuel : dédoublonnage + tri croissant, puis une boucle qui
    # appelle _set_episode_watched un épisode à la fois (0 est ignoré).
    assert calls == [1, 2, 3]


def test_rewatch_episode_season_noop_without_db_access_when_all_invalid(monkeypatch):
    def boom():
        raise AssertionError("cursor() ne doit pas être ouvert sans épisode valide")

    monkeypatch.setattr(crud, "cursor", lambda: boom())
    crud.rewatch_episode_season(
        user_id=1, media_id=5, season_number=2, episode_numbers=[0, -1]
    )


# ---------------------------------------------------------------------------
# verify_email_token
# ---------------------------------------------------------------------------


class _VerifyEmailCursor:
    def __init__(self, row):
        self.row = row
        self.executed: list[str] = []
        self._last_sql = ""

    def execute(self, sql, params=()):
        self.executed.append(sql)
        self._last_sql = sql

    def fetchone(self):
        if "FROM email_verification_tokens" in self._last_sql:
            return self.row
        return None


def test_verify_email_token_marks_user_verified_and_token_used(monkeypatch):
    cur = _VerifyEmailCursor({"user_id": 11})
    monkeypatch.setattr(crud, "cursor", lambda: contextlib.nullcontext(cur))

    assert crud.verify_email_token("sometoken") is True
    assert any(
        "UPDATE users" in sql and "email_verified_at = now()" in sql
        for sql in cur.executed
    )
    assert any(
        "UPDATE email_verification_tokens" in sql and "used_at = now()" in sql
        for sql in cur.executed
    )


def test_verify_email_token_returns_false_and_stops_at_select_when_missing(
    monkeypatch,
):
    cur = _VerifyEmailCursor(None)
    monkeypatch.setattr(crud, "cursor", lambda: contextlib.nullcontext(cur))

    assert crud.verify_email_token("bad-token") is False
    assert len(cur.executed) == 1  # seul le SELECT a été exécuté


# ---------------------------------------------------------------------------
# reset_password_with_token
# ---------------------------------------------------------------------------


class _ResetPasswordCursor:
    def __init__(self, row):
        self.row = row
        self.executed: list[str] = []
        self._last_sql = ""

    def execute(self, sql, params=()):
        self.executed.append(sql)
        self._last_sql = sql

    def fetchone(self):
        if "FROM password_reset_tokens" in self._last_sql:
            return self.row
        return None


def test_reset_password_with_token_rejects_weak_password_without_opening_cursor(
    monkeypatch,
):
    def boom():
        raise AssertionError("cursor() ne doit pas être ouvert pour un mdp faible")

    monkeypatch.setattr(crud, "cursor", lambda: boom())
    assert crud.reset_password_with_token("tok", "short") == "password_too_short"


def test_reset_password_with_token_rejects_same_as_current(monkeypatch):
    cur = _ResetPasswordCursor({"user_id": 3, "password_hash": "irrelevant"})
    monkeypatch.setattr(crud, "cursor", lambda: contextlib.nullcontext(cur))
    monkeypatch.setattr(crud, "_verify_password", lambda password, encoded: True)

    result = crud.reset_password_with_token("tok", "Str0ngPassw0rd!")
    assert result == "same_as_current"
    assert len(cur.executed) == 1  # pas de mutation si mdp identique


def test_reset_password_with_token_rejects_reused_password(monkeypatch):
    cur = _ResetPasswordCursor({"user_id": 3, "password_hash": "irrelevant"})
    monkeypatch.setattr(crud, "cursor", lambda: contextlib.nullcontext(cur))
    monkeypatch.setattr(crud, "_verify_password", lambda password, encoded: False)
    monkeypatch.setattr(
        crud, "_is_password_reused", lambda cur, user_id, password: True
    )

    assert crud.reset_password_with_token("tok", "Str0ngPassw0rd!") == "password_reused"


def test_reset_password_with_token_updates_and_revokes_sessions(monkeypatch):
    cur = _ResetPasswordCursor({"user_id": 3, "password_hash": "irrelevant"})
    monkeypatch.setattr(crud, "cursor", lambda: contextlib.nullcontext(cur))
    monkeypatch.setattr(crud, "_verify_password", lambda password, encoded: False)
    monkeypatch.setattr(
        crud, "_is_password_reused", lambda cur, user_id, password: False
    )
    revoked: list[int] = []
    monkeypatch.setattr(
        crud, "revoke_all_user_sessions", lambda cur, user_id: revoked.append(user_id)
    )

    result = crud.reset_password_with_token("tok", "Str0ngPassw0rd!")
    assert result == "updated"
    assert revoked == [3]
    assert any(
        "UPDATE users" in sql and "password_hash" in sql for sql in cur.executed
    )
    assert any("UPDATE password_reset_tokens" in sql for sql in cur.executed)
    assert any("INSERT INTO password_history" in sql for sql in cur.executed)


# ---------------------------------------------------------------------------
# change_password_for_user
# ---------------------------------------------------------------------------


class _ChangePasswordCursor:
    def __init__(self, row):
        self.row = row
        self.executed: list[str] = []
        self._last_sql = ""

    def execute(self, sql, params=()):
        self.executed.append(sql)
        self._last_sql = sql

    def fetchone(self):
        if "FROM users" in self._last_sql and "WHERE id = %s" in self._last_sql:
            return self.row
        return None


def test_change_password_for_user_rejects_invalid_current_password(monkeypatch):
    cur = _ChangePasswordCursor({"password_hash": "irrelevant"})
    monkeypatch.setattr(crud, "cursor", lambda: contextlib.nullcontext(cur))
    monkeypatch.setattr(crud, "_verify_password", lambda password, encoded: False)

    result = crud.change_password_for_user(
        user_id=1, current_password="bad", new_password="Str0ngPassw0rd!"
    )
    assert result == "current_password_invalid"


def test_change_password_for_user_updates_and_revokes_sessions(monkeypatch):
    cur = _ChangePasswordCursor({"password_hash": "irrelevant"})
    monkeypatch.setattr(crud, "cursor", lambda: contextlib.nullcontext(cur))
    verify_calls: list[str] = []

    def fake_verify(password, encoded):
        verify_calls.append(password)
        # Le mot de passe courant est valide, le nouveau est différent.
        return password == "current-pw-Str0ng!"

    monkeypatch.setattr(crud, "_verify_password", fake_verify)
    monkeypatch.setattr(
        crud, "_is_password_reused", lambda cur, user_id, password: False
    )
    revoked: list[int] = []
    monkeypatch.setattr(
        crud, "revoke_all_user_sessions", lambda cur, user_id: revoked.append(user_id)
    )

    result = crud.change_password_for_user(
        user_id=9, current_password="current-pw-Str0ng!", new_password="New-Str0ng!"
    )
    assert result == "updated"
    assert revoked == [9]
    assert any("INSERT INTO password_history" in sql for sql in cur.executed)


# ---------------------------------------------------------------------------
# get_user_id_from_token : comportement ACTUEL = mise à jour systématique
# ---------------------------------------------------------------------------


class _AuthTokenCursor:
    def __init__(self, row):
        self.row = row
        self.executed: list[str] = []
        self._last_sql = ""

    def execute(self, sql, params=()):
        self.executed.append(sql)
        self._last_sql = sql

    def fetchone(self):
        if "SELECT user_id" in self._last_sql and "FROM auth_tokens" in self._last_sql:
            return self.row
        return None


def test_get_user_id_from_token_always_updates_last_used_at_currently(monkeypatch):
    cur = _AuthTokenCursor({"user_id": 42})
    monkeypatch.setattr(crud, "cursor", lambda: contextlib.nullcontext(cur))

    assert crud.get_user_id_from_token("tok") == 42
    update_calls = [
        sql for sql in cur.executed if "UPDATE auth_tokens" in sql and "last_used_at" in sql
    ]
    # Comportement actuel (avant optimisation) : la mise à jour est
    # inconditionnelle, à chaque appel, même si last_used_at est récent.
    assert len(update_calls) == 1


def test_get_user_id_from_token_returns_none_without_update_when_token_missing(
    monkeypatch,
):
    cur = _AuthTokenCursor(None)
    monkeypatch.setattr(crud, "cursor", lambda: contextlib.nullcontext(cur))

    assert crud.get_user_id_from_token("missing") is None
    assert len(cur.executed) == 1  # seul le SELECT est exécuté
