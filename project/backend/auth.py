"""
auth.py — validate a Supabase JWT and return the user id.

Supabase's newer projects sign access tokens with asymmetric keys (ES256).
We verify against the project's public JWKS (cached), so no shared secret needed.
"""
import os
import time
import urllib.request
import json
from fastapi import Header, HTTPException
from jose import jwt, JWTError

_JWKS = None
_JWKS_AT = 0.0
_JWKS_TTL = 3600  # refresh hourly; keys rotate rarely


def _jwks() -> dict:
    global _JWKS, _JWKS_AT
    if _JWKS is None or time.time() - _JWKS_AT > _JWKS_TTL:
        url = os.environ["SUPABASE_URL"].rstrip("/") + "/auth/v1/.well-known/jwks.json"
        with urllib.request.urlopen(url, timeout=10) as r:
            _JWKS = json.load(r)
        _JWKS_AT = time.time()
    return _JWKS


def current_user(authorization: str = Header(...)) -> str:
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "missing bearer token")
    token = authorization[7:]
    try:
        kid = jwt.get_unverified_header(token)["kid"]
        key = next(k for k in _jwks()["keys"] if k["kid"] == kid)
        claims = jwt.decode(
            token, key,
            algorithms=[key.get("alg", "ES256")],
            audience="authenticated",
        )
    except (JWTError, StopIteration, KeyError) as e:
        raise HTTPException(401, f"invalid token: {e}")
    return claims["sub"]
