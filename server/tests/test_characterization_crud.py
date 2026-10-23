"""Tests de caractérisation : figent le comportement ACTUEL de crud.py avant
le refactor (découpage en modules, optimisation des requêtes groupées, etc.).

Ces tests n'utilisent pas de vraie base PostgreSQL (aucune instance n'est
disponible dans cet environnement) : ils remplacent ``cursor()`` par de
petites doublures qui enregistrent les requêtes SQL exécutées, à l'image de
``tests/test_crud.py`` existant.
"""

import contextlib
from datetime import datetime, timedelta, timezone

import auth_crud
import episode_crud
from schemas import EpisodeProgressItemIn


# ---------------------------------------------------------------------------
# replace_episode_progress / rewatch_episode_season : requêtes SQL groupées
# (optimisation étape 4, remplace la boucle "une requête par épisode").
# ---------------------------------------------------------------------------


class _EpisodeBatchCursor:
    """Curseur factice générique : compte les requêtes, sans logique métier."""

    def __init__(self, existing_rows=None):
        self.executed: list[str] = []
        self.params: list[tuple] = []
        self._last_sql = ""
        self._existing_rows = existing_rows or []

    def execute(self, sql, params=()):
        self.executed.append(sql)
        self.params.append(params)
        self._last_sql = sql

    def fetchone(self):
        return None

    def fetchall(self):
        if "SELECT season_number, episode_number, is_watched, updated_at" in self._last_sql:
            return self._existing_rows
        return []


def test_replace_episode_progress_issues_grouped_queries_not_one_per_episode(
    monkeypatch,
):
    cur = _EpisodeBatchCursor()
    monkeypatch.setattr(episode_crud, "cursor", lambda: contextlib.nullcontext(cur))

    items = [
        EpisodeProgressItemIn(season_number=1, episode_number=1, is_watched=True),
        EpisodeProgressItemIn(season_number=1, episode_number=2, is_watched=True),
        EpisodeProgressItemIn(season_number=1, episode_number=3, is_watched=False),
    ]
    episode_crud.replace_episode_progress(user_id=1, media_id=99, items=items)

    # Optimisation (étape 4) : les items "watched" sont traités en un seul lot
    # (1 SELECT FOR UPDATE + 1 INSERT watch_events + 1 DELETE tombstones + 1
    # UPSERT progress = 4 requêtes pour les 2 épisodes) et les items
    # "unwatched" en un seul lot (1 DELETE watch_events + 1 UPSERT progress =
    # 2 requêtes pour 1 épisode), peu importe le nombre d'épisodes : plus
    # aucune requête par épisode.
    assert len(cur.executed) == 4 + 2


def test_replace_episode_progress_noop_without_db_access_when_no_items(monkeypatch):
    def boom():
        raise AssertionError("cursor() ne doit pas être ouvert si items est vide")

    monkeypatch.setattr(episode_crud, "cursor", lambda: boom())
    episode_crud.replace_episode_progress(user_id=1, media_id=99, items=[])


def test_replace_episode_progress_last_write_wins_on_duplicate_keys(monkeypatch):
    calls: list[tuple[str, list]] = []

    def fake_watched_batch(cur, *, user_id, media_id, keys, allow_rewatch, watched_at=None):
        calls.append(("watched", list(keys)))

    def fake_unwatched_batch(cur, *, user_id, media_id, keys):
        calls.append(("unwatched", list(keys)))

    monkeypatch.setattr(episode_crud, "_set_episodes_watched_batch", fake_watched_batch)
    monkeypatch.setattr(episode_crud, "_set_episodes_unwatched_batch", fake_unwatched_batch)
    monkeypatch.setattr(episode_crud, "cursor", lambda: contextlib.nullcontext(object()))

    items = [
        EpisodeProgressItemIn(season_number=1, episode_number=1, is_watched=True),
        EpisodeProgressItemIn(season_number=1, episode_number=1, is_watched=False),
    ]
    episode_crud.replace_episode_progress(user_id=1, media_id=99, items=items)

    # La dernière entrée du payload pour une clé (saison, épisode) donnée
    # l'emporte, comme le ferait une boucle séquentielle écrasant la ligne.
    assert calls == [("unwatched", [(1, 1)])]


def test_rewatch_episode_season_dedupes_sorts_and_batches_single_call(monkeypatch):
    calls: list[list[tuple[int, int]]] = []

    def fake_set_watched_batch(
        cur, *, user_id, media_id, keys, allow_rewatch, watched_at=None,
    ):
        calls.append(list(keys))

    monkeypatch.setattr(episode_crud, "_set_episodes_watched_batch", fake_set_watched_batch)
    monkeypatch.setattr(episode_crud, "cursor", lambda: contextlib.nullcontext(object()))

    episode_crud.rewatch_episode_season(
        user_id=1, media_id=5, season_number=2, episode_numbers=[3, 1, 3, 0, 2]
    )

    # Comportement : dédoublonnage + tri croissant, puis un seul appel groupé
    # (0 est ignoré) au lieu d'une boucle par épisode.
    assert calls == [[(2, 1), (2, 2), (2, 3)]]


def test_rewatch_episode_season_noop_without_db_access_when_all_invalid(monkeypatch):
    def boom():
        raise AssertionError("cursor() ne doit pas être ouvert sans épisode valide")

    monkeypatch.setattr(episode_crud, "cursor", lambda: boom())
    episode_crud.rewatch_episode_season(
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
    monkeypatch.setattr(auth_crud, "cursor", lambda: contextlib.nullcontext(cur))

    assert auth_crud.verify_email_token("sometoken") is True
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
    monkeypatch.setattr(auth_crud, "cursor", lambda: contextlib.nullcontext(cur))

    assert auth_crud.verify_email_token("bad-token") is False
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

    monkeypatch.setattr(auth_crud, "cursor", lambda: boom())
    assert auth_crud.reset_password_with_token("tok", "short") == "password_too_short"


def test_reset_password_with_token_rejects_same_as_current(monkeypatch):
    cur = _ResetPasswordCursor({"user_id": 3, "password_hash": "irrelevant"})
    monkeypatch.setattr(auth_crud, "cursor", lambda: contextlib.nullcontext(cur))
    monkeypatch.setattr(auth_crud, "_verify_password", lambda password, encoded: True)

    result = auth_crud.reset_password_with_token("tok", "Str0ngPassw0rd!")
    assert result == "same_as_current"
    assert len(cur.executed) == 1  # pas de mutation si mdp identique


def test_reset_password_with_token_rejects_reused_password(monkeypatch):
    cur = _ResetPasswordCursor({"user_id": 3, "password_hash": "irrelevant"})
    monkeypatch.setattr(auth_crud, "cursor", lambda: contextlib.nullcontext(cur))
    monkeypatch.setattr(auth_crud, "_verify_password", lambda password, encoded: False)
    monkeypatch.setattr(auth_crud, "_is_password_reused", lambda cur, user_id, password: True
    )

    assert auth_crud.reset_password_with_token("tok", "Str0ngPassw0rd!") == "password_reused"


def test_reset_password_with_token_updates_and_revokes_sessions(monkeypatch):
    cur = _ResetPasswordCursor({"user_id": 3, "password_hash": "irrelevant"})
    monkeypatch.setattr(auth_crud, "cursor", lambda: contextlib.nullcontext(cur))
    monkeypatch.setattr(auth_crud, "_verify_password", lambda password, encoded: False)
    monkeypatch.setattr(auth_crud, "_is_password_reused", lambda cur, user_id, password: False
    )
    revoked: list[int] = []
    monkeypatch.setattr(auth_crud, "revoke_all_user_sessions", lambda cur, user_id: revoked.append(user_id)
    )

    result = auth_crud.reset_password_with_token("tok", "Str0ngPassw0rd!")
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
    monkeypatch.setattr(auth_crud, "cursor", lambda: contextlib.nullcontext(cur))
    monkeypatch.setattr(auth_crud, "_verify_password", lambda password, encoded: False)

    result = auth_crud.change_password_for_user(
        user_id=1, current_password="bad", new_password="Str0ngPassw0rd!"
    )
    assert result == "current_password_invalid"


def test_change_password_for_user_updates_and_revokes_sessions(monkeypatch):
    cur = _ChangePasswordCursor({"password_hash": "irrelevant"})
    monkeypatch.setattr(auth_crud, "cursor", lambda: contextlib.nullcontext(cur))
    verify_calls: list[str] = []

    def fake_verify(password, encoded):
        verify_calls.append(password)
        # Le mot de passe courant est valide, le nouveau est différent.
        return password == "current-pw-Str0ng!"

    monkeypatch.setattr(auth_crud, "_verify_password", fake_verify)
    monkeypatch.setattr(auth_crud, "_is_password_reused", lambda cur, user_id, password: False
    )
    revoked: list[int] = []
    monkeypatch.setattr(auth_crud, "revoke_all_user_sessions", lambda cur, user_id: revoked.append(user_id)
    )

    result = auth_crud.change_password_for_user(
        user_id=9, current_password="current-pw-Str0ng!", new_password="New-Str0ng!"
    )
    assert result == "updated"
    assert revoked == [9]
    assert any("INSERT INTO password_history" in sql for sql in cur.executed)


# ---------------------------------------------------------------------------
# get_user_id_from_token : mise à jour de last_used_at limitée dans le temps
# (optimisation perf, étape 4) : la ligne n'est réécrite que si la dernière
# mise à jour date de plus de 5 minutes.
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


def test_get_user_id_from_token_updates_last_used_at_when_missing(monkeypatch):
    cur = _AuthTokenCursor({"user_id": 42, "last_used_at": None})
    monkeypatch.setattr(auth_crud, "cursor", lambda: contextlib.nullcontext(cur))

    assert auth_crud.get_user_id_from_token("tok") == 42
    update_calls = [
        sql for sql in cur.executed if "UPDATE auth_tokens" in sql and "last_used_at" in sql
    ]
    assert len(update_calls) == 1


def test_get_user_id_from_token_skips_update_when_recently_used(monkeypatch):
    cur = _AuthTokenCursor(
        {"user_id": 42, "last_used_at": datetime.now(timezone.utc)}
    )
    monkeypatch.setattr(auth_crud, "cursor", lambda: contextlib.nullcontext(cur))

    assert auth_crud.get_user_id_from_token("tok") == 42
    update_calls = [
        sql for sql in cur.executed if "UPDATE auth_tokens" in sql and "last_used_at" in sql
    ]
    # Optimisation : pas d'écriture si last_used_at date de moins de 5 min.
    assert update_calls == []
    assert len(cur.executed) == 1  # seul le SELECT est exécuté


def test_get_user_id_from_token_updates_when_last_used_is_old(monkeypatch):
    stale = datetime.now(timezone.utc) - timedelta(minutes=10)
    cur = _AuthTokenCursor({"user_id": 42, "last_used_at": stale})
    monkeypatch.setattr(auth_crud, "cursor", lambda: contextlib.nullcontext(cur))

    assert auth_crud.get_user_id_from_token("tok") == 42
    update_calls = [
        sql for sql in cur.executed if "UPDATE auth_tokens" in sql and "last_used_at" in sql
    ]
    assert len(update_calls) == 1


def test_get_user_id_from_token_returns_none_without_update_when_token_missing(
    monkeypatch,
):
    cur = _AuthTokenCursor(None)
    monkeypatch.setattr(auth_crud, "cursor", lambda: contextlib.nullcontext(cur))

    assert auth_crud.get_user_id_from_token("missing") is None
    assert len(cur.executed) == 1  # seul le SELECT est exécuté
