"""Endpoints d'authentification : inscription, connexion, rafraîchissement
de jeton, vérification d'email, réinitialisation/changement de mot de passe,
gestion du profil (``/auth/me``)."""

import html
import logging
from typing import Optional
from urllib import parse as urllib_parse

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPAuthorizationCredentials

import auth_crud
import auth_service
import email_service
import rate_limit_service
import user_crud
from deps import bearer_scheme, get_current_user_id
from password_errors import map_common_password_error
from schemas import (
    AuthChangePasswordIn,
    AuthForgotPasswordIn,
    AuthLoginIn,
    AuthLogoutIn,
    AuthMeOut,
    AuthMeUpdateIn,
    AuthRefreshIn,
    AuthRegisterIn,
    AuthRegisterOut,
    AuthResendVerificationIn,
    AuthResetPasswordIn,
    AuthTokenOut,
)

router = APIRouter()


@router.post("/auth/register", response_model=AuthRegisterOut, status_code=201)
async def auth_register(payload: AuthRegisterIn, request: Request) -> AuthRegisterOut:
    ip = auth_service._client_ip(request)
    email = payload.email.strip().lower()
    await rate_limit_service.enforce_auth_rate_limit("register", ip, email)

    try:
        user: Optional[dict] = None
        user = await run_in_threadpool(
            auth_crud.register_user, payload.email, payload.password
        )
        verification_token = await run_in_threadpool(
            auth_crud.create_email_verification_token, user["user_id"]
        )
        verify_link = f"{str(request.base_url).rstrip('/')}/auth/verify-email?token={verification_token}"
        await run_in_threadpool(
            email_service._send_verification_email, user["email"], verify_link
        )
    except ValueError as exc:
        delay, remaining_attempts, blocked_until, ip_failures, should_alert = (
            await rate_limit_service._register_auth_failure("register", ip, email)
        )
        auth_service._auth_log(
            logging.WARNING,
            "auth_register_failed",
            ip=ip,
            email=email,
            reason=str(exc),
            attempts_remaining=remaining_attempts,
            retry_after=(int(delay) + 1) if delay > 0 else 0,
            ip_failures=ip_failures,
        )
        if should_alert:
            auth_service._auth_log(
                logging.ERROR,
                "AUTH_ALERT",
                alert="repeated_auth_failures",
                ip=ip,
                endpoint="register",
                failures_in_window=ip_failures,
                window_seconds=rate_limit_service.AUTH_ALERT_WINDOW_SECONDS,
            )
        if str(exc) == "email_already_exists":
            raise HTTPException(
                status_code=409,
                detail="Email already exists",
                headers=rate_limit_service._rate_limit_headers(
                    remaining_attempts=remaining_attempts,
                    retry_after_seconds=delay if delay > 0 else None,
                    reset_epoch_seconds=blocked_until,
                ),
            )
        password_error = map_common_password_error(str(exc))
        if password_error is not None:
            raise password_error
        raise
    except Exception as exc:
        if user is not None and user.get("created_new"):
            await run_in_threadpool(auth_crud.delete_user_by_id, user["user_id"])
        if isinstance(exc, RuntimeError) and str(exc) == "email_daily_limit_reached":
            auth_service._auth_log(
                logging.ERROR,
                "email_quota_limit_reached",
                endpoint="register",
                ip=ip,
                email=email,
            )
            raise HTTPException(status_code=503, detail="Daily email limit reached")
        auth_service._auth_log(
            logging.ERROR,
            "auth_register_failed",
            ip=ip,
            email=email,
            reason="email_delivery_failed",
        )
        raise HTTPException(status_code=503, detail="Email delivery failed")
    await rate_limit_service._register_auth_success("register", ip, email)
    auth_service._auth_log(logging.INFO, "auth_register_success", ip=ip, email=email)
    return AuthRegisterOut(message="Verification email sent")


@router.post("/auth/login", response_model=AuthTokenOut)
async def auth_login(payload: AuthLoginIn, request: Request) -> AuthTokenOut:
    ip = auth_service._client_ip(request)
    email = payload.email.strip().lower()
    await rate_limit_service.enforce_auth_rate_limit("login", ip, email)

    try:
        user = await run_in_threadpool(
            auth_crud.authenticate_user, payload.email, payload.password
        )
    except ValueError as exc:
        if str(exc) == "email_not_verified":
            auth_service._auth_log(
                logging.WARNING,
                "auth_login_failed",
                ip=ip,
                email=email,
                reason="email_not_verified",
            )
            raise HTTPException(status_code=403, detail="Email not verified")
        raise
    if user is None:
        delay, remaining_attempts, blocked_until, ip_failures, should_alert = (
            await rate_limit_service._register_auth_failure("login", ip, email)
        )
        auth_service._auth_log(
            logging.WARNING,
            "auth_login_failed",
            ip=ip,
            email=email,
            reason="invalid_credentials",
            attempts_remaining=remaining_attempts,
            retry_after=(int(delay) + 1) if delay > 0 else 0,
            ip_failures=ip_failures,
        )
        if should_alert:
            auth_service._auth_log(
                logging.ERROR,
                "AUTH_ALERT",
                alert="repeated_auth_failures",
                ip=ip,
                endpoint="login",
                failures_in_window=ip_failures,
                window_seconds=rate_limit_service.AUTH_ALERT_WINDOW_SECONDS,
            )
        raise HTTPException(
            status_code=401,
            detail="Invalid credentials",
            headers=rate_limit_service._rate_limit_headers(
                remaining_attempts=remaining_attempts,
                retry_after_seconds=delay if delay > 0 else None,
                reset_epoch_seconds=blocked_until,
            ),
        )
    if auth_service._admin_2fa_required_for_email(email):
        if not auth_service.ADMIN_2FA_TOTP_SECRET:
            auth_service._auth_log(
                logging.ERROR,
                "auth_login_failed",
                ip=ip,
                email=email,
                reason="admin_2fa_misconfigured",
            )
            raise HTTPException(
                status_code=503,
                detail="Admin two-factor authentication is not configured",
            )
        otp_code = auth_service._clean_otp_code(payload.otp_code)
        if not auth_service._verify_admin_totp_code(otp_code):
            delay, remaining_attempts, blocked_until, ip_failures, should_alert = (
                await rate_limit_service._register_auth_failure("login", ip, email)
            )
            auth_service._auth_log(
                logging.WARNING,
                "auth_login_failed",
                ip=ip,
                email=email,
                reason="invalid_2fa_code",
                attempts_remaining=remaining_attempts,
                retry_after=(int(delay) + 1) if delay > 0 else 0,
                ip_failures=ip_failures,
            )
            if should_alert:
                auth_service._auth_log(
                    logging.ERROR,
                    "AUTH_ALERT",
                    alert="repeated_auth_failures",
                    ip=ip,
                    endpoint="login",
                    failures_in_window=ip_failures,
                    window_seconds=rate_limit_service.AUTH_ALERT_WINDOW_SECONDS,
                )
            detail = (
                "Two-factor code required"
                if not otp_code
                else "Invalid two-factor code"
            )
            raise HTTPException(
                status_code=401,
                detail=detail,
                headers=rate_limit_service._rate_limit_headers(
                    remaining_attempts=remaining_attempts,
                    retry_after_seconds=delay if delay > 0 else None,
                    reset_epoch_seconds=blocked_until,
                ),
            )
    token = await run_in_threadpool(
        auth_crud.issue_session_tokens_for_user, user["user_id"]
    )
    await rate_limit_service._register_auth_success("login", ip, email)
    auth_service._auth_log(logging.INFO, "auth_login_success", ip=ip, email=email)
    return AuthTokenOut(
        token=token["access_token"],
        access_token=token["access_token"],
        refresh_token=token["refresh_token"],
        expires_in_seconds=token["expires_in_seconds"],
    )


@router.post("/auth/refresh", response_model=AuthTokenOut)
async def auth_refresh(payload: AuthRefreshIn, request: Request) -> AuthTokenOut:
    ip = auth_service._client_ip(request)
    retry_after, reset_epoch = await rate_limit_service.auth_rate_limiter.get_retry_after(
        "refresh", ip
    )
    if retry_after > 0:
        raise HTTPException(
            status_code=429,
            detail="Too many attempts. Try again later.",
            headers=rate_limit_service._rate_limit_headers(
                retry_after_seconds=retry_after, reset_epoch_seconds=reset_epoch
            ),
        )
    token = await run_in_threadpool(auth_crud.rotate_refresh_token, payload.refresh_token)
    if token is None:
        _, _, blocked_until, _, _ = await rate_limit_service.auth_rate_limiter.register_failure(
            "refresh", ip
        )
        raise HTTPException(
            status_code=401,
            detail="Invalid refresh token",
            headers=rate_limit_service._rate_limit_headers(
                reset_epoch_seconds=blocked_until
            ),
        )
    await rate_limit_service.auth_rate_limiter.register_success("refresh", ip)
    return AuthTokenOut(
        token=token["access_token"],
        access_token=token["access_token"],
        refresh_token=token["refresh_token"],
        expires_in_seconds=token["expires_in_seconds"],
    )


@router.get("/auth/verify-email")
def auth_verify_email(token: str = Query(min_length=20)) -> dict[str, str]:
    if auth_crud.verify_email_token(token):
        return {"message": "Email verified. You can now log in."}
    raise HTTPException(status_code=400, detail="Invalid or expired verification token")


@router.post("/auth/resend-verification", response_model=AuthRegisterOut, status_code=202)
async def auth_resend_verification(
    payload: AuthResendVerificationIn, request: Request
) -> AuthRegisterOut:
    ip = auth_service._client_ip(request)
    email = payload.email.strip().lower()
    await rate_limit_service.enforce_auth_rate_limit("resend_verification", ip, email)

    row = await run_in_threadpool(auth_crud.create_verification_token_for_email, email)
    if row is not None:
        verify_link = f"{str(request.base_url).rstrip('/')}/auth/verify-email?token={row['token']}"
        try:
            await run_in_threadpool(
                email_service._send_verification_email, row["email"], verify_link
            )
        except Exception as exc:
            if (
                isinstance(exc, RuntimeError)
                and str(exc) == "email_daily_limit_reached"
            ):
                auth_service._auth_log(
                    logging.ERROR,
                    "email_quota_limit_reached",
                    endpoint="resend_verification",
                    ip=ip,
                    email=email,
                )
            else:
                auth_service._auth_log(
                    logging.ERROR,
                    "auth_resend_verification_failed",
                    ip=ip,
                    email=email,
                    reason="email_delivery_failed",
                )
    await rate_limit_service._register_auth_failure("resend_verification", ip, email)
    return AuthRegisterOut(
        message=(
            "Si un compte non vérifié existe pour cet email, "
            "un nouvel email de vérification a été envoyé."
        )
    )


@router.post("/auth/forgot-password", response_model=AuthRegisterOut, status_code=202)
async def auth_forgot_password(
    payload: AuthForgotPasswordIn, request: Request
) -> AuthRegisterOut:
    ip = auth_service._client_ip(request)
    email = payload.email.strip().lower()
    await rate_limit_service.enforce_auth_rate_limit("forgot_password", ip, email)

    row = await run_in_threadpool(
        auth_crud.create_password_reset_token_for_email, email
    )
    if row is not None:
        try:
            reset_link = email_service._build_password_reset_link(request, row["token"])
            await run_in_threadpool(
                email_service._send_password_reset_email, row["email"], reset_link
            )
        except Exception as exc:
            if (
                isinstance(exc, RuntimeError)
                and str(exc) == "email_daily_limit_reached"
            ):
                auth_service._auth_log(
                    logging.ERROR,
                    "email_quota_limit_reached",
                    endpoint="forgot_password",
                    ip=ip,
                    email=email,
                )
            else:
                auth_service._auth_log(
                    logging.ERROR,
                    "auth_forgot_password_failed",
                    ip=ip,
                    email=email,
                    reason="email_delivery_failed",
                )
    await rate_limit_service._register_auth_failure("forgot_password", ip, email)
    return AuthRegisterOut(
        message="Si un compte existe pour cet email, un email de réinitialisation a été envoyé."
    )


def _render_reset_password_page(
    token: str, message: Optional[str] = None, is_error: bool = False
) -> str:
    escaped_token = html.escape(token, quote=True)
    escaped_message = html.escape(message, quote=True) if message else ""
    message_style = "color:#b91c1c;" if is_error else "color:#166534;"
    message_html = (
        f'<p style="{message_style}">{escaped_message}</p>' if message else ""
    )
    return f"""<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Réinitialiser le mot de passe</title>
</head>
<body>
  <main>
    <h1>Réinitialiser ton mot de passe</h1>
    {message_html}
    <form method="post" action="/auth/reset-password/confirm">
      <input type="hidden" name="token" value="{escaped_token}" />
      <label for="password">Nouveau mot de passe</label><br />
      <input id="password" name="password" type="password" minlength="10" maxlength="128" required /><br /><br />
      <label for="confirm_password">Confirmer le mot de passe</label><br />
      <input id="confirm_password" name="confirm_password" type="password" minlength="10" maxlength="128" required /><br /><br />
      <button type="submit">Mettre à jour le mot de passe</button>
    </form>
  </main>
</body>
</html>"""


def _render_reset_password_success_page(message: str) -> str:
    escaped_message = html.escape(message, quote=True)
    return f"""<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Mot de passe mis à jour</title>
</head>
<body>
  <main>
    <h1>Mot de passe mis à jour</h1>
    <p style="color:#166534;">{escaped_message}</p>
  </main>
</body>
</html>"""


@router.get("/auth/reset-password", response_class=HTMLResponse)
def auth_reset_password_page(token: str = Query(min_length=20)) -> str:
    return _render_reset_password_page(token)


@router.post("/auth/reset-password/confirm", response_class=HTMLResponse)
async def auth_reset_password_confirm(request: Request) -> HTMLResponse:
    raw_body = await request.body()
    form_data = urllib_parse.parse_qs(raw_body.decode("utf-8"), keep_blank_values=True)
    token = form_data.get("token", [""])[0]
    password = form_data.get("password", [""])[0]
    confirm_password = form_data.get("confirm_password", [""])[0]

    if len(token) < 20:
        return HTMLResponse(
            _render_reset_password_page("", "Lien invalide ou expiré.", is_error=True),
            status_code=400,
        )
    if len(password) < 10 or len(password) > 128:
        return HTMLResponse(
            _render_reset_password_page(
                token,
                "Le mot de passe doit contenir entre 10 et 128 caractères.",
                is_error=True,
            ),
            status_code=400,
        )
    if len(confirm_password) < 10 or len(confirm_password) > 128:
        return HTMLResponse(
            _render_reset_password_page(
                token,
                "Le mot de passe doit contenir entre 10 et 128 caractères.",
                is_error=True,
            ),
            status_code=400,
        )
    if password != confirm_password:
        return HTMLResponse(
            _render_reset_password_page(
                token, "Les mots de passe ne correspondent pas.", is_error=True
            ),
            status_code=400,
        )
    reset_result = auth_crud.reset_password_with_token(token, password)
    if reset_result == "password_too_short":
        return HTMLResponse(
            _render_reset_password_page(
                token,
                "Le mot de passe doit contenir au moins 10 caractères.",
                is_error=True,
            ),
            status_code=400,
        )
    if reset_result == "password_too_weak":
        return HTMLResponse(
            _render_reset_password_page(
                token,
                "Le mot de passe doit inclure minuscule, majuscule, chiffre et symbole.",
                is_error=True,
            ),
            status_code=400,
        )
    if reset_result == "same_as_current":
        auth_service._auth_log(
            logging.WARNING,
            "auth_reset_password_blocked",
            reason="same_as_current_password",
        )
        return HTMLResponse(
            _render_reset_password_page(
                token,
                "Le nouveau mot de passe doit être différent de l'actuel.",
                is_error=True,
            ),
            status_code=400,
        )
    if reset_result == "password_reused":
        auth_service._auth_log(
            logging.WARNING, "auth_reset_password_blocked", reason="password_reused"
        )
        return HTMLResponse(
            _render_reset_password_page(
                token, "Ce mot de passe a déjà été utilisé récemment.", is_error=True
            ),
            status_code=400,
        )
    if reset_result != "updated":
        return HTMLResponse(
            _render_reset_password_page(
                token, "Lien invalide ou expiré.", is_error=True
            ),
            status_code=400,
        )
    return HTMLResponse(
        _render_reset_password_success_page("Tu peux maintenant te connecter."),
        status_code=200,
    )


@router.post("/auth/reset-password", response_model=AuthRegisterOut)
def auth_reset_password(payload: AuthResetPasswordIn) -> AuthRegisterOut:
    reset_result = auth_crud.reset_password_with_token(payload.token, payload.password)
    password_error = map_common_password_error(reset_result)
    if password_error is not None:
        raise password_error
    if reset_result == "same_as_current":
        auth_service._auth_log(
            logging.WARNING,
            "auth_reset_password_blocked",
            reason="same_as_current_password",
        )
        raise HTTPException(
            status_code=400,
            detail="New password must be different from current password",
        )
    if reset_result != "updated":
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")
    return AuthRegisterOut(message="Password has been reset. You can now log in.")


@router.post("/auth/logout", status_code=204)
def auth_logout(
    payload: Optional[AuthLogoutIn] = None,
    user_id: int = Depends(get_current_user_id),
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> None:
    _ = user_id
    if credentials is None:
        raise HTTPException(status_code=401, detail="Missing bearer token")
    if not auth_crud.revoke_auth_token(credentials.credentials):
        auth_service._auth_log(
            logging.WARNING,
            "auth_logout_failed",
            user_id=user_id,
            reason="invalid_token",
        )
        raise HTTPException(status_code=401, detail="Invalid token")
    if payload is not None and payload.refresh_token:
        auth_crud.revoke_refresh_token(payload.refresh_token)
    auth_service._auth_log(logging.INFO, "auth_logout_success", user_id=user_id)


@router.get("/auth/me", response_model=AuthMeOut)
def auth_me(user_id: int = Depends(get_current_user_id)) -> AuthMeOut:
    profile = user_crud.get_user_profile(user_id)
    if profile is None:
        raise HTTPException(status_code=404, detail="User not found")
    return AuthMeOut(**profile)


@router.patch("/auth/me", response_model=AuthMeOut)
def auth_me_update(
    payload: AuthMeUpdateIn, user_id: int = Depends(get_current_user_id)
) -> AuthMeOut:
    profile = user_crud.update_user_display_name(user_id, payload.display_name)
    if profile is None:
        raise HTTPException(status_code=404, detail="User not found")
    return AuthMeOut(**profile)


@router.delete("/auth/me", response_model=AuthRegisterOut)
def auth_me_delete(user_id: int = Depends(get_current_user_id)) -> AuthRegisterOut:
    auth_crud.delete_user_by_id(user_id)
    auth_service._auth_log(logging.INFO, "auth_account_deleted", user_id=user_id)
    return AuthRegisterOut(message="Account deleted")


@router.post("/auth/change-password", response_model=AuthRegisterOut)
def auth_change_password(
    payload: AuthChangePasswordIn, user_id: int = Depends(get_current_user_id)
) -> AuthRegisterOut:
    result = auth_crud.change_password_for_user(
        user_id=user_id,
        current_password=payload.current_password,
        new_password=payload.new_password,
    )
    if result == "current_password_invalid":
        raise HTTPException(status_code=400, detail="Current password is invalid")
    password_error = map_common_password_error(result)
    if password_error is not None:
        raise password_error
    if result == "same_as_current":
        raise HTTPException(
            status_code=400,
            detail="New password must be different from current password",
        )
    if result == "user_not_found":
        raise HTTPException(status_code=404, detail="User not found")
    return AuthRegisterOut(message="Password updated")
