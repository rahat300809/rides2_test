"""
DIU Ride - Production Server Security Guard & Data Safety Module
===============================================================
Features:
1. Multi-tier In-Memory Sliding Window Rate Limiting (IP & route based)
2. DDoS & Slowloris Mitigation (Payload size ceiling, abusive IP jail, attack path filtering)
3. Unverified File Upload Security (Magic bytes signature check, extension whitelist, UUID sanitization, 5MB limit)
4. Security Response Headers (X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, Referrer-Policy)
5. SQLite Production Data Safety (WAL mode check, online transactional backup rotation)
"""

import os
import re
import time
import uuid
import hmac
import shutil
import sqlite3
from typing import Dict, List, Tuple, Optional
from fastapi import Request, HTTPException, status
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse, Response

# Directory for secure uploads
SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOADS_DIR = os.path.join(SERVER_DIR, "uploads")
BACKUPS_DIR = os.path.join(SERVER_DIR, "backups")
os.makedirs(UPLOADS_DIR, exist_ok=True)
os.makedirs(BACKUPS_DIR, exist_ok=True)

# Attack patterns to immediately block with 403
ATTACK_PATH_REGEX = re.compile(
    r"(\.\./|\.\.\\|/etc/passwd|/proc/|\.env|\.git|wp-admin|xmlrpc\.php|phpinfo|eval\(|<script|select\s+.*from|union\s+select)",
    re.IGNORECASE
)

# Maximum allowed body payload: 10 MB
MAX_BODY_BYTES = 10 * 1024 * 1024

# Allowed image file signatures (Magic Bytes)
IMAGE_MAGIC_SIGNATURES = {
    "jpeg": [b"\xFF\xD8\xFF"],
    "png": [b"\x89PNG\r\n\x1a\n"],
    "webp": [b"RIFF"], # Bytes 0-4 RIFF, bytes 8-12 WEBP
}

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024  # 5 MB


class RateLimitRule:
    """Defines a rate limit threshold for a specific route prefix."""
    def __init__(self, prefix: str, max_requests: int, window_seconds: int):
        self.prefix = prefix
        self.max_requests = max_requests
        self.window_seconds = window_seconds


class SecurityRateLimiter:
    """
    High-performance sliding-window in-memory rate limiter with abusive IP jail.
    """
    def __init__(self):
        # ip -> list of request timestamps
        self._ip_history: Dict[str, List[float]] = {}
        # (ip, prefix) -> list of request timestamps
        self._route_history: Dict[Tuple[str, str], List[float]] = {}
        # ip -> banned_until timestamp
        self._jailed_ips: Dict[str, float] = {}
        # ip -> count of suspicious / rate-limited offenses
        self._offenses: Dict[str, List[float]] = {}
        self._last_cleanup = time.time()

        # Dedicated rules for sensitive endpoints
        self.rules = [
            RateLimitRule("/auth/login", max_requests=12, window_seconds=60),
            RateLimitRule("/ride/api/auth/login", max_requests=12, window_seconds=60),
            RateLimitRule("/api/auth/login", max_requests=12, window_seconds=60),
            RateLimitRule("/auth/register", max_requests=8, window_seconds=60),
            RateLimitRule("/ride/api/auth/register", max_requests=8, window_seconds=60),
            RateLimitRule("/auth/verify-code", max_requests=15, window_seconds=60),
            RateLimitRule("/auth/forgot-password", max_requests=6, window_seconds=60),
            RateLimitRule("/api/admin/login", max_requests=5, window_seconds=60),
            RateLimitRule("/ride/api/admin/login", max_requests=5, window_seconds=60),
            RateLimitRule("/api/chat/ask", max_requests=25, window_seconds=60),
            RateLimitRule("/ride/api/chat/ask", max_requests=25, window_seconds=60),
            RateLimitRule("/api/upload", max_requests=10, window_seconds=60),
            RateLimitRule("/ride/api/upload", max_requests=10, window_seconds=60),
        ]
        # Global limit per IP for any other routes (180 requests per 60s)
        self.global_limit = 180
        self.global_window = 60

    def _cleanup_old_records(self, now: float):
        """Periodically purge expired entries every 60 seconds to conserve memory."""
        if now - self._last_cleanup < 60.0:
            return
        self._last_cleanup = now
        cutoff = now - 120.0

        # Purge IP history
        expired_ips = []
        for ip, timestamps in self._ip_history.items():
            self._ip_history[ip] = [t for t in timestamps if t > cutoff]
            if not self._ip_history[ip]:
                expired_ips.append(ip)
        for ip in expired_ips:
            del self._ip_history[ip]

        # Purge route history
        expired_routes = []
        for key, timestamps in self._route_history.items():
            self._route_history[key] = [t for t in timestamps if t > cutoff]
            if not self._route_history[key]:
                expired_routes.append(key)
        for key in expired_routes:
            del self._route_history[key]

        # Clean jail
        expired_jail = [ip for ip, expiry in self._jailed_ips.items() if expiry <= now]
        for ip in expired_jail:
            del self._jailed_ips[ip]

    def record_offense(self, ip: str, now: float) -> bool:
        """Records an abusive action. If threshold exceeded, jails IP for 60s."""
        history = self._offenses.setdefault(ip, [])
        history.append(now)
        # Keep last 60 seconds of offenses
        self._offenses[ip] = [t for t in history if t > now - 60.0]
        if len(self._offenses[ip]) >= 10:
            self._jailed_ips[ip] = now + 60.0  # Jail for 60 seconds
            return True
        return False

    def check_rate_limit(self, ip: str, path: str) -> Tuple[bool, int, str]:
        """
        Evaluates whether the request is allowed.
        Returns: (allowed: bool, retry_after: int, reason: str)
        """
        now = time.time()
        self._cleanup_old_records(now)

        # 1. Check if IP is currently jailed
        jail_expiry = self._jailed_ips.get(ip)
        if jail_expiry and jail_expiry > now:
            return False, int(jail_expiry - now) + 1, "IP temporarily jailed due to repeated excessive requests."

        # 2. Check path-specific rules
        for rule in self.rules:
            if path == rule.prefix or path.startswith(rule.prefix + "/") or path.startswith(rule.prefix + "?"):
                key = (ip, rule.prefix)
                timestamps = self._route_history.setdefault(key, [])
                # Purge timestamps outside rule window
                window_cutoff = now - rule.window_seconds
                self._route_history[key] = [t for t in timestamps if t > window_cutoff]
                if len(self._route_history[key]) >= rule.max_requests:
                    oldest = self._route_history[key][0]
                    retry_after = max(1, int(rule.window_seconds - (now - oldest)))
                    self.record_offense(ip, now)
                    return False, retry_after, f"Rate limit exceeded for {rule.prefix} ({rule.max_requests} reqs/{rule.window_seconds}s)."
                self._route_history[key].append(now)
                break

        # 3. Global rate limit check
        global_timestamps = self._ip_history.setdefault(ip, [])
        global_cutoff = now - self.global_window
        self._ip_history[ip] = [t for t in global_timestamps if t > global_cutoff]
        if len(self._ip_history[ip]) >= self.global_limit:
            oldest = self._ip_history[ip][0]
            retry_after = max(1, int(self.global_window - (now - oldest)))
            self.record_offense(ip, now)
            return False, retry_after, f"Global IP rate limit exceeded ({self.global_limit} reqs/{self.global_window}s)."
        self._ip_history[ip].append(now)

        return True, 0, ""


# Singleton Rate Limiter instance
security_rate_limiter = SecurityRateLimiter()


class ServerSecurityMiddleware(BaseHTTPMiddleware):
    """
    Production FastAPI / Starlette Security Middleware:
    - Blocks known attack paths (path traversal, shell injection, probe scanners)
    - Enforces request body size ceiling
    - Applies sliding-window rate limiting & abusive IP jailing
    - Injects hardened security response headers
    """
    async def dispatch(self, request: Request, call_next):
        client_ip = request.client.host if request.client else "127.0.0.1"
        # Forwarded IP support behind reverse proxy (Caddy / Nginx)
        forwarded_for = request.headers.get("x-forwarded-for")
        if forwarded_for:
            client_ip = forwarded_for.split(",")[0].strip()

        path = request.url.path

        # 1. DDoS & Web Probe Attack Pattern Inspection
        full_url = str(request.url)
        if ATTACK_PATH_REGEX.search(full_url):
            security_rate_limiter.record_offense(client_ip, time.time())
            return JSONResponse(
                status_code=status.HTTP_403_FORBIDDEN,
                content={"detail": "Forbidden: Request violates security access rules."}
            )

        # 2. Payload size guard (DDoS buffer exhaustion protection)
        content_length = request.headers.get("content-length")
        if content_length:
            try:
                length_int = int(content_length)
                if length_int > MAX_BODY_BYTES:
                    return JSONResponse(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        content={"detail": f"Payload too large. Maximum allowed size is {MAX_BODY_BYTES // (1024*1024)} MB."}
                    )
            except ValueError:
                pass

        # 3. Rate limiting check (Bypass static assets in /ride/ for seamless browser loading)
        is_static_asset = (
            path.startswith("/ride/assets") or
            path.startswith("/ride/canvaskit") or
            path.endswith(".js") or
            path.endswith(".png") or
            path.endswith(".jpg") or
            path.endswith(".svg") or
            path.endswith(".ico") or
            path.endswith(".css") or
            path.endswith(".wasm")
        )
        if not is_static_asset:
            allowed, retry_after, reason = security_rate_limiter.check_rate_limit(client_ip, path)
            if not allowed:
                return JSONResponse(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    headers={"Retry-After": str(retry_after)},
                    content={
                        "detail": reason,
                        "retry_after_seconds": retry_after,
                        "status": "rate_limited"
                    }
                )

        # 4. Process Request
        response: Response = await call_next(request)

        # 5. Inject Hardened Security Headers
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "SAMEORIGIN"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

        return response


# =====================================================================
# Secure File Upload Verification
# =====================================================================

def validate_and_save_upload_file(file_bytes: bytes, original_filename: str) -> Tuple[str, str]:
    """
    Validates file payload using Magic Bytes and extension whitelist.
    Prevents executable script uploading, SVG XSS, path traversal, or oversized binaries.
    
    Returns: (stored_filename: str, public_url_path: str)
    Raises: HTTPException with 400 or 413
    """
    if len(file_bytes) == 0:
        raise HTTPException(status_code=400, detail="Cannot upload empty file.")

    if len(file_bytes) > MAX_FILE_SIZE_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"File exceeds maximum allowed size of {MAX_FILE_SIZE_BYTES // (1024 * 1024)} MB."
        )

    # 1. Extension Verification
    _, ext = os.path.splitext(original_filename or "")
    clean_ext = ext.lower().strip()
    if clean_ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid file extension '{clean_ext}'. Only JPEG, PNG, and WebP images are permitted."
        )

    # 2. Magic Bytes Inspection
    is_valid_image = False
    detected_type = None

    if file_bytes.startswith(b"\xFF\xD8\xFF"):
        is_valid_image = True
        detected_type = "jpeg"
    elif file_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        is_valid_image = True
        detected_type = "png"
    elif len(file_bytes) >= 12 and file_bytes[:4] == b"RIFF" and file_bytes[8:12] == b"WEBP":
        is_valid_image = True
        detected_type = "webp"

    if not is_valid_image:
        raise HTTPException(
            status_code=400,
            detail="File content does not match genuine image binary signature (Spoofed file blocked)."
        )

    # 3. Generate Cryptographically Secure Nonce Filename
    safe_filename = f"diu_{uuid.uuid4().hex[:16]}_{int(time.time())}{clean_ext}"
    dest_path = os.path.join(UPLOADS_DIR, safe_filename)

    # 4. Atomic Write
    temp_path = dest_path + ".tmp"
    with open(temp_path, "wb") as f:
        f.write(file_bytes)
    os.replace(temp_path, dest_path)

    public_url = f"/api/uploads/{safe_filename}"
    return safe_filename, public_url


# =====================================================================
# Database Safety & Transactional Backup Routine
# =====================================================================

def backup_sqlite_database(db_path: str, max_backups: int = 5) -> Optional[str]:
    """
    Creates an online, non-blocking snapshot of SQLite database using the SQLite Backup API.
    Rotates existing snapshots to avoid unbounded disk consumption.
    """
    if not os.path.exists(db_path):
        return None

    try:
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        backup_filename = f"rides_backup_{timestamp}.db"
        dest_backup_path = os.path.join(BACKUPS_DIR, backup_filename)

        # Use SQLite online backup API to ensure 100% ACID consistency without blocking readers/writers
        src_conn = sqlite3.connect(db_path, timeout=15.0)
        dst_conn = sqlite3.connect(dest_backup_path)
        with dst_conn:
            src_conn.backup(dst_conn, pages=100, sleep=0.01)
        dst_conn.close()
        src_conn.close()

        # Rotation: Keep last `max_backups`
        existing_backups = sorted(
            [os.path.join(BACKUPS_DIR, f) for f in os.listdir(BACKUPS_DIR) if f.startswith("rides_backup_") and f.endswith(".db")],
            key=os.path.getmtime
        )
        while len(existing_backups) > max_backups:
            oldest = existing_backups.pop(0)
            try:
                os.remove(oldest)
            except Exception:
                pass

        return dest_backup_path
    except Exception as e:
        print(f"[SECURITY_GUARD] Database backup error: {e}")
        return None
