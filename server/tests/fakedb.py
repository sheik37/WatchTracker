"""Petits doublures (fakes) de connexion/curseur psycopg2 pour les tests unitaires.

Ces objets imitent juste assez l'API utilisée par les modules crud (``execute``,
``fetchone``, ``fetchall``, ``rowcount``) pour permettre de caractériser le
comportement du code sans dépendre d'une vraie base PostgreSQL.
"""

from contextlib import contextmanager


class FakeCursor:
    """Curseur factice : empile les requêtes exécutées et rejoue des réponses.

    ``responses`` est une liste de callables ou de valeurs, consommée dans
    l'ordre à chaque ``execute`` ; chaque entrée sert de résultat pour le
    ``fetchone``/``fetchall`` qui suit.
    """

    def __init__(self, responses=None):
        self._responses = list(responses or [])
        self.calls: list[tuple[str, tuple]] = []
        self._current_result = None
        self.rowcount = 0

    def execute(self, sql, params=()):
        self.calls.append((sql, tuple(params) if params else ()))
        if self._responses:
            entry = self._responses.pop(0)
            if callable(entry):
                entry = entry(sql, params)
            if isinstance(entry, dict) and "rowcount" in entry:
                self.rowcount = entry.get("rowcount", 0)
                self._current_result = entry.get("row")
            else:
                self._current_result = entry
        else:
            self._current_result = None

    def fetchone(self):
        return self._current_result

    def fetchall(self):
        if self._current_result is None:
            return []
        return self._current_result

    @property
    def executed_sql(self) -> list[str]:
        return [sql for sql, _ in self.calls]

    def calls_matching(self, needle: str):
        return [(sql, params) for sql, params in self.calls if needle in sql]


def make_fake_cursor_factory(fake_cursor: FakeCursor):
    """Retourne un remplaçant pour ``db.cursor`` qui expose ``fake_cursor``."""

    @contextmanager
    def _fake_cursor():
        yield fake_cursor

    return _fake_cursor
