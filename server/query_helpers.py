"""Petits utilitaires partagés pour la construction de requêtes SQL.

Factorise la clause de filtre temporel ``*_since`` dupliquée entre les
fonctions de listing de watchlist_crud.py et episode_crud.py (watchlist,
progression épisode, tombstones).
"""

from datetime import datetime
from typing import Any, Optional


def since_clause(column: str, since: Optional[datetime], params: list[Any]) -> str:
    """Retourne (et ajoute aux ``params``) la clause SQL ``AND <column> > %s``
    si ``since`` est fourni, sinon une chaîne vide. ``params`` est modifiée
    en place pour rester dans l'ordre positionnel attendu par psycopg2.
    """
    if since is None:
        return ""
    params.append(since)
    return f" AND {column} > %s"
