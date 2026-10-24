"""Mapping commun des codes d'erreur de politique de mot de passe retournés
par ``auth_crud`` (register, reset-password, change-password) vers des
``HTTPException`` FastAPI, pour éviter la duplication entre endpoints.
"""

from typing import Optional

from fastapi import HTTPException


def map_common_password_error(result: str) -> Optional[HTTPException]:
    """Retourne l'exception correspondante pour les codes partagés par
    plusieurs endpoints, ou ``None`` si le code n'est pas générique."""
    if result == "password_too_short":
        return HTTPException(
            status_code=400, detail="Password must contain at least 10 characters"
        )
    if result == "password_too_weak":
        return HTTPException(
            status_code=400,
            detail="Password must include lower, upper, digit, and symbol",
        )
    if result == "password_reused":
        return HTTPException(
            status_code=400, detail="Password was already used recently"
        )
    return None
