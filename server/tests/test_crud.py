from datetime import datetime, timezone

import episode_crud


def test_set_episodes_watched_batch_preserves_new_first_watch_timestamp():
    watched_at = datetime(2026, 9, 9, 0, 0, tzinfo=timezone.utc)
    row = {
        "season_number": 2,
        "episode_number": 7,
        "is_watched": False,
        "updated_at": datetime(2026, 9, 1, 0, 0, tzinfo=timezone.utc),
    }
    cursor = _FakeCursor(row)

    episode_crud._set_episodes_watched_batch(
        cursor,
        user_id=1,
        media_id=42,
        keys=[(2, 7)],
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
        self._fetchall_result = []

    def execute(self, sql, params):
        self.calls.append((sql, params))
        if "SELECT season_number, episode_number, is_watched, updated_at" in sql:
            self._fetchall_result = [self.row] if self.row else []

    def fetchone(self):
        return None

    def fetchall(self):
        return self._fetchall_result
