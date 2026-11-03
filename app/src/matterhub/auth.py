"""Authentication and role-based access control with Microsoft Entra ID.

Callers present an OAuth 2.0 access token issued by Entra ID for this API's app
registration. The token signature is checked against the tenant's published JWKS,
and the ``roles`` claim (Entra ID app roles) drives authorisation:

* ``Matters.Read``  - read matters and audit history
* ``Matters.Write`` - create and update matters
* ``Matters.Admin`` - implies all of the above
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Annotated, Any, Protocol

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

logger = logging.getLogger(__name__)


class Roles:
    READ = "Matters.Read"
    WRITE = "Matters.Write"
    ADMIN = "Matters.Admin"


@dataclass(frozen=True)
class Principal:
    subject: str
    name: str
    roles: frozenset[str]


# Used only when auth_mode=disabled, which config.py forbids in staging/prod.
LOCAL_DEV_PRINCIPAL = Principal(
    subject="local-developer",
    name="local-developer",
    roles=frozenset({Roles.ADMIN}),
)


class SigningKeySource(Protocol):
    def get_signing_key_from_jwt(self, token: str) -> Any: ...


class TokenValidator:
    def __init__(
        self,
        tenant_id: str,
        audience: str,
        jwks_client: SigningKeySource | None = None,
    ) -> None:
        self.issuer = f"https://login.microsoftonline.com/{tenant_id}/v2.0"
        self.audience = audience
        self._jwks: SigningKeySource = jwks_client or jwt.PyJWKClient(
            f"https://login.microsoftonline.com/{tenant_id}/discovery/v2.0/keys",
            cache_keys=True,
            lifespan=3600,
        )

    def validate(self, token: str) -> Principal:
        signing_key = self._jwks.get_signing_key_from_jwt(token)
        claims: dict[str, Any] = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],  # never accept "none" or HS* for Entra tokens
            audience=self.audience,
            issuer=self.issuer,
            options={"require": ["exp", "iat", "aud", "iss", "sub"]},
            leeway=30,
        )
        subject = str(claims.get("oid") or claims["sub"])
        name = str(claims.get("preferred_username") or claims.get("azp") or subject)
        roles = frozenset(str(r) for r in claims.get("roles", []))
        return Principal(subject=subject, name=name, roles=roles)


_bearer = HTTPBearer(auto_error=False)


def _unauthorised(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_principal(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> Principal:
    settings = request.app.state.settings
    if settings.auth_mode == "disabled":
        principal = LOCAL_DEV_PRINCIPAL
    else:
        if credentials is None:
            raise _unauthorised("Missing bearer token")
        validator: TokenValidator = request.app.state.token_validator
        try:
            principal = validator.validate(credentials.credentials)
        except jwt.PyJWTError as exc:
            # Log the reason for operators, but never echo it to the caller.
            logger.warning("token_rejected", extra={"reason": type(exc).__name__})
            raise _unauthorised("Invalid token") from exc
    request.state.principal = principal
    return principal


def require_role(*accepted: str) -> Any:
    """Dependency factory: allow the request if the caller holds any accepted role."""

    def dependency(principal: Annotated[Principal, Depends(get_principal)]) -> Principal:
        if Roles.ADMIN in principal.roles or principal.roles.intersection(accepted):
            return principal
        logger.warning(
            "access_denied",
            extra={"principal": principal.subject, "required_roles": sorted(accepted)},
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")

    return dependency


CanRead = Annotated[Principal, Depends(require_role(Roles.READ, Roles.WRITE))]
CanWrite = Annotated[Principal, Depends(require_role(Roles.WRITE))]
