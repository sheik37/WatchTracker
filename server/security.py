"""Hash et vérification des mots de passe.

Module partagé par ``db.py`` (bootstrap du compte admin) et ``crud.py``
(inscription, connexion, changement de mot de passe) afin d'éviter la
duplication de la logique PBKDF2-SHA256.
"""

import hashlib
import hmac
import secrets

PBKDF2_ROUNDS = 150_000


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt.encode("utf-8"), PBKDF2_ROUNDS
    ).hex()
    return f"pbkdf2_sha256${PBKDF2_ROUNDS}${salt}${digest}"


def verify_password(password: str, encoded: str) -> bool:
    try:
        algo, rounds_text, salt, digest = encoded.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        rounds = int(rounds_text)
    except (TypeError, ValueError):
        return False
    check = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt.encode("utf-8"), rounds
    ).hex()
    return hmac.compare_digest(check, digest)
