from datetime import datetime, timezone

import crud as crud_module


def test_set_episode_watched_preserves_new_first_watch_timestamp():
    watched_at = datetime(2026, 9, 9, 0, 0, tzinfo=timezone.utc)
    row = {
        "is_watched": False,
        "updated_at": datetime(2026, 9, 1, 0, 0, tzinfo=timezone.utc),
    }
    cursor = _FakeCursor(row)

    crud_module._set_episode_watched(
        cursor,
        user_id=1,
        media_id=42,
        season_number=2,
        episode_number=7,
        allow_rewatch=False,
        watched_at=watched_at,
    )

    upsert_sql, upsert_params = cursor.calls[-1]
    assert "ELSE EXCLUDED.updated_at" in upsert_sql
    assert upsert_params[-1] == watched_at


class _FakeCursor:
    def __init__(self, row):
        self.row = row
        self.calls = []
        self._fetchone_result = None

    def execute(self, sql, params):
        self.calls.append((sql, params))
        if "SELECT is_watched, updated_at, sync_updated_at" in sql:
            self._fetchone_result = self.row

    def fetchone(self):
        return self._fetchone_result
