"""Accès base de données pour le profil utilisateur (hors authentification)."""

from typing import Any, Optional

from db import cursor


def get_user_profile(user_id: int) -> Optional[dict[str, Any]]:
    with cursor() as cur:
        cur.execute(
            """
            SELECT id, username, display_name
            FROM users
            WHERE id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        return {
            "user_id": row["id"],
            "email": row["username"],
            "display_name": row["display_name"],
        }


def update_user_display_name(
    user_id: int, display_name: Optional[str]
) -> Optional[dict[str, Any]]:
    normalized_display_name = (
        display_name.strip() if isinstance(display_name, str) else None
    )
    if normalized_display_name == "":
        normalized_display_name = None
    with cursor() as cur:
        cur.execute(
            """
            UPDATE users
            SET display_name = %s
            WHERE id = %s
            RETURNING id, username, display_name
            """,
            (normalized_display_name, user_id),
        )
        row = cur.fetchone()
        if row is None:
            return None
        return {
            "user_id": row["id"],
            "email": row["username"],
            "display_name": row["display_name"],
        }
