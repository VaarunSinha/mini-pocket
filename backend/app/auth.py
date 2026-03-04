"""HTTP Basic Auth: validate username/password against env with secrets.compare_digest()."""

import os
import secrets
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials

security = HTTPBasic(auto_error=True)


def get_current_username(
    credentials: Annotated[HTTPBasicCredentials, Depends(security)],
) -> str:
    """Validate Basic credentials against BASIC_AUTH_USERNAME and BASIC_AUTH_PASSWORD env vars."""
    expected_username = os.environ.get("BASIC_AUTH_USERNAME", "").strip()
    expected_password = os.environ.get("BASIC_AUTH_PASSWORD", "")

    if not expected_username:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Server auth not configured (BASIC_AUTH_USERNAME)",
            headers={"WWW-Authenticate": "Basic"},
        )

    username_bytes = credentials.username.encode("utf-8")
    password_bytes = credentials.password.encode("utf-8")
    correct_username_bytes = expected_username.encode("utf-8")
    correct_password_bytes = expected_password.encode("utf-8")

    if not (
        secrets.compare_digest(username_bytes, correct_username_bytes)
        and secrets.compare_digest(password_bytes, correct_password_bytes)
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username
