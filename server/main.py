import os
import re
import json
import sqlite3
import asyncio
import csv
from datetime import datetime, timedelta, timezone
from typing import List, Optional, Dict, Any

BD_TZ = timezone(timedelta(hours=6))

def normalize_student_id(s: str) -> str:
    """Normalize student ID by stripping dashes, spaces, and punctuation."""
    if not s:
        return ""
    return re.sub(r'[^a-zA-Z0-9]', '', str(s)).upper()

def _phone_digits(s: Optional[str]) -> str:
    return re.sub(r"\D", "", str(s or ""))

def _identity_tokens(*values: Optional[str]) -> set:
    """Build comparable identity tokens for same-account detection."""
    tokens = set()
    for raw in values:
        if raw is None:
            continue
        text = str(raw).strip()
        if not text:
            continue
        lower = text.lower()
        tokens.add(lower)
        clean = normalize_student_id(text)
        if clean:
            tokens.add(clean)
            if clean.startswith("USR"):
                tokens.add(clean[3:])
            tokens.add(f"USR{clean}" if not clean.startswith("USR") else clean)
        digits = _phone_digits(text)
        if len(digits) >= 8:
            tokens.add(digits)
            tokens.add(digits[-11:] if len(digits) > 11 else digits)
            tokens.add(digits[-10:] if len(digits) > 10 else digits)
    tokens.discard("")
    return tokens

def is_same_account(
    left_ids: Optional[List[Optional[str]]] = None,
    right_ids: Optional[List[Optional[str]]] = None,
    left_phone: Optional[str] = None,
    right_phone: Optional[str] = None,
    left_name: Optional[str] = None,
    right_name: Optional[str] = None,
) -> bool:
    """
    True when both sides belong to the same DIU account.
    Used to stop self-accept / self-book after Student ↔ Biker mode switch.
    """
    left = _identity_tokens(*(left_ids or []), left_phone)
    right = _identity_tokens(*(right_ids or []), right_phone)
    if left and right and (left & right):
        return True
    lp = _phone_digits(left_phone)
    rp = _phone_digits(right_phone)
    if lp and rp and len(lp) >= 8 and len(rp) >= 8:
        if lp == rp or lp.endswith(rp) or rp.endswith(lp):
            return True
    ln = re.sub(r"\s+", " ", str(left_name or "").strip().lower())
    rn = re.sub(r"\s+", " ", str(right_name or "").strip().lower())
    if ln and rn and ln == rn and "student" not in ln and len(ln) >= 4:
        # Name-only match is weak; only treat as same if phones also empty/equal-ish
        if not lp and not rp:
            return True
    return False

def get_current_bd_time() -> datetime:
    """Returns current naive datetime in Bangladesh local time (UTC+6)."""
    return datetime.now(timezone.utc).astimezone(BD_TZ).replace(tzinfo=None)

def parse_bd_datetime(dt_str: Optional[str]) -> Optional[datetime]:
    if not dt_str:
        return None
    raw = str(dt_str).strip()
    lower_raw = raw.lower()
    if any(k in lower_raw for k in ('now', 'asap', 'immediate')):
        return get_current_bd_time().replace(tzinfo=None)
    try:
        iso_s = raw.replace("Z", "+00:00")
        dt = datetime.fromisoformat(iso_s)
        if dt.tzinfo is not None:
            return dt.astimezone(BD_TZ).replace(tzinfo=None)
        return dt
    except Exception:
        pass
    cleaned = raw.replace("Z", "").strip()
    is_tomorrow = False
    lower_c = cleaned.lower()
    if lower_c.startswith("today,"):
        cleaned = cleaned[6:].strip()
    elif lower_c.startswith("today"):
        cleaned = cleaned[5:].strip()
    elif lower_c.startswith("tomorrow,"):
        cleaned = cleaned[9:].strip()
        is_tomorrow = True
    elif lower_c.startswith("tomorrow"):
        cleaned = cleaned[8:].strip()
        is_tomorrow = True

    try:
        return datetime.fromisoformat(cleaned).replace(tzinfo=None)
    except Exception:
        pass
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d", "%d/%m/%Y %H:%M", "%d-%m-%Y %H:%M"):
        try:
            return datetime.strptime(cleaned, fmt).replace(tzinfo=None)
        except Exception:
            pass
    # For time-only format like "%I:%M %p" or "%H:%M", combine with today/tomorrow's date in BD time
    for fmt in ("%I:%M %p", "%I:%M%p", "%I:%M %P", "%I:%M%P", "%H:%M", "%H:%M:%S"):
        try:
            t = datetime.strptime(cleaned, fmt).time()
            now_bd = get_current_bd_time()
            base_date = now_bd.date() + timedelta(days=1) if is_tomorrow else now_bd.date()
            return datetime.combine(base_date, t)
        except Exception:
            pass
    return None
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Query, Request, Body, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse, FileResponse, HTMLResponse, RedirectResponse
from pydantic import BaseModel
from security_guard import (
    ServerSecurityMiddleware,
    validate_and_save_upload_file,
    backup_sqlite_database,
    UPLOADS_DIR,
)

DB_FILE = os.path.join(os.path.dirname(__file__), "rides.db")
CSV_FILE = os.path.join(os.path.dirname(__file__), "completed_trips.csv")

from active_rides_manager import (
    sync_active_rides_file,
    add_or_update_ride_in_file,
    remove_ride_from_file,
    get_active_rides_from_file,
    ACTIVE_RIDES_JSON_PATH,
    ACTIVE_RIDES_MD_PATH,
)
from confirm_flow import (
    bind_confirm_flow,
    ensure_confirm_columns,
    mark_one_sided_confirm_wait,
    clear_confirm_wait,
    notify_other_parties_after_mutual_confirm,
    periodic_confirm_reminder_task,
)
from ai_service import (
    process_ai_chat_request,
    init_ai_settings_table,
)

app = FastAPI(title="DIU Ride Unified Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

# Hardened Server Security, DDoS & Rate Limiting Middleware
app.add_middleware(ServerSecurityMiddleware)

# =====================================================================
# Database Setup & Initialization (Production SQLite with WAL Mode)
# =====================================================================

def get_db():
    conn = sqlite3.connect(DB_FILE, timeout=20.0, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA synchronous = NORMAL;")
    conn.execute("PRAGMA busy_timeout = 20000;")
    conn.execute("PRAGMA foreign_keys = ON;")
    return conn

def init_db():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("PRAGMA journal_mode = WAL;")

    # 1. Users
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        student_id TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        phone TEXT,
        department TEXT DEFAULT 'CSE',
        batch TEXT DEFAULT 'Batch 54',
        password_hash TEXT NOT NULL,
        rating REAL DEFAULT 4.90,
        total_rides_as_passenger INTEGER DEFAULT 0,
        total_rides_as_driver INTEGER DEFAULT 0,
        is_verified INTEGER DEFAULT 1,
        is_driver_registered INTEGER DEFAULT 0,
        is_biker INTEGER DEFAULT 0,
        vehicle_info TEXT,
        fcm_token TEXT,
        last_known_lat REAL,
        last_known_lng REAL,
        last_location_at TEXT,
        created_at TEXT NOT NULL
    );
    """)

    # 2. Rides
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS rides (
        id TEXT PRIMARY KEY,
        driver_id TEXT NOT NULL,
        driver_name TEXT NOT NULL,
        driver_photo_url TEXT,
        driver_dept TEXT DEFAULT 'CSE',
        driver_phone TEXT,
        driver_rating REAL DEFAULT 4.90,
        driver_ride_count INTEGER DEFAULT 12,
        origin_name TEXT NOT NULL,
        origin_subtitle TEXT,
        origin_lat REAL NOT NULL,
        origin_lng REAL NOT NULL,
        destination_name TEXT NOT NULL,
        destination_subtitle TEXT,
        destination_lat REAL NOT NULL,
        destination_lng REAL NOT NULL,
        waypoint_name TEXT,
        departure_time TEXT NOT NULL,
        fare_per_seat REAL NOT NULL,
        total_seats INTEGER NOT NULL,
        available_seats INTEGER NOT NULL,
        is_female_only INTEGER DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'published',
        vehicle_model TEXT NOT NULL,
        vehicle_type TEXT NOT NULL,
        vehicle_plate TEXT,
        vehicle_color TEXT,
        route_corridor TEXT DEFAULT 'Ashulia Highway Corridor',
        distance_km REAL DEFAULT 14.0,
        duration_minutes INTEGER DEFAULT 30,
        start_lat REAL,
        start_lng REAL,
        start_time TEXT,
        start_maps_link TEXT,
        end_lat REAL,
        end_lng REAL,
        end_time TEXT,
        end_maps_link TEXT,
        route_maps_link TEXT,
        created_at TEXT NOT NULL
    );
    """)

    # Schema migration for existing databases
    for col, c_type in [
        ("start_lat", "REAL"),
        ("start_lng", "REAL"),
        ("start_time", "TEXT"),
        ("start_maps_link", "TEXT"),
        ("end_lat", "REAL"),
        ("end_lng", "REAL"),
        ("end_time", "TEXT"),
        ("end_maps_link", "TEXT"),
        ("route_maps_link", "TEXT"),
        ("rider_confirmed", "INTEGER DEFAULT 0"),
        ("passenger_confirmed", "INTEGER DEFAULT 0"),
        ("total_duration_minutes", "REAL DEFAULT 0.0"),
        ("cancel_reason", "TEXT"),
        ("passenger_id", "TEXT"),
        ("passenger_name", "TEXT"),
        ("destination_choices", "TEXT"),
        ("extension_prompted", "INTEGER DEFAULT 0"),
        ("extended_at", "TEXT"),
        ("post_date", "TEXT"),
        ("post_time", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE rides ADD COLUMN {col} {c_type}")
        except Exception:
            pass

    for col, c_type in [
        ("destination_choices", "TEXT"),
        ("extension_prompted", "INTEGER DEFAULT 0"),
        ("extended_at", "TEXT"),
        ("pickup_lat", "REAL"),
        ("pickup_lng", "REAL"),
        ("dropoff_lat", "REAL"),
        ("dropoff_lng", "REAL"),
        ("post_date", "TEXT"),
        ("post_time", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE passenger_requests ADD COLUMN {col} {c_type}")
        except Exception:
            pass

    for col, c_type in [
        ("rider_confirmed", "INTEGER DEFAULT 0"),
        ("passenger_confirmed", "INTEGER DEFAULT 0"),
        ("trip_status", "TEXT DEFAULT 'pending'"),
        ("started_at", "TEXT"),
        ("completed_at", "TEXT"),
        ("start_lat", "REAL"),
        ("start_lng", "REAL"),
        ("end_lat", "REAL"),
        ("end_lng", "REAL"),
        ("total_duration_minutes", "REAL DEFAULT 0.0"),
        ("cancel_reason", "TEXT"),
        ("driver_id", "TEXT"),
        ("driver_name", "TEXT"),
        ("driver_phone", "TEXT"),
        ("vehicle_model", "TEXT"),
        ("departure_time", "TEXT"),
        ("origin_name", "TEXT"),
        ("destination_name", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE bookings ADD COLUMN {col} {c_type}")
        except Exception:
            pass

    for col, c_type in [
        ("default_address", "TEXT"),
        ("otp_code", "TEXT"),
        ("is_biker", "INTEGER DEFAULT 0"),
        ("fcm_token", "TEXT"),
        ("last_known_lat", "REAL"),
        ("last_known_lng", "REAL"),
        ("last_location_at", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE users ADD COLUMN {col} {c_type}")
        except Exception:
            pass

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS email_otps (
        identifier TEXT PRIMARY KEY,
        otp TEXT NOT NULL,
        created_at TEXT NOT NULL
    );
    """)

    # 3. Bookings
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS bookings (
        id TEXT PRIMARY KEY,
        ride_id TEXT NOT NULL,
        passenger_id TEXT NOT NULL,
        passenger_name TEXT NOT NULL,
        passenger_photo_url TEXT,
        passenger_dept TEXT DEFAULT 'CSE',
        passenger_phone TEXT,
        pickup_point TEXT NOT NULL,
        dropoff_point TEXT NOT NULL,
        seats_booked INTEGER NOT NULL,
        total_fare REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'requested',
        requested_at TEXT NOT NULL,
        rider_confirmed INTEGER DEFAULT 0,
        passenger_confirmed INTEGER DEFAULT 0,
        trip_status TEXT DEFAULT 'pending',
        started_at TEXT,
        completed_at TEXT,
        start_lat REAL,
        start_lng REAL,
        end_lat REAL,
        end_lng REAL,
        total_duration_minutes REAL DEFAULT 0.0,
        cancel_reason TEXT,
        driver_id TEXT,
        driver_name TEXT,
        driver_phone TEXT,
        vehicle_model TEXT,
        departure_time TEXT,
        origin_name TEXT,
        destination_name TEXT
    );
    """)

    # 4. Realtime Chat Messages
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        ride_id TEXT NOT NULL,
        conversation_id TEXT,
        sender_id TEXT NOT NULL,
        sender_name TEXT NOT NULL,
        text TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        is_read INTEGER DEFAULT 1,
        is_location_share INTEGER DEFAULT 0,
        shared_lat REAL,
        shared_lng REAL,
        receiver_id TEXT,
        message_type TEXT DEFAULT 'text',
        ride_event TEXT,
        ride_event_at TEXT
    );
    """)
    for col, c_type in [
        ("receiver_id", "TEXT"),
        ("conversation_id", "TEXT"),
        ("message_type", "TEXT DEFAULT 'text'"),
        ("ride_event", "TEXT"),
        ("ride_event_at", "TEXT"),
        ("sender_mode", "TEXT DEFAULT 'chat'"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE messages ADD COLUMN {col} {c_type}")
        except Exception:
            pass

    # 4b. Stable Conversations Table (one inbox per user pair)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        user_a_id TEXT NOT NULL,
        user_b_id TEXT NOT NULL,
        ride_id TEXT,
        context_type TEXT DEFAULT 'ride',
        last_message TEXT,
        last_message_at TEXT,
        last_sender_id TEXT,
        unread_a INTEGER DEFAULT 0,
        unread_b INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        chat_context TEXT DEFAULT 'peer',
        source_post_id TEXT,
        session_state TEXT DEFAULT 'idle',
        rider_confirmed INTEGER DEFAULT 0,
        passenger_confirmed INTEGER DEFAULT 0,
        trip_starter_a INTEGER DEFAULT 0,
        trip_starter_b INTEGER DEFAULT 0,
        trip_started_at TEXT,
        trip_ender_a INTEGER DEFAULT 0,
        trip_ender_b INTEGER DEFAULT 0,
        trip_ended_at TEXT,
        canceller_id TEXT,
        cancel_reason TEXT,
        diverge_started_at TEXT,
        diverge_alerted INTEGER DEFAULT 0,
        origin TEXT,
        destination TEXT,
        fare REAL DEFAULT 0.0,
        vehicle_model TEXT
    );
    """)
    for col, c_type in [
        ("chat_context", "TEXT DEFAULT 'peer'"),
        ("source_post_id", "TEXT"),
        ("session_state", "TEXT DEFAULT 'idle'"),
        ("rider_confirmed", "INTEGER DEFAULT 0"),
        ("passenger_confirmed", "INTEGER DEFAULT 0"),
        ("trip_starter_a", "INTEGER DEFAULT 0"),
        ("trip_starter_b", "INTEGER DEFAULT 0"),
        ("trip_started_at", "TEXT"),
        ("trip_ender_a", "INTEGER DEFAULT 0"),
        ("trip_ender_b", "INTEGER DEFAULT 0"),
        ("trip_ended_at", "TEXT"),
        ("canceller_id", "TEXT"),
        ("cancel_reason", "TEXT"),
        ("diverge_started_at", "TEXT"),
        ("diverge_alerted", "INTEGER DEFAULT 0"),
        ("origin", "TEXT"),
        ("destination", "TEXT"),
        ("fare", "REAL DEFAULT 0.0"),
        ("vehicle_model", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE conversations ADD COLUMN {col} {c_type}")
        except Exception:
            pass

    cursor.execute("CREATE INDEX IF NOT EXISTS idx_conv_user_a ON conversations(user_a_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_conv_user_b ON conversations(user_b_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_conv_last_msg ON conversations(last_message_at);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_conv_session ON conversations(session_state);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id);")
    ensure_confirm_columns(cursor)

    # 5. Shared Locations (Rider & Passenger GPS Sharing with Google Maps)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS shared_locations (
        id TEXT PRIMARY KEY,
        ride_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        user_name TEXT NOT NULL,
        role TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        maps_link TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    """)

    # 6. Live Driver Locations
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS driver_locations (
        driver_id TEXT PRIMARY KEY,
        ride_id TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        heading REAL DEFAULT 0.0,
        speed REAL DEFAULT 0.0,
        eta_minutes INTEGER DEFAULT 5,
        distance_remaining_km REAL DEFAULT 1.0,
        updated_at TEXT NOT NULL
    );
    """)

    # 7. SOS Emergency Alerts
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS sos_alerts (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        student_name TEXT NOT NULL,
        student_phone TEXT,
        location_name TEXT,
        latitude REAL,
        longitude REAL,
        status TEXT DEFAULT 'active',
        created_at TEXT NOT NULL
    );
    """)

    # 8. Student Ride Requests
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS passenger_requests (
        id TEXT PRIMARY KEY,
        passenger_id TEXT NOT NULL,
        passenger_name TEXT NOT NULL,
        passenger_phone TEXT,
        passenger_dept TEXT DEFAULT 'CSE',
        pickup TEXT NOT NULL,
        dropoff TEXT NOT NULL,
        pickup_lat REAL,
        pickup_lng REAL,
        dropoff_lat REAL,
        dropoff_lng REAL,
        requested_time TEXT NOT NULL,
        proposed_fare REAL DEFAULT 50.0,
        notes TEXT,
        status TEXT DEFAULT 'open',
        accepted_by_driver_id TEXT,
        accepted_by_driver_name TEXT,
        accepted_by_driver_phone TEXT,
        accepted_by_driver_bike TEXT,
        created_at TEXT NOT NULL,
        post_date TEXT,
        post_time TEXT
    );
    """)

    # 9. Completed Rides Historical Log
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS completed_rides (
        id TEXT PRIMARY KEY,
        ride_id TEXT NOT NULL,
        driver_id TEXT NOT NULL,
        driver_name TEXT NOT NULL,
        passenger_id TEXT,
        passenger_name TEXT,
        origin_name TEXT NOT NULL,
        destination_name TEXT NOT NULL,
        start_time TEXT,
        completed_time TEXT NOT NULL,
        fare REAL NOT NULL,
        start_maps_link TEXT,
        end_maps_link TEXT,
        rating REAL DEFAULT 5.0,
        feedback TEXT,
        created_at TEXT NOT NULL
    );
    """)

    # 10. Student Campus News Feed Posts (Facebook / Instagram Style for DIU Students)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS campus_feed_posts (
        id TEXT PRIMARY KEY,
        author_id TEXT NOT NULL,
        author_name TEXT NOT NULL,
        author_dept TEXT DEFAULT 'CSE',
        author_student_id TEXT,
        content TEXT NOT NULL,
        category TEXT DEFAULT 'General',
        image_url TEXT DEFAULT '',
        likes_count INTEGER DEFAULT 0,
        comments_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
    );
    """)

    try:
        cursor.execute("ALTER TABLE campus_feed_posts ADD COLUMN image_url TEXT DEFAULT '';")
    except Exception:
        pass

    # Ensure completed_rides contains full varsity community audit attributes
    for col, col_t in [
        ("driver_phone", "TEXT DEFAULT ''"),
        ("driver_dept", "TEXT DEFAULT 'CSE'"),
        ("driver_student_id", "TEXT DEFAULT ''"),
        ("passenger_phone", "TEXT DEFAULT ''"),
        ("passenger_dept", "TEXT DEFAULT 'DIU Student'"),
        ("passenger_student_id", "TEXT DEFAULT ''"),
        ("route_maps_link", "TEXT DEFAULT ''"),
        ("duration_minutes", "REAL DEFAULT 15.0"),
        ("tracking_notes", "TEXT DEFAULT ''"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE completed_rides ADD COLUMN {col} {col_t};")
        except Exception:
            pass

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS campus_feed_likes (
        post_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        PRIMARY KEY (post_id, user_id)
    );
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS campus_feed_comments (
        id TEXT PRIMARY KEY,
        post_id TEXT NOT NULL,
        author_id TEXT NOT NULL,
        author_name TEXT NOT NULL,
        author_dept TEXT DEFAULT 'CSE',
        content TEXT NOT NULL,
        created_at TEXT NOT NULL
    );
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS trip_route_points (
        id TEXT PRIMARY KEY,
        ride_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        role TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        landmark_name TEXT,
        created_at TEXT NOT NULL
    );
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_trip_route_points_ride ON trip_route_points(ride_id);")

    # Production Database Performance Indexes
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_rides_driver ON rides(driver_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_rides_created ON rides(created_at);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_bookings_ride ON bookings(ride_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_bookings_passenger ON bookings(passenger_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_messages_ride ON messages(ride_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_requests_status ON passenger_requests(status);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_users_student_id ON users(student_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_feed_created ON campus_feed_posts(created_at);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_feed_author ON campus_feed_posts(author_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_feed_comments_post ON campus_feed_comments(post_id);")

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS student_verifications (
        id TEXT PRIMARY KEY,
        student_id TEXT UNIQUE NOT NULL,
        full_name TEXT NOT NULL,
        diu_email TEXT UNIQUE NOT NULL,
        phone TEXT,
        department TEXT DEFAULT 'CSE',
        batch TEXT,
        password_plain TEXT NOT NULL,
        password_hash TEXT,
        verification_status TEXT DEFAULT 'pending',
        is_verified INTEGER DEFAULT 0,
        verification_method TEXT DEFAULT 'firebase_email',
        role TEXT DEFAULT 'student',
        vehicle_model TEXT,
        vehicle_plate TEXT,
        vehicle_color TEXT,
        has_helmet INTEGER DEFAULT 1,
        emergency_contact TEXT,
        id_card_photo_url TEXT,
        created_at TEXT NOT NULL,
        verified_at TEXT,
        last_login_at TEXT
    );
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_verif_student_id ON student_verifications(student_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_verif_email ON student_verifications(diu_email);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_verif_status ON student_verifications(verification_status);")

    # Column migrations for users table
    for col, c_type in [
        ("password_plain", "TEXT"),
        ("verification_status", "TEXT DEFAULT 'pending'"),
        ("verification_method", "TEXT DEFAULT 'firebase_email'"),
        ("verified_at", "TEXT"),
        ("emergency_contact", "TEXT"),
        ("last_login_at", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE users ADD COLUMN {col} {c_type}")
        except Exception:
            pass

    # Ensure all accounts from student_verifications are safely synced into users
    try:
        cursor.execute("""
            INSERT OR IGNORE INTO users (
                id, student_id, name, email, phone, department, batch, password_hash,
                password_plain, verification_status, is_verified, verification_method,
                verified_at, created_at
            )
            SELECT 
                'usr_' || REPLACE(student_id, '-', '_'),
                student_id, full_name, diu_email, phone, department, batch, password_hash,
                password_plain, verification_status, is_verified, verification_method,
                verified_at, created_at
            FROM student_verifications
            WHERE student_id IS NOT NULL AND diu_email IS NOT NULL;
        """)
    except Exception as e:
        print(f"[DB Sync Users Note] {e}")
    _ensure_seed_passenger_requests(cursor)

    conn.commit()
    conn.close()

def _ensure_seed_passenger_requests(cursor):
    # Purge any old seed requests so registration starts clean from 0
    try:
        cursor.execute("DELETE FROM passenger_requests WHERE id LIKE 'preq_seed_%'")
        cursor.execute("DELETE FROM rides WHERE id LIKE 'ride_seed_%'")
    except Exception:
        pass

init_db()

# =====================================================================
# WebSocket Connection Manager (Mobile + Web Realtime Interconnection)
# =====================================================================

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []
        self.user_connections: Dict[str, Set[WebSocket]] = {}
        self.socket_user: Dict[WebSocket, str] = {}

    async def connect(self, websocket: WebSocket, user_id: Optional[str] = None):
        await websocket.accept()
        self.active_connections.append(websocket)
        if user_id:
            self.register_user(websocket, user_id)
        print(f"[WS] Client connected. Total active: {len(self.active_connections)}")

    def register_user(self, websocket: WebSocket, user_id: str):
        if not user_id:
            return
        uid = str(user_id).strip().lower()
        if uid in ("system", "unknown", "none", "", "null"):
            return
        self.socket_user[websocket] = uid
        clean_norm = uid.replace("usr_", "").replace("_", "-")
        aliases = {
            uid,
            clean_norm,
            uid.replace("_", "-"),
            uid.replace("-", "_"),
            f"usr_{clean_norm.replace('-', '_')}",
            "".join(filter(str.isalnum, uid))
        }
        for a in aliases:
            if a:
                if a not in self.user_connections:
                    self.user_connections[a] = set()
                self.user_connections[a].add(websocket)
        print(f"[WS] Registered user '{uid}' (aliases: {aliases}) on socket.")

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
        self.socket_user.pop(websocket, None)
        for user_key in list(self.user_connections.keys()):
            self.user_connections[user_key].discard(websocket)
            if not self.user_connections[user_key]:
                del self.user_connections[user_key]
        print(f"[WS] Client disconnected. Remaining: {len(self.active_connections)}")

    async def broadcast(self, event: str, data: Any):
        payload = json.dumps({"event": event, "data": data})
        to_remove = []
        for connection in list(self.active_connections):
            try:
                await connection.send_text(payload)
            except Exception as e:
                to_remove.append(connection)
        for dead in to_remove:
            self.disconnect(dead)

    async def send_to_user(self, user_id: str, event: str, data: Any) -> bool:
        if not user_id:
            return False
        uid = str(user_id).strip().lower()
        norm_sid = uid.replace("usr_", "").replace("_", "-")
        target_sockets = set()
        for k in (uid, norm_sid, f"usr_{norm_sid.replace('-', '_')}", "".join(filter(str.isalnum, uid))):
            if k in self.user_connections:
                target_sockets.update(self.user_connections[k])
        if not target_sockets:
            return False
        payload = json.dumps({"event": event, "data": data})
        to_remove = []
        for ws in target_sockets:
            try:
                await ws.send_text(payload)
            except Exception:
                to_remove.append(ws)
        for dead in to_remove:
            self.disconnect(dead)
        return len(target_sockets) > len(to_remove)

    async def send_to_pair(self, user_a: str, user_b: str, event: str, data: Any):
        sent_a = await self.send_to_user(user_a, event, data)
        sent_b = await self.send_to_user(user_b, event, data)
        # If user_b was not found in registered sockets (e.g. connected before login or network swap),
        # fallback to broadcast so the peer still receives the message instantly over WS in 0ms!
        if not sent_b:
            await self.broadcast(event, data)

manager = ConnectionManager()

async def check_and_cleanup_expired_scheduled_posts(conn=None):
    close_at_end = False
    if conn is None:
        conn = get_db()
        close_at_end = True
    cursor = conn.cursor()
    # Use Bangladesh local time (UTC+6) because departure_time/requested_time is stored
    # in local Bangladesh time without timezone offset from the Flutter client.
    now_local = get_current_bd_time().replace(tzinfo=None)
    
    deleted_rides = []
    prompt_rides = []
    
    # 1. Rides: check published rides
    try:
        cursor.execute("""
            SELECT id, driver_id, driver_phone, origin_name, destination_name, 
                   departure_time, created_at, status, total_seats, available_seats,
                   rider_confirmed, passenger_confirmed, passenger_id, extension_prompted
            FROM rides 
            WHERE status = 'published'
        """)
        rides = cursor.fetchall()
        for row in rides:
            r = dict(row)
            dep_str = r.get("departure_time")
            dep_dt = parse_bd_datetime(dep_str)
            
            if dep_dt:
                diff_seconds = (now_local - dep_dt).total_seconds()
                # Allow a 60-minute grace window past departure time before purging unbooked rides
                if diff_seconds > 3600:
                    # Check if there is ANY confirmed, accepted, or active booking on this ride
                    cursor.execute("""
                        SELECT COUNT(*) as cnt FROM bookings 
                        WHERE (ride_id = ? OR ride_id LIKE ?) 
                          AND status IN ('accepted', 'confirmed', 'requested', 'in_progress')
                    """, (r["id"], f"%{r['id']}%"))
                    b_cnt = cursor.fetchone()
                    has_order = (b_cnt and b_cnt["cnt"] > 0)
                    
                    if not has_order:
                        total_s = r.get("total_seats", 1) or 1
                        avail_s = r.get("available_seats", 1) or 1
                        if (avail_s < total_s) or (r.get("rider_confirmed")) or (r.get("passenger_confirmed")) or (r.get("passenger_id")):
                            has_order = True

                    if not has_order:
                        # Auto delete post immediately when time has passed
                        cursor.execute("DELETE FROM rides WHERE id = ?", (r["id"],))
                        cursor.execute("DELETE FROM bookings WHERE ride_id = ?", (r["id"],))
                        cursor.execute("DELETE FROM messages WHERE ride_id = ?", (r["id"],))
                        try:
                            cursor.execute("DELETE FROM shared_locations WHERE ride_id = ?", (r["id"],))
                            cursor.execute("DELETE FROM driver_locations WHERE ride_id = ?", (r["id"],))
                        except Exception:
                            pass
                        deleted_rides.append(r["id"])
                        remove_ride_from_file(r["id"])
                        print(f"[AUTO-DELETE EXPIRED POST] Ride {r['id']} crossed departure time. Purged.")
    except Exception as e:
        print(f"[Cleanup Error Rides] {e}")

    # 2. Passenger Requests: check open requests (time par hole delete immediately)
    deleted_reqs = []
    prompt_reqs = []
    try:
        cursor.execute("""
            SELECT id, passenger_id, passenger_phone, pickup, dropoff, 
                   requested_time, created_at, status, extension_prompted 
            FROM passenger_requests 
            WHERE status = 'open'
        """)
        requests = cursor.fetchall()
        for row in requests:
            req = dict(row)
            req_str = req.get("requested_time")
            req_dt = parse_bd_datetime(req_str)
            if not req_dt and req.get("created_at"):
                req_dt = parse_bd_datetime(req.get("created_at"))
            
            if req_dt:
                diff_seconds = (now_local - req_dt).total_seconds()
                # Allow a 60-minute grace window past requested departure time before purging
                if diff_seconds > 3600:
                    cursor.execute("DELETE FROM passenger_requests WHERE id = ?", (req["id"],))
                    deleted_reqs.append(req["id"])
                    print(f"[AUTO-DELETE EXPIRED REQUEST] Passenger request {req['id']} crossed requested time (+30m grace). Purged.")
    except Exception as e:
        print(f"[Cleanup Error Requests] {e}")

    conn.commit()
    if close_at_end:
        conn.close()

    for r_id in deleted_rides:
        await manager.broadcast("ride_deleted", {"id": r_id, "reason": "expired"})
        await manager.broadcast("ride_expired", {"id": r_id, "reason": "expired"})
        await manager.broadcast("post_deleted", {"postId": r_id, "id": r_id, "type": "ride", "reason": "expired"})
    for req_id in deleted_reqs:
        await manager.broadcast("passenger_request_deleted", {"id": req_id, "reason": "expired"})
        await manager.broadcast("passenger_request_expired", {"id": req_id, "reason": "expired"})
        await manager.broadcast("post_deleted", {"postId": req_id, "id": req_id, "type": "passenger_request", "reason": "expired"})

    return deleted_rides, deleted_reqs

async def periodic_expiry_cleanup_task():
    while True:
        try:
            conn = get_db()
            await check_and_cleanup_expired_scheduled_posts(conn)
            sync_active_rides_file(conn)
            conn.close()
        except Exception:
            pass
        await asyncio.sleep(10)


# =====================================================================
# Hardened File Upload Endpoints & Uploads Mount
# =====================================================================
app.mount("/api/uploads", StaticFiles(directory=UPLOADS_DIR), name="api_uploads")
app.mount("/ride/api/uploads", StaticFiles(directory=UPLOADS_DIR), name="ride_api_uploads")

@app.post("/api/upload")
@app.post("/ride/api/upload")
async def secure_file_upload_endpoint(request: Request):
    """
    Cryptographically secure file upload endpoint:
    - Magic bytes binary signature verification (JPEG, PNG, WebP)
    - Rejects shell scripts, SVG XSS vectors, executables (.php, .sh, .py, .exe)
    - Enforces 5 MB size ceiling
    - Generates randomized non-traversable UUID filename
    """
    import base64
    file_bytes = b""
    filename = "upload.jpg"

    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid JSON body")
        raw_b64 = body.get("image_base64") or body.get("image") or ""
        if not raw_b64:
            raise HTTPException(status_code=400, detail="No image or image_base64 provided in JSON payload")
        if "," in raw_b64:
            raw_b64 = raw_b64.split(",", 1)[1]
        try:
            file_bytes = base64.b64decode(raw_b64)
        except Exception:
            raise HTTPException(status_code=400, detail="Corrupted base64 image data")
        filename = body.get("filename") or "upload.jpg"
    elif file is not None:
        file_bytes = await file.read()
        filename = file.filename or "upload.jpg"
    else:
        # Fallback check form
        try:
            form = await request.form()
            form_file = form.get("file")
            if form_file and hasattr(form_file, "read"):
                file_bytes = await form_file.read()
                filename = getattr(form_file, "filename", "upload.jpg")
        except Exception:
            pass

    if not file_bytes:
        raise HTTPException(status_code=400, detail="No valid file or image data received")

    safe_filename, public_url = validate_and_save_upload_file(file_bytes, filename)
    return {
        "status": "success",
        "filename": safe_filename,
        "url": public_url,
        "full_url": f"/ride{public_url}",
    }

@app.on_event("startup")
async def startup_event():
    init_db()
    try:
        backup_path = backup_sqlite_database(DB_FILE)
        if backup_path:
            print(f"[SECURITY GUARD] Database backup snapshot created: {backup_path}")
    except Exception as e:
        print(f"[SECURITY GUARD] Backup error on startup: {e}")
    try:
        conn = get_db()
        init_ai_settings_table(conn)
        conn.close()
    except Exception as e:
        print(f"[STARTUP AI SETTINGS INIT ERROR] {e}")
    try:
        sync_active_rides_file()
    except Exception as e:
        print(f"[STARTUP ACTIVE RIDES SYNC ERROR] {e}")
    asyncio.create_task(periodic_expiry_cleanup_task())

from admin_portal import admin_router, set_ws_manager, ADMIN_HTML
from commute_pdf_generator import generate_commute_passport_pdf
set_ws_manager(manager)
app.include_router(admin_router)

# =====================================================================
# Helper Mappers
# =====================================================================

def map_user(row) -> Dict[str, Any]:
    return {
        "id": row["id"],
        "studentId": row["student_id"],
        "name": row["name"],
        "email": row["email"],
        "phone": row["phone"] or "",
        "department": row["department"] or "CSE",
        "batch": row["batch"] or "Batch 54",
        "isDiuVerified": bool(row["is_verified"]),
        "role": "student",
        "rating": float(row["rating"] or 4.90),
        "totalRidesAsPassenger": int(row["total_rides_as_passenger"] or 0),
        "totalRidesAsDriver": int(row["total_rides_as_driver"] or 0),
        "isDriverRegistered": bool(row["is_driver_registered"]),
        "vehicleInfo": row["vehicle_info"],
        "defaultAddress": row["default_address"] if ("default_address" in row.keys() and row["default_address"]) else "",
    }

def map_ride(row) -> Dict[str, Any]:
    return {
        "id": row["id"],
        "driverId": row["driver_id"],
        "driverName": row["driver_name"],
        "driverPhotoUrl": row["driver_photo_url"],
        "driverDept": row["driver_dept"] or "DIU Student",
        "driverPhone": row["driver_phone"] or "",
        "driverRating": float(row["driver_rating"] or 4.90),
        "driverRideCount": int(row["driver_ride_count"] or 0),
        "originName": row["origin_name"],
        "originSubtitle": row["origin_subtitle"],
        "originLat": float(row["origin_lat"]),
        "originLng": float(row["origin_lng"]),
        "destinationName": row["destination_name"],
        "destinationSubtitle": row["destination_subtitle"],
        "destinationLat": float(row["destination_lat"]),
        "destinationLng": float(row["destination_lng"]),
        "waypointName": row["waypoint_name"],
        "departureTime": row["departure_time"],
        "farePerSeat": float(row["fare_per_seat"]),
        "totalSeats": int(row["total_seats"]),
        "availableSeats": int(row["available_seats"]),
        "isFemaleOnly": bool(row["is_female_only"]),
        "status": row["status"],
        "suspendReason": row["suspend_reason"] if ("suspend_reason" in row.keys() and row["suspend_reason"]) else "",
        "suspendedAt": row["suspended_at"] if ("suspended_at" in row.keys() and row["suspended_at"]) else "",
        "vehicle": {
            "id": f"v_{row['id']}",
            "model": row["vehicle_model"],
            "modelName": row["vehicle_model"],
            "type": "bike",
            "licensePlate": row["vehicle_plate"] or "",
            "color": row["vehicle_color"] or "",
            "hasPassengerHelmet": True,
        },
        "routeCorridor": row["route_corridor"] or "Ashulia Highway Corridor",
        "distanceKm": float(row["distance_km"] or 14.0),
        "durationMinutes": int(row["duration_minutes"] or 30),
        "startLat": float(row["start_lat"]) if ("start_lat" in row.keys() and row["start_lat"] is not None) else None,
        "startLng": float(row["start_lng"]) if ("start_lng" in row.keys() and row["start_lng"] is not None) else None,
        "startTime": row["start_time"] if ("start_time" in row.keys() and row["start_time"] is not None) else None,
        "startMapsLink": row["start_maps_link"] if ("start_maps_link" in row.keys() and row["start_maps_link"] is not None) else None,
        "endLat": float(row["end_lat"]) if ("end_lat" in row.keys() and row["end_lat"] is not None) else None,
        "endLng": float(row["end_lng"]) if ("end_lng" in row.keys() and row["end_lng"] is not None) else None,
        "endTime": row["end_time"] if ("end_time" in row.keys() and row["end_time"] is not None) else None,
        "endMapsLink": row["end_maps_link"] if ("end_maps_link" in row.keys() and row["end_maps_link"] is not None) else None,
        "routeMapsLink": row["route_maps_link"] if ("route_maps_link" in row.keys() and row["route_maps_link"] is not None) else None,
        "riderConfirmed": bool(row["rider_confirmed"]) if ("rider_confirmed" in row.keys() and row["rider_confirmed"]) else False,
        "passengerConfirmed": bool(row["passenger_confirmed"]) if ("passenger_confirmed" in row.keys() and row["passenger_confirmed"]) else False,
        "totalDurationMinutes": float(row["total_duration_minutes"]) if ("total_duration_minutes" in row.keys() and row["total_duration_minutes"]) else 0.0,
        "cancelReason": row["cancel_reason"] if ("cancel_reason" in row.keys()) else None,
        "passengerId": row["passenger_id"] if ("passenger_id" in row.keys()) else None,
        "passengerName": row["passenger_name"] if ("passenger_name" in row.keys()) else None,
        "createdAt": row["created_at"] if "created_at" in row.keys() else None,
        "destinationChoices": (
            json.loads(row["destination_choices"]) if ("destination_choices" in row.keys() and row["destination_choices"])
            else []
        ) if ("destination_choices" in row.keys() and isinstance(row["destination_choices"], str) and str(row["destination_choices"]).startswith("["))
        else ([c.strip() for c in row["destination_choices"].split(",") if c.strip()] if ("destination_choices" in row.keys() and row["destination_choices"]) else []),
        "extensionPrompted": bool(row["extension_prompted"]) if "extension_prompted" in row.keys() else False,
        "extendedAt": row["extended_at"] if "extended_at" in row.keys() else None,
        "postDate": row["post_date"] if "post_date" in row.keys() else None,
        "postTime": row["post_time"] if "post_time" in row.keys() else None,
    }

def map_booking(row) -> Dict[str, Any]:
    keys = row.keys() if hasattr(row, "keys") else []
    return {
        "id": row["id"],
        "rideId": row["ride_id"],
        "passengerId": row["passenger_id"],
        "passengerName": row["passenger_name"],
        "passengerPhotoUrl": row["passenger_photo_url"],
        "passengerDept": row["passenger_dept"] or "DIU Student",
        "passengerPhone": row["passenger_phone"] or "",
        "pickupPoint": row["pickup_point"],
        "dropoffPoint": row["dropoff_point"],
        "seatsBooked": int(row["seats_booked"]),
        "totalFare": float(row["total_fare"]),
        "status": row["status"],
        "requestedAt": row["requested_at"],
        "riderConfirmed": bool(row["rider_confirmed"]) if ("rider_confirmed" in keys and row["rider_confirmed"]) else False,
        "passengerConfirmed": bool(row["passenger_confirmed"]) if ("passenger_confirmed" in keys and row["passenger_confirmed"]) else False,
        "tripStatus": row["trip_status"] if ("trip_status" in keys and row["trip_status"]) else row["status"],
        "startedAt": row["started_at"] if ("started_at" in keys) else None,
        "completedAt": row["completed_at"] if ("completed_at" in keys) else None,
        "totalDurationMinutes": float(row["total_duration_minutes"]) if ("total_duration_minutes" in keys and row["total_duration_minutes"]) else 0.0,
        "cancelReason": row["cancel_reason"] if ("cancel_reason" in keys) else None,
        "driverId": row["driver_id"] if ("driver_id" in keys) else None,
        "driverName": row["driver_name"] if ("driver_name" in keys) else None,
        "driverPhone": row["driver_phone"] if ("driver_phone" in keys) else None,
        "vehicleModel": row["vehicle_model"] if ("vehicle_model" in keys) else None,
        "departureTime": row["departure_time"] if ("departure_time" in keys) else None,
        "originName": row["origin_name"] if ("origin_name" in keys) else None,
        "destinationName": row["destination_name"] if ("destination_name" in keys) else None,
        "rideStatus": row["ride_status"] if ("ride_status" in keys) else (row["status"] if "status" in keys else None),
    }

def map_message(row) -> Dict[str, Any]:
    if not row:
        return {}
    keys = row.keys() if hasattr(row, 'keys') else []
    return {
        "id": row["id"],
        "rideId": row["ride_id"],
        "conversationId": row["conversation_id"] if "conversation_id" in keys else None,
        "senderId": row["sender_id"],
        "senderName": row["sender_name"],
        "receiverId": row["receiver_id"] if "receiver_id" in keys else None,
        "text": row["text"],
        "timestamp": row["timestamp"],
        "isRead": bool(row["is_read"]),
        "isLocationShare": bool(row["is_location_share"]),
        "sharedLat": row["shared_lat"],
        "sharedLng": row["shared_lng"],
        "messageType": row["message_type"] if "message_type" in keys else "text",
        "rideEvent": row["ride_event"] if "ride_event" in keys else None,
        "rideEventAt": row["ride_event_at"] if "ride_event_at" in keys else None,
        "senderMode": row["sender_mode"] if "sender_mode" in keys and row["sender_mode"] else "chat",
        "sender_mode": row["sender_mode"] if "sender_mode" in keys and row["sender_mode"] else "chat",
    }

def map_passenger_request(row) -> Dict[str, Any]:
    keys = row.keys() if hasattr(row, 'keys') else []
    return {
        "id": row["id"],
        "passengerId": row["passenger_id"],
        "passengerName": row["passenger_name"],
        "passengerPhone": row["passenger_phone"] or "",
        "passengerDept": row["passenger_dept"] or "DIU Student",
        "pickup": row["pickup"],
        "dropoff": row["dropoff"],
        "pickupLat": row["pickup_lat"] if "pickup_lat" in keys else None,
        "pickupLng": row["pickup_lng"] if "pickup_lng" in keys else None,
        "dropoffLat": row["dropoff_lat"] if "dropoff_lat" in keys else None,
        "dropoffLng": row["dropoff_lng"] if "dropoff_lng" in keys else None,
        "requestedTime": row["requested_time"],
        "proposedFare": float(row["proposed_fare"] or 50.0),
        "notes": row["notes"] or "",
        "status": row["status"],
        "acceptedByDriverId": row["accepted_by_driver_id"],
        "acceptedByDriverName": row["accepted_by_driver_name"],
        "acceptedByDriverPhone": row["accepted_by_driver_phone"],
        "acceptedByDriverBike": row["accepted_by_driver_bike"],
        "createdAt": row["created_at"],
        "postDate": row["post_date"] if "post_date" in keys else None,
        "postTime": row["post_time"] if "post_time" in keys else None,
        "destinationChoices": (
            json.loads(row["destination_choices"]) if ("destination_choices" in row.keys() and row["destination_choices"])
            else []
        ) if ("destination_choices" in row.keys() and isinstance(row["destination_choices"], str) and str(row["destination_choices"]).startswith("["))
        else ([c.strip() for c in row["destination_choices"].split(",") if c.strip()] if ("destination_choices" in row.keys() and row["destination_choices"]) else []),
        "extensionPrompted": bool(row["extension_prompted"]) if "extension_prompted" in row.keys() else False,
        "extendedAt": row["extended_at"] if "extended_at" in row.keys() else None,
    }

def map_completed_ride(row) -> Dict[str, Any]:
    return {
        "id": row["id"],
        "rideId": row["ride_id"],
        "driverId": row["driver_id"],
        "driverName": row["driver_name"],
        "driverPhone": row["driver_phone"] if "driver_phone" in row.keys() else "",
        "driverDept": row["driver_dept"] if "driver_dept" in row.keys() else "CSE",
        "driverStudentId": row["driver_student_id"] if "driver_student_id" in row.keys() else "",
        "passengerId": row["passenger_id"] or "",
        "passengerName": row["passenger_name"] or "",
        "passengerPhone": row["passenger_phone"] if "passenger_phone" in row.keys() else "",
        "passengerDept": row["passenger_dept"] if "passenger_dept" in row.keys() else "DIU Student",
        "passengerStudentId": row["passenger_student_id"] if "passenger_student_id" in row.keys() else "",
        "originName": row["origin_name"],
        "destinationName": row["destination_name"],
        "startTime": row["start_time"],
        "completedTime": row["completed_time"],
        "durationMinutes": float(row["duration_minutes"] or 15.0) if "duration_minutes" in row.keys() else 15.0,
        "fare": float(row["fare"]),
        "startMapsLink": row["start_maps_link"],
        "endMapsLink": row["end_maps_link"],
        "routeMapsLink": row["route_maps_link"] if "route_maps_link" in row.keys() else "",
        "trackingNotes": row["tracking_notes"] if "tracking_notes" in row.keys() else "",
        "rating": float(row["rating"] or 5.0),
        "feedback": row["feedback"] or "",
        "createdAt": row["created_at"],
    }

# =====================================================================
# REST Endpoints: Health Check
# =====================================================================

@app.get("/ride/health")
@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "service": "DIU Ride Backend",
        "version": "1.0.0",
        "timestamp": datetime.utcnow().isoformat(),
        "active_ws_connections": len(manager.active_connections),
    }

# =====================================================================
# Real Gmail / SMTP Email Dispatcher & Verification
# =====================================================================
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def append_completed_trip_csv(data: Dict[str, Any]):
    file_exists = os.path.isfile(CSV_FILE)
    fieldnames = [
        "trip_id",
        "rider_id",
        "rider_name",
        "rider_phone",
        "passenger_id",
        "passenger_name",
        "passenger_phone",
        "origin",
        "destination",
        "fare",
        "start_time",
        "start_gps_latitude",
        "start_gps_longitude",
        "start_maps_link",
        "end_time",
        "end_gps_latitude",
        "end_gps_longitude",
        "end_maps_link",
        "total_duration_minutes",
        "route_maps_link",
        "status",
        "cancel_reason",
        "completed_at"
    ]
    try:
        with open(CSV_FILE, mode="a", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            if not file_exists:
                writer.writeheader()
            row = {
                "trip_id": data.get("trip_id") or data.get("id") or "",
                "rider_id": data.get("rider_id") or data.get("driver_id") or "",
                "rider_name": data.get("rider_name") or data.get("driver_name") or "",
                "rider_phone": data.get("rider_phone") or data.get("driver_phone") or "",
                "passenger_id": data.get("passenger_id") or "",
                "passenger_name": data.get("passenger_name") or "",
                "passenger_phone": data.get("passenger_phone") or "",
                "origin": data.get("origin") or data.get("origin_name") or "",
                "destination": data.get("destination") or data.get("destination_name") or "",
                "fare": data.get("fare") or 0.0,
                "start_time": data.get("start_time") or "",
                "start_gps_latitude": data.get("start_lat") or data.get("start_gps_latitude") or "",
                "start_gps_longitude": data.get("start_lng") or data.get("start_gps_longitude") or "",
                "start_maps_link": data.get("start_maps_link") or "",
                "end_time": data.get("end_time") or "",
                "end_gps_latitude": data.get("end_lat") or data.get("end_gps_latitude") or "",
                "end_gps_longitude": data.get("end_lng") or data.get("end_gps_longitude") or "",
                "end_maps_link": data.get("end_maps_link") or "",
                "total_duration_minutes": data.get("total_duration_minutes") or 0.0,
                "route_maps_link": data.get("route_maps_link") or "",
                "status": data.get("status") or "completed",
                "cancel_reason": data.get("cancel_reason") or "",
                "completed_at": data.get("completed_time") or datetime.utcnow().isoformat(),
            }
            writer.writerow(row)
        print(f"[CSV AUTO-SAVE] Successfully saved trip {row['trip_id']} ({row['status']}) to {CSV_FILE}")
    except Exception as e:
        print(f"[CSV ERROR] Failed to append trip to CSV: {e}")

FIREBASE_WEB_API_KEY = os.getenv("FIREBASE_WEB_API_KEY", "AIzaSyCSOpUBZYClVhratJeK-OTRhypoRdTTjfk")

def dispatch_firebase_auth_email(to_email: str, password: str = "", is_password_reset: bool = False) -> bool:
    clean_email = to_email.strip().lower()
    if not clean_email or "@" not in clean_email:
        return False

    try:
        import urllib.request as u_req
        import urllib.error as u_err

        if is_password_reset:
            # 1. Ensure user is provisioned in Firebase Auth so sendOobCode actually dispatches the email
            signup_url = f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={FIREBASE_WEB_API_KEY}"
            signup_data = json.dumps({"email": clean_email, "password": password or "DiuTempPass2026!#", "returnSecureToken": False}).encode("utf-8")
            signup_req = u_req.Request(signup_url, data=signup_data, headers={"Content-Type": "application/json"})
            try:
                with u_req.urlopen(signup_req, timeout=6):
                    print(f"[FIREBASE RESET] User provisioned in Firebase Auth: {clean_email}")
            except Exception:
                pass  # User already exists or other non-fatal note

            # 2. Dispatch official Google Firebase Password Reset email
            reset_url = f"https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key={FIREBASE_WEB_API_KEY}"
            reset_data = json.dumps({"requestType": "PASSWORD_RESET", "email": clean_email}).encode("utf-8")
            reset_req = u_req.Request(reset_url, data=reset_data, headers={"Content-Type": "application/json"})
            with u_req.urlopen(reset_req, timeout=8) as r_resp:
                print(f"[FIREBASE RESET] Password reset email dispatched to {clean_email}")
                return True
        else:
            # For Account Verification (VERIFY_EMAIL):
            # Google Identity Toolkit requires an idToken to dispatch VERIFY_EMAIL.
            id_token = None
            candidate_password = password if password and len(password) >= 6 else "DiuStudent2026!#"

            # Try to register user first
            signup_url = f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={FIREBASE_WEB_API_KEY}"
            signup_data = json.dumps({"email": clean_email, "password": candidate_password, "returnSecureToken": True}).encode("utf-8")
            signup_req = u_req.Request(signup_url, data=signup_data, headers={"Content-Type": "application/json"})
            try:
                with u_req.urlopen(signup_req, timeout=6) as s_resp:
                    s_data = json.loads(s_resp.read().decode())
                    id_token = s_data.get("idToken")
                    print(f"[FIREBASE VERIFY] Registered student in Firebase Auth: {clean_email}")
            except u_err.HTTPError as he:
                err_text = he.read().decode()
                if "EMAIL_EXISTS" in err_text:
                    # User exists; try sign-in with provided password
                    signin_url = f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={FIREBASE_WEB_API_KEY}"
                    signin_req = u_req.Request(signin_url, data=signup_data, headers={"Content-Type": "application/json"})
                    try:
                        with u_req.urlopen(signin_req, timeout=6) as si_resp:
                            si_data = json.loads(si_resp.read().decode())
                            id_token = si_data.get("idToken")
                            print(f"[FIREBASE VERIFY] Signed into Firebase Auth: {clean_email}")
                    except Exception as si_err:
                        print(f"[FIREBASE VERIFY] Firebase sign-in note: {si_err}")

            if id_token:
                oob_url = f"https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key={FIREBASE_WEB_API_KEY}"
                oob_data = json.dumps({"requestType": "VERIFY_EMAIL", "idToken": id_token}).encode("utf-8")
                oob_req = u_req.Request(oob_url, data=oob_data, headers={"Content-Type": "application/json"})
                with u_req.urlopen(oob_req, timeout=8) as o_resp:
                    print(f"[FIREBASE VERIFY] Verification email dispatched to {clean_email} (noreply@diuride252.firebaseapp.com)")
                    return True
            else:
                # If idToken couldn't be obtained, dispatch PASSWORD_RESET which also delivers an email directly
                reset_url = f"https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key={FIREBASE_WEB_API_KEY}"
                reset_data = json.dumps({"requestType": "PASSWORD_RESET", "email": clean_email}).encode("utf-8")
                reset_req = u_req.Request(reset_url, data=reset_data, headers={"Content-Type": "application/json"})
                with u_req.urlopen(reset_req, timeout=8) as r_resp:
                    print(f"[FIREBASE VERIFY] Fallback account activation email dispatched to {clean_email} (noreply@diuride252.firebaseapp.com)")
                    return True
    except Exception as e:
        print(f"[FIREBASE DISPATCH NOTE] {e}")
        return False

def check_firebase_email_verified(email: str, password: str = "") -> bool:
    """Checks directly with Firebase Auth Identity Toolkit if user email has been verified via the link."""
    try:
        import urllib.request as u_req
        clean_email = email.strip().lower()
        if not clean_email or "@" not in clean_email:
            return False
        cand_pass = password if password and len(password) >= 6 else "DiuStudent2026!#"
        signin_url = f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={FIREBASE_WEB_API_KEY}"
        data = json.dumps({"email": clean_email, "password": cand_pass, "returnSecureToken": True}).encode("utf-8")
        req = u_req.Request(signin_url, data=data, headers={"Content-Type": "application/json"})
        with u_req.urlopen(req, timeout=5) as resp:
            token = json.loads(resp.read().decode()).get("idToken")
            if not token:
                return False
        lookup_url = f"https://identitytoolkit.googleapis.com/v1/accounts:lookup?key={FIREBASE_WEB_API_KEY}"
        l_data = json.dumps({"idToken": token}).encode("utf-8")
        l_req = u_req.Request(lookup_url, data=l_data, headers={"Content-Type": "application/json"})
        with u_req.urlopen(l_req, timeout=5) as l_resp:
            l_res = json.loads(l_resp.read().decode())
            users = l_res.get("users", [])
            if users and users[0].get("emailVerified"):
                return True
    except Exception as e:
        print(f"[FIREBASE CHECK VERIFIED NOTE] {e}")
    return False

def verify_firebase_password(email: str, password: str) -> bool:
    """Verifies credentials directly against Google Firebase Identity Toolkit."""
    try:
        import urllib.request as u_req
        clean_email = email.strip().lower()
        if not clean_email or "@" not in clean_email or not password:
            return False
        signin_url = f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={FIREBASE_WEB_API_KEY}"
        data = json.dumps({"email": clean_email, "password": password, "returnSecureToken": True}).encode("utf-8")
        req = u_req.Request(signin_url, data=data, headers={"Content-Type": "application/json"})
        with u_req.urlopen(req, timeout=5) as resp:
            data_resp = json.loads(resp.read().decode())
            return bool(data_resp.get("idToken"))
    except Exception:
        return False

def send_smtp_email(to_email: str, subject: str = "Welcome to DIU_Ride - Verification and Account Recovery", otp_code: str = "", student_name: str = "Student", is_password_reset: bool = False, password: str = "") -> bool:
    smtp_user = os.getenv("SMTP_USER") or os.getenv("GMAIL_USER") or os.getenv("EMAIL_HOST_USER") or ""
    smtp_pass = os.getenv("SMTP_PASS") or os.getenv("GMAIL_APP_PASSWORD") or os.getenv("EMAIL_HOST_PASSWORD") or ""
    smtp_host = os.getenv("SMTP_HOST", "smtp.gmail.com")
    smtp_port = int(os.getenv("SMTP_PORT", "587"))

    is_reset = is_password_reset or ("Reset" in subject) or ("Password" in subject) or ("Recovery" in subject)

    verify_link = f"https://servertest.eu.cc/ride/api/auth/verify-link?email={to_email}&otp={otp_code}"
    reset_link = f"https://servertest.eu.cc/ride/api/auth/reset-password-link?email={to_email}&otp={otp_code}"
    web_app_link = f"https://servertest.eu.cc/ride/?verify_email={to_email}&otp={otp_code}"

    # Always ensure the title/subject follows the user's requested format
    email_subject = "Welcome to DIU_Ride - Verification and Account Recovery"

    # 1. Dispatch via Google Firebase Authentication infrastructure for guaranteed deliverability
    firebase_sent = dispatch_firebase_auth_email(to_email=to_email, password=password, is_password_reset=is_reset)

    # 2. Dispatch via SMTP if credentials are configured
    if not smtp_user or not smtp_pass:
        print(f"[EMAIL NOTIFICATION] To: {to_email} | OTP: {otp_code} | Verify: {verify_link} | Reset: {reset_link} | Subject: {email_subject} (Firebase sent: {firebase_sent}. For direct Gmail Primary Inbox delivery, configure GMAIL_APP_PASSWORD in .env)")
        return True

    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = email_subject
        msg["From"] = f"DIU Rides <{smtp_user}>"
        msg["To"] = to_email

        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>{email_subject}</title>
        </head>
        <body style="margin: 0; padding: 24px 0; background-color: #F4F6F8; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
            <div style="max-width: 600px; margin: 0 auto; background-color: #FFFFFF; border: 1px solid #E5E7EB; border-radius: 20px; overflow: hidden; box-shadow: 0 4px 24px rgba(0,0,0,0.06);">
                <!-- App UI Based Header Banner -->
                <div style="background: linear-gradient(135deg, #1B5E20 0%, #2E7D32 50%, #E65100 100%); padding: 36px 28px; text-align: center; color: #FFFFFF;">
                    <div style="display: inline-block; background: rgba(255,255,255,0.22); padding: 6px 18px; border-radius: 20px; font-size: 11.5px; font-weight: 800; letter-spacing: 1.2px; margin-bottom: 12px; text-transform: uppercase;">
                        DIU_RIDE - RIDE SAFE
                    </div>
                    <h1 style="margin: 0; font-size: 26px; font-weight: 800; letter-spacing: -0.5px;">Welcome to DIU_Ride</h1>
                    <p style="margin: 8px 0 0 0; font-size: 14px; opacity: 0.94;">Your Smart Campus Commuting Companion • Daffodil Smart City</p>
                </div>

                <!-- Body Content -->
                <div style="padding: 32px 28px; background-color: #FFFFFF;">
                    <p style="font-size: 16px; color: #111827; margin: 0 0 12px 0; font-weight: 700;">
                        Dear {student_name},
                    </p>
                    <p style="font-size: 14.5px; color: #374151; line-height: 1.65; margin: 0 0 24px 0;">
                        Thank you for using <strong>DIU_Ride</strong>. We are glad to have you on board to make your campus travel easier and more convenient.
                    </p>

                    <!-- Account Verification Section -->
                    <div style="background: #F0FDF4; border: 1.5px solid #86EFAC; border-radius: 16px; padding: 20px 22px; margin-bottom: 22px;">
                        <div style="display: flex; align-items: center; margin-bottom: 8px;">
                            <span style="font-size: 18px; margin-right: 8px;">🛡️</span>
                            <h3 style="margin: 0; font-size: 16px; font-weight: 800; color: #166534;">Account Verification</h3>
                        </div>
                        <p style="font-size: 13.5px; color: #15803D; margin: 0 0 14px 0; line-height: 1.5;">
                            To get started and fully verify your student account, please click the link below:
                        </p>
                        <div style="text-align: center; margin: 14px 0;">
                            <a href="{verify_link}" target="_blank" style="display: inline-block; background: linear-gradient(135deg, #16A34A 0%, #15803D 100%); color: #FFFFFF; font-size: 14.5px; font-weight: 700; text-decoration: none; padding: 13px 28px; border-radius: 12px; box-shadow: 0 4px 12px rgba(22,163,74,0.3);">
                                [ Click Here to Verify Your DIU_Ride Account ]
                            </a>
                        </div>
                        <div style="text-align: center; margin-top: 10px; font-size: 12.5px; color: #166534; font-weight: 600;">
                            Verification Code: <strong style="font-family: monospace; font-size: 16px; letter-spacing: 2px;">{otp_code}</strong> (Valid for 15 minutes)
                        </div>
                    </div>

                    <!-- Password Recovery Section -->
                    <div style="background: #FFFBEB; border: 1.5px solid #FDE68A; border-radius: 16px; padding: 20px 22px; margin-bottom: 24px;">
                        <div style="display: flex; align-items: center; margin-bottom: 8px;">
                            <span style="font-size: 18px; margin-right: 8px;">🔑</span>
                            <h3 style="margin: 0; font-size: 16px; font-weight: 800; color: #92400E;">Password Recovery</h3>
                        </div>
                        <p style="font-size: 13.5px; color: #B45309; margin: 0 0 14px 0; line-height: 1.5;">
                            If you ever forget your password or need to reset your login details, do not worry. You can easily change your password using the secure recovery link below:
                        </p>
                        <div style="text-align: center; margin: 14px 0;">
                            <a href="{reset_link}" target="_blank" style="display: inline-block; background: linear-gradient(135deg, #E65100 0%, #D97706 100%); color: #FFFFFF; font-size: 14.5px; font-weight: 700; text-decoration: none; padding: 13px 28px; border-radius: 12px; box-shadow: 0 4px 12px rgba(230,81,0,0.3);">
                                [ Click Here to Reset / Recover Your Account ]
                            </a>
                        </div>
                        <div style="text-align: center; margin-top: 10px; font-size: 12.5px; color: #92400E; font-weight: 600;">
                            Recovery Code: <strong style="font-family: monospace; font-size: 16px; letter-spacing: 2px;">{otp_code}</strong> (Valid for 15 minutes)
                        </div>
                    </div>

                    <!-- Plaintext Banner ASCII Box -->
                    <div style="margin: 24px 0; font-family: monospace; font-size: 12.5px; line-height: 1.4; color: #1E293B; background: #F8FAFC; border: 1.5px dashed #94A3B8; border-radius: 12px; padding: 16px 20px; white-space: pre-wrap; text-align: center;">
+-------------------------------------------------------------+
|                                                             |
|                   DIU_RIDE - RIDE SAFE                      |
|           Your Smart Campus Commuting Companion             |
|                                                             |
+-------------------------------------------------------------+</div>

                    <p style="font-size: 14.5px; color: #374151; line-height: 1.6; margin: 20px 0 18px 0;">
                        Wishing you very good luck with your rides and your studies at DIU. If you ever need any assistance, feel free to reach out to our support team.
                    </p>

                    <p style="font-size: 14.5px; color: #111827; margin: 0 0 4px 0; font-weight: 600;">
                        Best regards,
                    </p>
                    <p style="font-size: 14.5px; color: #2E7D32; margin: 0 0 2px 0; font-weight: 800;">
                        The DIU_Ride Team
                    </p>
                    <p style="font-size: 13.5px; color: #64748B; margin: 0;">
                        Daffodil International University
                    </p>
                </div>

                <!-- Footer -->
                <div style="background-color: #F8FAFC; padding: 20px 28px; text-align: center; border-top: 1px solid #E2E8F0;">
                    <p style="margin: 0; font-size: 12px; color: #64748B; font-weight: 500;">
                        Daffodil International University • Smart City Campus, Ashulia, Savar, Dhaka
                    </p>
                    <p style="margin: 6px 0 0 0; font-size: 11px; color: #94A3B8;">
                        DIU_Ride Commuter Network &copy; 2026. All rights reserved.
                    </p>
                </div>
            </div>
        </body>
        </html>
        """
        msg.attach(MIMEText(html_content, "html"))

        if smtp_port == 465:
            with smtplib.SMTP_SSL(smtp_host, smtp_port, timeout=10) as server:
                server.login(smtp_user, smtp_pass)
                server.sendmail(smtp_user, to_email, msg.as_string())
        else:
            with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as server:
                server.starttls()
                server.login(smtp_user, smtp_pass)
                server.sendmail(smtp_user, to_email, msg.as_string())
        print(f"[EMAIL SUCCESS] Dispatched live email to {to_email} via {smtp_host}:{smtp_port}")
        return True
    except Exception as e:
        print(f"[EMAIL ERROR] Failed sending to {to_email}: {e}")
        return False

# =====================================================================
# REST Endpoints: Auth
# =====================================================================

class LoginPayload(BaseModel):
    identifier: str
    password: str
    firebaseVerified: Optional[bool] = False

class RegisterPayload(BaseModel):
    studentId: str
    name: str
    email: str
    phone: str
    password: str
    department: Optional[str] = "CSE"

@app.post("/ride/api/auth/login")
@app.post("/api/auth/login")
def auth_login(payload: LoginPayload):
    identifier = payload.identifier.strip()
    password = payload.password.strip()
    firebase_verified = bool(payload.firebaseVerified)
    clean_id = normalize_student_id(identifier)
    prefix_id = identifier.split('@')[0].strip() if '@' in identifier else identifier
    clean_prefix = normalize_student_id(prefix_id)

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM users 
        WHERE student_id = ? 
           OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
           OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
           OR student_id = ?
           OR LOWER(email) = LOWER(?)
           OR LOWER(email) = LOWER(?)
        LIMIT 1
    """, (identifier, clean_id, clean_prefix, prefix_id, identifier, f"{prefix_id}@diu.edu.bd"))
    row = cursor.fetchone()

    if not row:
        # Check student_verifications table for auto-syncing verified student accounts
        cursor.execute("""
            SELECT * FROM student_verifications 
            WHERE student_id = ? 
               OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
               OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
               OR student_id = ?
               OR LOWER(diu_email) = LOWER(?)
               OR LOWER(diu_email) = LOWER(?)
            LIMIT 1
        """, (identifier, clean_id, clean_prefix, prefix_id, identifier, f"{prefix_id}@diu.edu.bd"))
        v_row = cursor.fetchone()
        if v_row:
            u_id = f"usr_{v_row['student_id'].replace('-', '_')}"
            cursor.execute("""
                INSERT OR REPLACE INTO users (
                    id, student_id, name, email, phone, department, batch, password_hash,
                    password_plain, verification_status, is_verified, verification_method,
                    verified_at, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                u_id, v_row["student_id"], v_row["full_name"], v_row["diu_email"],
                v_row["phone"], v_row["department"], v_row["batch"], v_row["password_hash"],
                v_row["password_plain"], v_row["verification_status"], v_row["is_verified"],
                v_row["verification_method"], v_row["verified_at"], v_row["created_at"]
            ))
            conn.commit()
            cursor.execute("SELECT * FROM users WHERE id = ?", (u_id,))
            row = cursor.fetchone()

    if not row:
        conn.close()
        raise HTTPException(
            status_code=404,
            detail=f"Student account not found for '{identifier}'. Please check your ID or register."
        )

    login_now = datetime.utcnow().isoformat()
    # Check verification status (supports both manual OTP and Firebase email link verification)
    if not bool(row["is_verified"]):
        if firebase_verified or check_firebase_email_verified(row["email"], password):
            cursor.execute("UPDATE users SET is_verified = 1, verification_status = 'verified', verified_at = ?, otp_code = NULL WHERE id = ?", (login_now, row["id"]))
            cursor.execute("UPDATE student_verifications SET is_verified = 1, verification_status = 'verified', verified_at = ? WHERE student_id = ? OR LOWER(diu_email) = LOWER(?)", (login_now, row["student_id"], row["email"]))
            conn.commit()
            cursor.execute("SELECT * FROM users WHERE id = ?", (row["id"],))
            row = cursor.fetchone()
        else:
            user_email = row["email"]
            user_student_id = row["student_id"]
            conn.close()
            raise HTTPException(
                status_code=403,
                detail="Your account is not verified yet. Please click the verification link sent to your DIU student email or enter the OTP code.",
                headers={"X-User-Email": user_email, "X-Student-Id": user_student_id}
            )

    stored_hash = row["password_hash"] or ""
    stored_plain = row["password_plain"] if "password_plain" in row.keys() else ""
    # Accept any password if stored hash is the default placeholder from student-id registration flow
    is_default_hash = stored_hash in ("default_student_pwd", "", "none", "null")
    fb_verified_now = False
    if not (stored_hash == password or stored_plain == password or stored_hash == f"hash_{password}" or is_default_hash):
        fb_verified_now = verify_firebase_password(row["email"], password)

    is_valid = (
        firebase_verified or
        fb_verified_now or
        is_default_hash or
        (stored_hash and stored_hash == password) or
        (stored_plain and stored_plain == password) or
        stored_hash == f"hash_{password}"
    )

    if not is_valid:
        user_email = row["email"]
        user_student_id = row["student_id"]
        conn.close()
        raise HTTPException(
            status_code=401,
            detail="Incorrect password. Please verify and try again or use Forgot Password.",
            headers={"X-User-Email": user_email, "X-Student-Id": user_student_id}
        )

    if stored_hash != password or fb_verified_now:
        cursor.execute("UPDATE users SET password_hash = ?, password_plain = ?, is_verified = 1 WHERE id = ?", (password, password, row["id"]))
        cursor.execute("UPDATE student_verifications SET password_hash = ?, password_plain = ?, is_verified = 1 WHERE student_id = ? OR LOWER(diu_email) = LOWER(?)", (password, password, row["student_id"], row["email"]))
        conn.commit()

    login_now = datetime.utcnow().isoformat()
    try:
        cursor.execute("UPDATE users SET last_login_at = ? WHERE id = ?", (login_now, row["id"]))
        cursor.execute("UPDATE student_verifications SET last_login_at = ? WHERE student_id = ? OR LOWER(diu_email) = LOWER(?)", (login_now, row["student_id"], row["email"]))
        conn.commit()
    except Exception:
        pass
    conn.close()

    user_dict = map_user(row)
    return {
        "token": f"jwt_diu_{row['id']}_{int(datetime.utcnow().timestamp())}",
        "refreshToken": f"refresh_diu_{row['id']}",
        "user": user_dict,
        "email": row["email"],
        "studentId": row["student_id"],
    }

@app.post("/ride/api/auth/register")
@app.post("/api/auth/register")
def auth_register(payload: RegisterPayload):
    import random
    bd_now = get_current_bd_time().replace(tzinfo=None)
    now = bd_now.isoformat()
    otp = str(random.randint(100000, 999999))
    email = payload.email.strip().lower()
    student_id = payload.studentId.strip()
    name = payload.name.strip()
    phone = payload.phone.strip()
    dept = payload.department or "CSE"
    password = payload.password.strip()

    conn = get_db()
    cursor = conn.cursor()

    # Block duplicate verified account creation
    cursor.execute("SELECT id, email, name, is_verified FROM users WHERE LOWER(email) = LOWER(?)", (email,))
    existing_user_email = cursor.fetchone()
    if existing_user_email:
        if bool(existing_user_email["is_verified"]):
            conn.close()
            raise HTTPException(
                status_code=400,
                detail=f"An account with email '{email}' is already registered and verified. Please log in or use Forgot Password."
            )
        else:
            # Unverified account: allow re-registration, update details and re-dispatch verification email
            cursor.execute("""
                UPDATE users SET name = ?, phone = ?, department = ?, password_hash = ?, password_plain = ?, otp_code = ?, created_at = ?
                WHERE id = ?
            """, (name, phone, dept, password, password, otp, now, existing_user_email["id"]))
            cursor.execute("""
                UPDATE student_verifications SET full_name = ?, phone = ?, department = ?, password_hash = ?, password_plain = ?, created_at = ?
                WHERE LOWER(diu_email) = LOWER(?) OR student_id = ?
            """, (name, phone, dept, password, password, now, email, student_id))
            user_id = existing_user_email["id"]

    # Block duplicate verified student ID
    cursor.execute("SELECT id, student_id, is_verified FROM users WHERE student_id = ?", (student_id,))
    existing_user_id = cursor.fetchone()
    if existing_user_id:
        if bool(existing_user_id["is_verified"]):
            conn.close()
            raise HTTPException(
                status_code=400,
                detail=f"An account with Student ID '{student_id}' is already registered and verified. Please log in."
            )
        else:
            cursor.execute("""
                UPDATE users SET name = ?, email = ?, phone = ?, department = ?, password_hash = ?, password_plain = ?, otp_code = ?, created_at = ?
                WHERE id = ?
            """, (name, email, phone, dept, password, password, otp, now, existing_user_id["id"]))
            cursor.execute("""
                UPDATE student_verifications SET full_name = ?, diu_email = ?, phone = ?, department = ?, password_hash = ?, password_plain = ?, created_at = ?
                WHERE student_id = ? OR LOWER(diu_email) = LOWER(?)
            """, (name, email, phone, dept, password, password, now, student_id, email))
            user_id = existing_user_id["id"]

    if not existing_user_email and not existing_user_id:
        user_id = f"usr_{student_id.replace('-', '_')}"
        cursor.execute("""
        INSERT INTO users (
            id, student_id, name, email, phone, department, password_hash, password_plain,
            is_verified, verification_status, verification_method, otp_code, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'pending', 'firebase_email', ?, ?)
        """, (
            user_id,
            student_id,
            name,
            email,
            phone,
            dept,
            password,
            password,
            otp,
            now,
        ))

        cursor.execute("""
        INSERT OR REPLACE INTO student_verifications (
            id, student_id, full_name, diu_email, phone, department, batch,
            password_plain, password_hash, verification_status, is_verified,
            verification_method, role, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, 'firebase_email', 'student', ?)
        """, (
            f"verif_{user_id}",
            student_id,
            name,
            email,
            phone,
            dept,
            getattr(payload, 'batch', None) or 'Batch 55',
            password,
            password,
            now,
        ))

    cursor.execute("""
    INSERT OR REPLACE INTO email_otps (identifier, otp, created_at)
    VALUES (?, ?, ?)
    """, (email, otp, now))
    cursor.execute("""
    INSERT OR REPLACE INTO email_otps (identifier, otp, created_at)
    VALUES (?, ?, ?)
    """, (student_id, otp, now))

    conn.commit()
    conn.close()

    # Dispatch real email verification code via Firebase & SMTP with exact title 'DIU ride Verification'
    send_smtp_email(
        to_email=email,
        subject="DIU ride Verification",
        otp_code=otp,
        student_name=name,
        password=password,
    )
    print(f"[AUTH] Registered {student_id} ({email}). Verification OTP: {otp} dispatched to email.")

    return {
        "status": "success",
        "message": f"Verification code and direct activation link sent to {email}.",
        "email": email,
        "studentId": student_id,
        "otp": otp,
    }

@app.post("/ride/api/auth/verify-registration")
@app.post("/ride/api/auth/verify-email")
@app.post("/api/auth/verify-registration")
@app.post("/api/auth/verify-email")
def auth_verify_email(req: Dict[str, Any]):
    email = req.get("email", "").strip().lower()
    student_id = req.get("studentId", "").strip()
    otp = str(req.get("otp", "")).strip()

    conn = get_db()
    cursor = conn.cursor()
    row = None

    if email or student_id:
        cursor.execute("""
            SELECT * FROM users 
            WHERE (LOWER(email) = LOWER(?) AND email != '') 
               OR (student_id = ? AND student_id != '')
            ORDER BY created_at DESC LIMIT 1
        """, (email, student_id))
        row = cursor.fetchone()

    # Look up user by unique generated OTP if email was omitted by client
    if not row and otp:
        cursor.execute("SELECT identifier FROM email_otps WHERE otp = ? ORDER BY created_at DESC LIMIT 1", (otp,))
        otp_match = cursor.fetchone()
        if otp_match:
            ident = otp_match[0]
            cursor.execute("SELECT * FROM users WHERE LOWER(email) = LOWER(?) OR student_id = ? ORDER BY created_at DESC LIMIT 1", (ident, ident))
            row = cursor.fetchone()

    if not row and otp:
        cursor.execute("SELECT * FROM users WHERE otp_code = ? ORDER BY created_at DESC LIMIT 1", (otp,))
        row = cursor.fetchone()

    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Student profile not found.")

    stored_otp = row["otp_code"]
    cursor.execute("SELECT otp FROM email_otps WHERE identifier = ? OR identifier = ?", (row["email"], row["student_id"]))
    otp_rows = cursor.fetchall()
    valid_otps = set()
    if stored_otp:
        valid_otps.add(str(stored_otp).strip())
    for r in otp_rows:
        if r[0]:
            valid_otps.add(str(r[0]).strip())

    is_firebase_verified = bool(
        req.get("firebaseVerified") or 
        req.get("firebase_verified") or 
        otp.upper() in {"FIREBASE_VERIFIED", "FIREBASE"} or
        check_firebase_email_verified(row["email"], row["password_hash"] if "password_hash" in row.keys() else "")
    )

    if not is_firebase_verified and otp not in valid_otps:
        conn.close()
        raise HTTPException(
            status_code=400, 
            detail="Invalid verification code. Please enter the valid 6-digit code sent to your email."
        )

    cursor.execute("""
        UPDATE users 
        SET is_verified = 1, verification_status = 'verified', verified_at = ?, otp_code = NULL 
        WHERE id = ?
    """, (datetime.utcnow().isoformat(), row["id"]))
    cursor.execute("""
        UPDATE student_verifications 
        SET is_verified = 1, verification_status = 'verified', verified_at = ? 
        WHERE student_id = ? OR LOWER(diu_email) = LOWER(?)
    """, (datetime.utcnow().isoformat(), row["student_id"], row["email"]))
    conn.commit()

    cursor.execute("SELECT * FROM users WHERE id = ?", (row["id"],))
    updated_row = cursor.fetchone()
    conn.close()

    user_dict = map_user(updated_row)
    return {
        "user": user_dict,
        "token": f"jwt_verified_{user_dict['id']}",
        "message": "DIU Student account verified and activated successfully!",
    }

@app.get("/ride/api/auth/verify-link")
@app.get("/api/auth/verify-link")
def verify_link_get(email: str = Query(...), otp: str = Query(...)):
    clean_email = email.strip().lower()
    clean_otp = str(otp).strip()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM users 
        WHERE LOWER(email) = LOWER(?) 
        ORDER BY created_at DESC LIMIT 1
    """, (clean_email,))
    user_row = cursor.fetchone()

    if not user_row:
        conn.close()
        return HTMLResponse(content="""
        <!DOCTYPE html>
        <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 60px 20px; background: #FFF3E0;">
        <div style="max-width: 460px; margin: auto; background: #fff; padding: 36px; border-radius: 20px; box-shadow: 0 4px 16px rgba(0,0,0,0.1);">
            <div style="font-size: 48px; margin-bottom: 16px;">⚠️</div>
            <h2 style="color: #D32F2F; margin: 0 0 10px 0;">Account Not Found</h2>
            <p style="color: #555; line-height: 1.5;">No student account is associated with this email address. Please register through the DIU Ride app.</p>
            <a href="/ride/" style="display:inline-block; margin-top:20px; padding:12px 28px; background:#E65100; color:#fff; text-decoration:none; border-radius:12px; font-weight:bold;">Open DIU Ride</a>
        </div>
        </body></html>
        """, status_code=404)

    # Check OTP in email_otps or user otp_code
    cursor.execute("SELECT otp FROM email_otps WHERE identifier = ? OR identifier = ?", (user_row["email"], user_row["student_id"]))
    otp_rows = cursor.fetchall()
    valid_otps = {str(user_row["otp_code"]).strip()} if user_row["otp_code"] else set()
    for r in otp_rows:
        if r[0]:
            valid_otps.add(str(r[0]).strip())

    if clean_otp not in valid_otps and clean_otp != "FIREBASE_VERIFIED":
        conn.close()
        return HTMLResponse(content="""
        <!DOCTYPE html>
        <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 60px 20px; background: #FFF3E0;">
        <div style="max-width: 460px; margin: auto; background: #fff; padding: 36px; border-radius: 20px; box-shadow: 0 4px 16px rgba(0,0,0,0.1);">
            <div style="font-size: 48px; margin-bottom: 16px;">⏳</div>
            <h2 style="color: #D32F2F; margin: 0 0 10px 0;">Invalid or Expired Link</h2>
            <p style="color: #555; line-height: 1.5;">This verification link has expired or has already been used. Please request a new verification code from the DIU Ride app.</p>
            <a href="/ride/" style="display:inline-block; margin-top:20px; padding:12px 28px; background:#E65100; color:#fff; text-decoration:none; border-radius:12px; font-weight:bold;">Open DIU Ride</a>
        </div>
        </body></html>
        """, status_code=400)

    cursor.execute("UPDATE users SET is_verified = 1, verification_status = 'verified', otp_code = NULL WHERE id = ?", (user_row["id"],))
    cursor.execute("UPDATE student_verifications SET is_verified = 1, verification_status = 'verified' WHERE student_id = ? OR LOWER(diu_email) = LOWER(?)", (user_row["student_id"], user_row["email"]))
    conn.commit()
    conn.close()

    return HTMLResponse(content=f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>DIU Ride Verification Success</title>
        <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #F8F9FA; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }}
            .card {{ background: #FFFFFF; max-width: 480px; width: 100%; padding: 40px 32px; border-radius: 24px; box-shadow: 0 10px 30px rgba(0,0,0,0.08); text-align: center; }}
            .icon {{ width: 72px; height: 72px; background: #E8F5E9; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; color: #2E7D32; font-size: 38px; margin-bottom: 20px; }}
            h1 {{ color: #1B5E20; font-size: 24px; margin: 0 0 10px 0; font-weight: 800; }}
            p {{ color: #4B5563; font-size: 15px; line-height: 1.6; margin: 0 0 24px 0; }}
            .btn {{ display: inline-block; background: linear-gradient(135deg, #E65100 0%, #F57C00 100%); color: #FFFFFF; font-weight: bold; text-decoration: none; padding: 14px 32px; border-radius: 14px; font-size: 15px; box-shadow: 0 4px 12px rgba(230,81,0,0.3); transition: transform 0.2s; }}
            .btn:hover {{ transform: translateY(-2px); }}
            .footer {{ margin-top: 24px; font-size: 12px; color: #9CA3AF; }}
        </style>
    </head>
    <body>
        <div class="card">
            <div class="icon">✓</div>
            <h1>Verification Successful!</h1>
            <p>Hello <strong>{user_row['name']}</strong>, your DIU Student account has been verified and activated. You can now login and enjoy seamless campus rides!</p>
            <a href="/ride/" class="btn">Open DIU Ride App</a>
            <div class="footer">Daffodil International University • Ashulia Campus</div>
        </div>
    </body>
    </html>
    """)

@app.post("/ride/api/auth/request-password-reset")
@app.post("/api/auth/request-password-reset")
def request_password_reset(payload: Dict[str, Any]):
    import random
    identifier = str(payload.get("identifier", "")).strip()
    if not identifier:
        raise HTTPException(status_code=400, detail="Student ID or Email is required.")

    clean_id = normalize_student_id(identifier)
    prefix_id = identifier.split('@')[0].strip() if '@' in identifier else identifier
    clean_prefix = normalize_student_id(prefix_id)

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM users 
        WHERE student_id = ? 
           OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
           OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
           OR student_id = ?
           OR LOWER(email) = LOWER(?)
           OR LOWER(email) = LOWER(?)
        LIMIT 1
    """, (identifier, clean_id, clean_prefix, prefix_id, identifier, f"{prefix_id}@diu.edu.bd"))
    row = cursor.fetchone()

    if not row:
        cursor.execute("""
            SELECT * FROM student_verifications 
            WHERE student_id = ? 
               OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
               OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
               OR student_id = ?
               OR LOWER(diu_email) = LOWER(?)
               OR LOWER(diu_email) = LOWER(?)
            LIMIT 1
        """, (identifier, clean_id, clean_prefix, prefix_id, identifier, f"{prefix_id}@diu.edu.bd"))
        v_row = cursor.fetchone()
        if v_row:
            u_id = f"usr_{v_row['student_id'].replace('-', '_')}"
            cursor.execute("""
                INSERT OR REPLACE INTO users (
                    id, student_id, name, email, phone, department, batch, password_hash,
                    password_plain, verification_status, is_verified, verification_method,
                    verified_at, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                u_id, v_row["student_id"], v_row["full_name"], v_row["diu_email"],
                v_row["phone"], v_row["department"], v_row["batch"], v_row["password_hash"],
                v_row["password_plain"], v_row["verification_status"], v_row["is_verified"],
                v_row["verification_method"], v_row["verified_at"], v_row["created_at"]
            ))
            conn.commit()
            cursor.execute("SELECT * FROM users WHERE id = ?", (u_id,))
            row = cursor.fetchone()

    if not row:
        conn.close()
        raise HTTPException(
            status_code=404,
            detail=f"No account found registered with Student ID or Email '{identifier}'. Please check your ID or sign up."
        )

    target_email = row["email"]
    student_name = row["name"] or "Student"
    student_id = row["student_id"]

    otp = f"{random.randint(100000, 999999)}"
    now = datetime.utcnow().isoformat()
    cursor.execute("UPDATE users SET otp_code = ? WHERE id = ?", (otp, row["id"]))
    cursor.execute("INSERT OR REPLACE INTO email_otps (identifier, otp, created_at) VALUES (?, ?, ?)", (target_email, otp, now))
    cursor.execute("INSERT OR REPLACE INTO email_otps (identifier, otp, created_at) VALUES (?, ?, ?)", (student_id, otp, now))
    if clean_id:
        cursor.execute("INSERT OR REPLACE INTO email_otps (identifier, otp, created_at) VALUES (?, ?, ?)", (clean_id, otp, now))
    conn.commit()
    conn.close()

    # Dispatch password reset email with subject 'DIU ride Verification', greeting, code & link
    send_smtp_email(
        to_email=target_email,
        subject="DIU ride Verification",
        otp_code=otp,
        student_name=student_name,
        is_password_reset=True,
    )
    print(f"[AUTH FORGOT PASS] Reset OTP: {otp} for student {student_id} sent to registered email {target_email}")

    return {
        "status": "success",
        "message": f"Password reset code and activation link dispatched to {target_email}.",
        "name": student_name,
        "email": target_email,
        "studentId": student_id,
        "otp": otp,
    }

@app.post("/ride/api/auth/reset-password")
@app.post("/api/auth/reset-password")
def reset_password(payload: Dict[str, Any]):
    identifier = str(payload.get("identifier", "")).strip()
    otp = str(payload.get("otp", "")).strip()
    new_password = str(payload.get("newPassword", "")).strip()

    if not identifier or not otp or not new_password:
        raise HTTPException(status_code=400, detail="Identifier, OTP and new password are required.")

    clean_id = normalize_student_id(identifier)
    prefix_id = identifier.split('@')[0].strip() if '@' in identifier else identifier
    clean_prefix = normalize_student_id(prefix_id)

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM users 
        WHERE student_id = ? 
           OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
           OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
           OR student_id = ?
           OR LOWER(email) = LOWER(?)
           OR LOWER(email) = LOWER(?)
        LIMIT 1
    """, (identifier, clean_id, clean_prefix, prefix_id, identifier, f"{prefix_id}@diu.edu.bd"))
    row = cursor.fetchone()

    if not row:
        cursor.execute("""
            SELECT * FROM student_verifications 
            WHERE student_id = ? 
               OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
               OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
               OR student_id = ?
               OR LOWER(diu_email) = LOWER(?)
               OR LOWER(diu_email) = LOWER(?)
            LIMIT 1
        """, (identifier, clean_id, clean_prefix, prefix_id, identifier, f"{prefix_id}@diu.edu.bd"))
        v_row = cursor.fetchone()
        if v_row:
            u_id = f"usr_{v_row['student_id'].replace('-', '_')}"
            cursor.execute("""
                INSERT OR REPLACE INTO users (
                    id, student_id, name, email, phone, department, batch, password_hash,
                    password_plain, verification_status, is_verified, verification_method,
                    verified_at, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                u_id, v_row["student_id"], v_row["full_name"], v_row["diu_email"],
                v_row["phone"], v_row["department"], v_row["batch"], v_row["password_hash"],
                v_row["password_plain"], v_row["verification_status"], v_row["is_verified"],
                v_row["verification_method"], v_row["verified_at"], v_row["created_at"]
            ))
            conn.commit()
            cursor.execute("SELECT * FROM users WHERE id = ?", (u_id,))
            row = cursor.fetchone()

    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Student account not found.")

    cursor.execute("""
        SELECT otp FROM email_otps 
        WHERE identifier = ? OR identifier = ? OR identifier = ? OR identifier = ? OR identifier = ?
    """, (identifier, clean_id, clean_prefix, row["email"], row["student_id"]))
    otp_rows = cursor.fetchall()
    valid_otps = set()
    if row["otp_code"]:
        valid_otps.add(str(row["otp_code"]).strip())
    for r in otp_rows:
        if r[0]:
            valid_otps.add(str(r[0]).strip())

    if otp not in valid_otps and otp.upper() not in {"FIREBASE_VERIFIED", "FIREBASE"}:
        conn.close()
        raise HTTPException(status_code=400, detail="Invalid reset code. Please enter the valid code sent to your email.")

    cursor.execute("UPDATE users SET password_hash = ?, password_plain = ?, otp_code = NULL, is_verified = 1 WHERE id = ?", (new_password, new_password, row["id"]))
    cursor.execute("UPDATE student_verifications SET password_hash = ?, password_plain = ?, is_verified = 1 WHERE student_id = ? OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ? OR LOWER(diu_email) = LOWER(?)", (new_password, new_password, row["student_id"], clean_id, row["email"]))
    cursor.execute("DELETE FROM email_otps WHERE identifier = ? OR identifier = ? OR identifier = ? OR identifier = ?", (identifier, clean_id, row["email"], row["student_id"]))
    conn.commit()
    conn.close()

    return {
        "status": "success",
        "message": "Password updated successfully. You can now login with your new credentials."
    }

@app.get("/ride/api/auth/reset-password-link")
@app.get("/api/auth/reset-password-link")
def reset_password_link_get(email: str = Query(...), otp: str = Query(...)):
    clean_email = email.strip().lower()
    clean_otp = otp.strip()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE LOWER(email) = LOWER(?)", (clean_email,))
    user = cursor.fetchone()
    cursor.execute("SELECT otp FROM email_otps WHERE identifier = ?", (clean_email,))
    otp_rows = cursor.fetchall()
    conn.close()

    valid_otps = set()
    if user and user["otp_code"]:
        valid_otps.add(str(user["otp_code"]).strip())
    for r in otp_rows:
        if r[0]:
            valid_otps.add(str(r[0]).strip())

    if clean_otp not in valid_otps:
        return HTMLResponse(status_code=400, content=f"""
        <!DOCTYPE html>
        <html>
        <head><title>Reset Link Expired - DIU Ride</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #F9FAFB; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }}
          .card {{ background: white; max-width: 460px; width: 100%; border-radius: 24px; padding: 36px 28px; box-shadow: 0 10px 30px rgba(0,0,0,0.08); text-align: center; border: 1px solid #F3F4F6; }}
          .icon {{ width: 64px; height: 64px; background: #FEE2E2; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 20px; color: #DC2626; font-size: 32px; }}
          h2 {{ color: #111827; margin: 0 0 10px; font-size: 22px; font-weight: 800; }}
          p {{ color: #6B7280; font-size: 14.5px; line-height: 1.5; margin: 0 0 24px; }}
          a.btn {{ display: block; background: #2E7D32; color: white; text-decoration: none; padding: 14px 20px; border-radius: 14px; font-weight: 700; font-size: 15px; }}
        </style>
        </head>
        <body>
          <div class="card">
            <div class="icon">✕</div>
            <h2>Reset Link Invalid or Expired</h2>
            <p>This password reset link has expired or has already been used. Please request a new reset code from the DIU Ride app.</p>
            <a class="btn" href="/ride/">Open DIU Ride</a>
          </div>
        </body>
        </html>
        """)

    # Interactive New Password Form
    return HTMLResponse(content=f"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Reset Password - DIU Ride</title>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        * {{ box-sizing: border-box; }}
        body {{
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: linear-gradient(135deg, #E8F5E9 0%, #C8E6C9 100%);
          display: flex; align-items: center; justify-content: center;
          min-height: 100vh; margin: 0; padding: 20px;
        }}
        .card {{
          background: white; max-width: 440px; width: 100%; border-radius: 28px;
          padding: 36px 30px; box-shadow: 0 16px 40px rgba(46,125,50,0.12);
          text-align: center; border: 1px solid #E5E7EB;
        }}
        .icon-wrap {{
          width: 72px; height: 72px; background: linear-gradient(135deg, #1B5E20, #2E7D32);
          border-radius: 22px; display: flex; align-items: center; justify-content: center;
          margin: 0 auto 20px; color: white; font-size: 32px; box-shadow: 0 8px 20px rgba(46,125,50,0.3);
        }}
        h2 {{ color: #111827; margin: 0 0 8px; font-size: 24px; font-weight: 800; }}
        .subtitle {{ color: #6B7280; font-size: 13.5px; margin: 0 0 24px; line-height: 1.5; }}
        .badge {{
          background: #E8F5E9; color: #2E7D32; font-weight: 700; font-size: 12px;
          padding: 6px 14px; border-radius: 20px; display: inline-block; margin-bottom: 20px;
        }}
        .field {{ text-align: left; margin-bottom: 16px; }}
        label {{ font-size: 13px; font-weight: 700; color: #374151; display: block; margin-bottom: 6px; }}
        input {{
          width: 100%; padding: 13px 16px; border: 1.5px solid #D1D5DB; border-radius: 12px;
          font-size: 15px; outline: none; transition: border-color 0.2s;
        }}
        input:focus {{ border-color: #2E7D32; }}
        .btn {{
          width: 100%; background: linear-gradient(135deg, #2E7D32, #1B5E20); color: white;
          border: none; padding: 15px 20px; border-radius: 14px; font-size: 15px;
          font-weight: 700; cursor: pointer; box-shadow: 0 6px 20px rgba(46,125,50,0.3);
          margin-top: 10px; transition: transform 0.1s, opacity 0.2s;
        }}
        .btn:hover {{ opacity: 0.95; }}
        .btn:active {{ transform: scale(0.98); }}
        .msg {{ margin-top: 16px; font-size: 13px; font-weight: 600; display: none; }}
        .msg.err {{ color: #DC2626; display: block; }}
        .msg.ok {{ color: #2E7D32; display: block; }}
      </style>
    </head>
    <body>
      <div class="card" id="formCard">
        <div class="icon-wrap">🔑</div>
        <div class="badge">DIU Ride Account Recovery</div>
        <h2>Set New Password</h2>
        <div class="subtitle">Enter your new secure password for <strong>{clean_email}</strong>.</div>
        <form id="resetForm" onsubmit="handleReset(event)">
          <div class="field">
            <label>New Password</label>
            <input type="password" id="newPass" required minlength="6" placeholder="Enter new password (min 6 chars)">
          </div>
          <div class="field">
            <label>Confirm Password</label>
            <input type="password" id="confirmPass" required minlength="6" placeholder="Re-type new password">
          </div>
          <button type="submit" class="btn" id="submitBtn">Update Password & Proceed</button>
          <div id="statusMsg" class="msg"></div>
        </form>
      </div>

      <script>
        async function handleReset(e) {{
          e.preventDefault();
          const p1 = document.getElementById('newPass').value;
          const p2 = document.getElementById('confirmPass').value;
          const msg = document.getElementById('statusMsg');
          const btn = document.getElementById('submitBtn');

          if (p1 !== p2) {{
            msg.className = 'msg err';
            msg.innerText = 'Passwords do not match. Please re-enter.';
            return;
          }}

          btn.disabled = true;
          btn.innerText = 'Updating Password...';
          msg.className = 'msg';
          msg.innerText = '';

          try {{
            const res = await fetch('/ride/api/auth/reset-password', {{
              method: 'POST',
              headers: {{ 'Content-Type': 'application/json' }},
              body: JSON.stringify({{
                identifier: '{clean_email}',
                otp: '{clean_otp}',
                newPassword: p1
              }})
            }});

            const data = await res.json();
            if (res.ok) {{
              document.getElementById('formCard').innerHTML = `
                <div class="icon-wrap" style="background: linear-gradient(135deg, #10B981, #059669);">✓</div>
                <div class="badge" style="background: #E8F5E9; color: #10B981;">Updated Successfully</div>
                <h2>Password Reset Complete! 🎉</h2>
                <div class="subtitle">Your password has been securely updated. You can now log into DIU Ride with your new credentials.</div>
                <a href="/ride/" class="btn" style="display: block; text-decoration: none; margin-top: 20px;">Open DIU Ride App / Web</a>
              `;
            }} else {{
              msg.className = 'msg err';
              msg.innerText = data.detail || 'Failed to update password. Please try again.';
              btn.disabled = false;
              btn.innerText = 'Update Password & Proceed';
            }}
          }} catch (err) {{
            msg.className = 'msg err';
            msg.innerText = 'Network error. Please check your connection and try again.';
            btn.disabled = false;
            btn.innerText = 'Update Password & Proceed';
          }}
        }}
      </script>
    </body>
    </html>
    """)

@app.post("/ride/api/auth/default-address")
@app.post("/api/auth/default-address")
def update_default_address(payload: Dict[str, Any]):
    user_id = str(payload.get("userId") or payload.get("id") or "").strip()
    student_id = str(payload.get("studentId") or "").strip()
    email = str(payload.get("email") or "").strip().lower()
    address = str(payload.get("defaultAddress") or payload.get("address") or "").strip()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        UPDATE users SET default_address = ? 
        WHERE (id = ? AND id != '') 
           OR (student_id = ? AND student_id != '') 
           OR (LOWER(email) = ? AND email != '')
    """, (address, user_id, student_id or user_id, email))
    conn.commit()

    cursor.execute("""
        SELECT * FROM users 
        WHERE (id = ? AND id != '') 
           OR (student_id = ? AND student_id != '') 
           OR (LOWER(email) = ? AND email != '')
    """, (user_id, student_id or user_id, email))
    row = cursor.fetchone()
    conn.close()

    if row:
        return {"status": "success", "user": map_user(row), "defaultAddress": address}
    return {"status": "success", "user": {"defaultAddress": address}, "defaultAddress": address}

@app.post("/ride/api/admin/clear-all-records")
@app.post("/api/admin/clear-all-records")
def clear_all_records():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM messages")
    cursor.execute("DELETE FROM bookings")
    cursor.execute("DELETE FROM rides")
    cursor.execute("DELETE FROM shared_locations")
    cursor.execute("DELETE FROM driver_locations")
    cursor.execute("DELETE FROM sos_alerts")
    cursor.execute("DELETE FROM passenger_requests")
    cursor.execute("DELETE FROM completed_rides")
    cursor.execute("DELETE FROM email_otps")
    cursor.execute("DELETE FROM users")
    conn.commit()
    conn.close()
    print("[ADMIN] All test and demo records cleared from database.")
    return {
        "status": "success",
        "message": "All records cleared successfully. Production fresh database ready.",
    }

@app.post("/ride/api/auth/send-email-otp")
@app.post("/api/auth/send-email-otp")
@app.post("/ride/api/auth/resend-verification")
@app.post("/api/auth/resend-verification")
def auth_send_email_otp(payload: Dict[str, Any]):
    import random
    email = payload.get("email", "").strip().lower()
    student_id = payload.get("studentId", "").strip()
    if not email and not student_id:
        raise HTTPException(status_code=400, detail="Email or Student ID is required")
    
    otp = f"{random.randint(100000, 999999)}"
    now = datetime.utcnow().isoformat()
    conn = get_db()
    cursor = conn.cursor()
    ident = email or student_id
    cursor.execute("INSERT OR REPLACE INTO email_otps (identifier, otp, created_at) VALUES (?, ?, ?)", (ident, otp, now))
    if email and student_id:
        cursor.execute("INSERT OR REPLACE INTO email_otps (identifier, otp, created_at) VALUES (?, ?, ?)", (student_id, otp, now))
    conn.commit()
    conn.close()

    send_smtp_email(to_email=email or f"{student_id}@diu.edu.bd", subject="DIU ride Verification", otp_code=otp)
    return {
        "status": "ok",
        "message": f"Verification code sent to {email or student_id}.",
        "email": email,
        "otp": otp,
    }

@app.post("/ride/api/auth/login-student-id")
@app.post("/api/auth/login-student-id")
def auth_login_student_id(payload: Dict[str, Any]):
    name = payload.get("name", "DIU Student").strip()
    student_id = payload.get("studentId", "").strip()
    email = payload.get("email", "").strip().lower()
    phone = payload.get("phone", "").strip()

    if not student_id:
        raise HTTPException(status_code=400, detail="Student ID is required")

    conn = get_db()
    cursor = conn.cursor()
    clean_id = normalize_student_id(student_id)
    cursor.execute("""
        SELECT * FROM users 
        WHERE student_id = ? 
           OR UPPER(REPLACE(REPLACE(student_id, '-', ''), ' ', '')) = ?
           OR LOWER(email) = LOWER(?)
    """, (student_id, clean_id, email))
    row = cursor.fetchone()

    now = datetime.utcnow().isoformat()
    if not row:
        user_id = f"usr_{student_id.replace('-', '_')}"
        cursor.execute("""
        INSERT INTO users (id, student_id, name, email, phone, is_verified, password_hash, created_at)
        VALUES (?, ?, ?, ?, ?, 1, 'default_student_pwd', ?)
        """, (user_id, student_id, name, email or f"{student_id}@diu.edu.bd", phone, now))
        conn.commit()
        cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
        row = cursor.fetchone()
    conn.close()

    user_dict = map_user(row)
    return {
        "token": f"jwt_student_{user_dict['id']}",
        "user": user_dict,
    }

@app.post("/ride/api/auth/profile")
@app.post("/api/auth/profile")
async def update_profile_endpoint(request: Request):
    try:
        data = await request.json()
    except Exception:
        data = {}
    u_id = data.get("id") or data.get("studentId")
    if not u_id:
        raise HTTPException(status_code=400, detail="Missing user id")
    conn = get_db()
    cursor = conn.cursor()
    v_info = data.get("vehicleInfo")
    if isinstance(v_info, dict):
        v_info = json.dumps(v_info)
    cursor.execute("""
        UPDATE users SET
            name = COALESCE(?, name),
            phone = COALESCE(?, phone),
            department = COALESCE(?, department),
            batch = COALESCE(?, batch),
            vehicle_info = COALESCE(?, vehicle_info),
            default_address = COALESCE(?, default_address)
        WHERE id = ? OR student_id = ?
    """, (
        data.get("name"),
        data.get("phone"),
        data.get("department"),
        data.get("batch"),
        v_info,
        data.get("defaultAddress"),
        u_id,
        u_id
    ))
    conn.commit()
    cursor.execute("SELECT * FROM users WHERE id = ? OR student_id = ?", (u_id, u_id))
    row = cursor.fetchone()
    conn.close()
    if row:
        return {"status": "success", "user": map_user(row)}
    return {"status": "success"}

@app.post("/ride/api/auth/logout")
@app.post("/api/auth/logout")
def logout_endpoint():
    return {"status": "success", "message": "Logged out successfully"}

@app.post("/ride/api/auth/send-otp")
@app.post("/api/auth/send-otp")
async def send_phone_otp_endpoint(request: Request):
    try:
        data = await request.json()
    except Exception:
        data = {}
    phone = data.get("phone", "")
    return {"status": "success", "phone": phone, "message": "OTP sent successfully"}

@app.post("/ride/api/alert-ring")
@app.post("/api/alert-ring")
async def trigger_alert_ring(payload: Dict[str, Any]):
    ring_id = str(payload.get("ringId") or f"ring_{int(datetime.utcnow().timestamp()*1000)}").strip()
    target_user_id = str(payload.get("targetUserId", "all")).strip()
    target_name = str(payload.get("targetName", "")).strip()
    sender_id = str(payload.get("senderId", "")).strip()
    sender_name = str(payload.get("senderName", "Campus Peer")).strip()
    ride_id = str(payload.get("rideId", "general")).strip()
    message = str(payload.get("message") or f"🚨 Urgent: {sender_name} is ringing you for pickup!").strip()
    now = datetime.utcnow().isoformat()

    alert_data = {
        "id": ring_id,
        "ringId": ring_id,
        "targetUserId": target_user_id,
        "targetName": target_name,
        "senderId": sender_id,
        "senderName": sender_name,
        "rideId": ride_id,
        "message": message,
        "timestamp": now,
        "type": "alert_ring",
    }

    # Broadcast event to all WebSocket clients!
    await manager.broadcast("alert_ring", alert_data)
    print(f"[ALERT RING] Ring {ring_id} from {sender_name} ({sender_id}) to {target_user_id} ({target_name})")

    return {
        "status": "success",
        "message": "Alert ring buzzer dispatched successfully!",
        "data": alert_data,
    }

@app.post("/ride/api/stop-ring")
@app.post("/api/stop-ring")
async def stop_alert_ring(payload: Dict[str, Any]):
    ring_id = str(payload.get("ringId", "")).strip()
    target_user_id = str(payload.get("targetUserId", "")).strip()
    sender_id = str(payload.get("senderId", "")).strip()
    stopped_by = str(payload.get("stoppedBy", "user")).strip()

    stop_data = {
        "id": ring_id,
        "ringId": ring_id,
        "targetUserId": target_user_id,
        "senderId": sender_id,
        "stoppedBy": stopped_by,
        "timestamp": datetime.utcnow().isoformat(),
        "type": "stop_ring",
    }

    await manager.broadcast("stop_ring", stop_data)
    print(f"[STOP RING] Stopped ring {ring_id} between {sender_id} and {target_user_id} by {stopped_by}")

    return {
        "status": "success",
        "message": "Ring stopped successfully.",
        "data": stop_data,
    }

# =====================================================================
# REST Endpoints: Rides (Bikes Only with Auto Destination Search)
# =====================================================================

@app.get("/ride/api/rides")
@app.get("/api/rides")
async def get_rides(
    status: Optional[str] = None,
    pickup: Optional[str] = None,
    dropoff: Optional[str] = None,
    destination: Optional[str] = None,
    query: Optional[str] = None,
    vehicle_type: Optional[str] = None,
    female_only: Optional[bool] = None,
    exclude_user_id: Optional[str] = None,
    exclude_phone: Optional[str] = None,
    driver_id: Optional[str] = None,
):
    try:
        await check_and_cleanup_expired_scheduled_posts()
    except Exception:
        pass

    conn = get_db()
    cursor = conn.cursor()
    sql = "SELECT * FROM rides WHERE id NOT LIKE 'preq_%'"
    params = []

    if driver_id:
        sql += " AND (driver_id = ? OR driver_id LIKE ?)"
        params.extend([driver_id, f"%{driver_id}%"])

    if exclude_user_id and not driver_id:
        sql += " AND (driver_id != ? AND driver_id NOT LIKE ?)"
        params.extend([exclude_user_id, f"%{exclude_user_id}%"])

    if exclude_phone and not driver_id:
        clean_p = "".join(filter(str.isdigit, exclude_phone))
        if len(clean_p) >= 8:
            short_p = clean_p[-8:]
            sql += " AND driver_phone NOT LIKE ?"
            params.append(f"%{short_p}%")
        else:
            sql += " AND driver_phone != ?"
            params.append(exclude_phone)

    if vehicle_type and vehicle_type.lower() != "all":
        sql += " AND LOWER(vehicle_type) = ?"
        params.append(vehicle_type.lower())

    if status:
        sql += " AND status = ?"
        params.append(status)

    target_query = (query or "").strip()
    if target_query:
        q_val = f"%{target_query.lower()}%"
        is_ab4 = "ab4" in target_query.lower() or "ab 4" in target_query.lower() or "ab-4" in target_query.lower()
        if is_ab4:
            ab4_val = "%academic building 4%"
            sql += """ AND (
                LOWER(destination_name) LIKE ? OR LOWER(destination_subtitle) LIKE ? 
                OR LOWER(origin_name) LIKE ? OR LOWER(origin_subtitle) LIKE ? 
                OR LOWER(route_corridor) LIKE ? OR LOWER(waypoint_name) LIKE ?
                OR LOWER(driver_name) LIKE ? OR LOWER(origin_name) LIKE ?
                OR LOWER(destination_name) LIKE ? OR LOWER(destination_choices) LIKE ?
            )"""
            params.extend([q_val, q_val, q_val, q_val, q_val, q_val, q_val, ab4_val, ab4_val, q_val])
        else:
            sql += """ AND (
                LOWER(destination_name) LIKE ? OR LOWER(destination_subtitle) LIKE ? 
                OR LOWER(origin_name) LIKE ? OR LOWER(origin_subtitle) LIKE ? 
                OR LOWER(route_corridor) LIKE ? OR LOWER(waypoint_name) LIKE ?
                OR LOWER(driver_name) LIKE ? OR LOWER(destination_choices) LIKE ?
            )"""
            params.extend([q_val, q_val, q_val, q_val, q_val, q_val, q_val, q_val])
    else:
        target_dest = (destination or dropoff or "").strip()
        if target_dest:
            d_val = f"%{target_dest.lower()}%"
            sql += " AND (LOWER(destination_name) LIKE ? OR LOWER(destination_subtitle) LIKE ? OR LOWER(route_corridor) LIKE ? OR LOWER(destination_choices) LIKE ?)"
            params.extend([d_val, d_val, d_val, d_val])

        if pickup and pickup.strip():
            p_val = f"%{pickup.strip().lower()}%"
            sql += " AND (LOWER(origin_name) LIKE ? OR LOWER(origin_subtitle) LIKE ?)"
            params.extend([p_val, p_val])

    if female_only is not None:
        sql += " AND is_female_only = ?"
        params.append(1 if female_only else 0)

    sql += " ORDER BY departure_time ASC"
    cursor.execute(sql, params)
    rows = cursor.fetchall()
    conn.close()

    now_local = get_current_bd_time().replace(tzinfo=None)
    rides = []
    for r in rows:
        m = map_ride(r)
        if m.get("status") == "published":
            dep_str = m.get("departureTime") or ""
            dep_dt = parse_bd_datetime(dep_str)
            # Strict BST check: if departure time is more than 15 minutes past, expire from feed
            if dep_dt and (now_local - dep_dt).total_seconds() > 900:
                continue  # Expired past scheduled departure time
        elif not driver_id:
            continue  # Non-published rides not visible in public feed

        # If general public search (not driver fetching their own posted rides):
        # Exclude booked / occupied rides from the public feed so they only show to the person who booked it
        if not driver_id:
            avail_s = m.get("availableSeats")
            if avail_s is not None and avail_s <= 0:
                continue
            if m.get("status") in ("cancelled", "completed", "occupied", "suspended"):
                continue

        rides.append(m)
    return rides

@app.get("/ride/api/rides/my-posted")
@app.get("/api/rides/my-posted")
async def get_my_posted_rides(user_id: str = Query(...)):
    """
    Uber-style Activity endpoint: returns all rides posted by the driver
    along with their current booking requests and passenger details.
    """
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM rides 
        WHERE driver_id = ? OR driver_id LIKE ? 
        ORDER BY created_at DESC, departure_time DESC
    """, (user_id, f"%{user_id}%"))
    ride_rows = cursor.fetchall()

    results = []
    for r in ride_rows:
        ride_dict = map_ride(r)
        # Fetch all bookings for this ride
        cursor.execute("SELECT * FROM bookings WHERE ride_id = ? ORDER BY requested_at DESC", (r["id"],))
        booking_rows = cursor.fetchall()
        ride_dict["bookings"] = [map_booking(b) for b in booking_rows]
        results.append(ride_dict)

    conn.close()
    return results

@app.post("/ride/api/rides")
@app.post("/api/rides")
async def create_ride(ride_data: Dict[str, Any]):
    # Validate core fields
    origin = (ride_data.get("originName") or "").strip()
    destination = (ride_data.get("destinationName") or "").strip()
    if not origin or not destination:
        raise HTTPException(status_code=400, detail="Origin and destination cannot be empty.")
    if origin.lower() == destination.lower():
        raise HTTPException(status_code=400, detail="Origin and destination cannot be identical.")

    try:
        fare = float(ride_data.get("farePerSeat", 60.0))
    except (ValueError, TypeError):
        raise HTTPException(status_code=400, detail="Invalid fare amount.")
    if fare <= 0:
        raise HTTPException(status_code=400, detail="Fare per seat must be greater than zero.")

    try:
        total_seats = int(ride_data.get("totalSeats", 1))
        avail_seats = int(ride_data.get("availableSeats", 1))
    except (ValueError, TypeError):
        raise HTTPException(status_code=400, detail="Invalid seat count.")
    if total_seats <= 0 or avail_seats <= 0:
        raise HTTPException(status_code=400, detail="Seat count must be at least 1.")

    # Validate departure time
    dep_time_str = ride_data.get("departureTime")
    dep_dt = parse_bd_datetime(dep_time_str)
    now_bd = get_current_bd_time()
    if dep_dt and dep_dt < (now_bd - timedelta(minutes=60)):
        raise HTTPException(status_code=400, detail="Departure time cannot be in the past.")
    if not dep_time_str or any(k in str(dep_time_str).lower() for k in ("now", "asap")):
        dep_time_str = now_bd.isoformat()

    driver_id = str(ride_data.get("driverId") or "drv_usr").strip()

    # Prevent accidental double-tap spam posting within 5 seconds for same driver & route
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    SELECT id FROM rides
    WHERE driver_id = ? AND status = 'published' AND origin_name = ? AND destination_name = ?
      AND created_at >= ?
    """, (driver_id, origin, destination, (now_bd - timedelta(seconds=5)).isoformat()))
    if cursor.fetchone():
        conn.close()
        raise HTTPException(status_code=400, detail="An identical ride was just posted. Please wait a moment.")

    ride_id = ride_data.get("id") or f"ride_{int(datetime.utcnow().timestamp()*1000)}"
    vehicle = ride_data.get("vehicle", {})

    # Validate motorcycle setup requirement
    v_model = str(vehicle.get("modelName") or vehicle.get("model") or "").strip()
    v_plate = str(vehicle.get("licensePlate") or vehicle.get("plate") or "").strip()
    cursor.execute("SELECT vehicle_info FROM users WHERE id = ? OR student_id = ?", (driver_id, driver_id))
    d_row = cursor.fetchone()
    db_v_info = str(d_row["vehicle_info"] or "").strip() if d_row else ""
    if not db_v_info and (not v_model or not v_plate):
        conn.close()
        raise HTTPException(status_code=400, detail="Motorcycle setup is required before publishing a ride.")
    if db_v_info and (not v_model or not v_plate):
        import re
        match_v = re.match(r'^(.*?)\s*\((.*?)\)$', db_v_info)
        if match_v:
            v_model = v_model or match_v.group(1).strip()
            v_plate = v_plate or match_v.group(2).strip()
        else:
            v_model = v_model or db_v_info
            v_plate = v_plate or "DHAKA-METRO" 

    dest_choices = ride_data.get("destinationChoices") or []
    if isinstance(dest_choices, list):
        dest_choices_str = json.dumps(dest_choices)
    elif isinstance(dest_choices, str):
        dest_choices_str = dest_choices
    else:
        dest_choices_str = "[]"

    post_date_str = now_bd.strftime("%Y-%m-%d")
    post_time_str = now_bd.strftime("%I:%M %p")
    cursor.execute("""
    INSERT INTO rides (
        id, driver_id, driver_name, driver_photo_url, driver_dept, driver_phone,
        driver_rating, driver_ride_count, origin_name, origin_subtitle, origin_lat, origin_lng,
        destination_name, destination_subtitle, destination_lat, destination_lng,
        waypoint_name, departure_time, fare_per_seat, total_seats, available_seats, is_female_only,
        status, vehicle_model, vehicle_type, vehicle_plate, vehicle_color,
        route_corridor, distance_km, duration_minutes, destination_choices, created_at,
        post_date, post_time
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        ride_id,
        ride_data.get("driverId", "drv_usr"),
        ride_data.get("driverName", "DIU Student"),
        ride_data.get("driverPhotoUrl"),
        ride_data.get("driverDept", "CSE"),
        ride_data.get("driverPhone", "01712345678"),
        float(ride_data.get("driverRating", 5.0)),
        int(ride_data.get("driverRideCount", 1)),
        ride_data.get("originName", "DIU Campus"),
        ride_data.get("originSubtitle"),
        float(ride_data.get("originLat", 23.8765)),
        float(ride_data.get("originLng", 90.3204)),
        ride_data.get("destinationName", "Dhaka"),
        ride_data.get("destinationSubtitle"),
        float(ride_data.get("destinationLat", 23.8728)),
        float(ride_data.get("destinationLng", 90.3984)),
        ride_data.get("waypointName"),
        ride_data.get("departureTime") or get_current_bd_time().strftime("%Y-%m-%d %H:%M:%S"),
        float(ride_data.get("farePerSeat", 60.0)),
        int(ride_data.get("totalSeats", 3)),
        int(ride_data.get("availableSeats", 3)),
        1 if ride_data.get("isFemaleOnly") else 0,
        ride_data.get("status", "published"),
        v_model or vehicle.get("model", "Vehicle"),
        vehicle.get("type", "bike"),
        v_plate,
        vehicle.get("color", ""),
        ride_data.get("routeCorridor", "Campus Highway Corridor"),
        float(ride_data.get("distanceKm", 14.0)),
        int(ride_data.get("durationMinutes", 30)),
        dest_choices_str,
        now_bd.isoformat(),
        post_date_str,
        post_time_str,
    ))
    conn.commit()

    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
    conn.close()

    created = map_ride(row)
    if row:
        try:
            add_or_update_ride_in_file(dict(row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on create_ride] {e}")
    await manager.broadcast("ride_created", created)
    return created

@app.post("/ride/api/rides/{ride_id}/extend-time")
@app.post("/api/rides/{ride_id}/extend-time")
async def extend_ride_departure_time(ride_id: str, payload: Dict[str, Any] = Body(...)):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Ride not found")
    
    minutes = int(payload.get("minutes", 30))
    new_departure_time = payload.get("newDepartureTime")
    if not new_departure_time:
        try:
            cur_dt = datetime.fromisoformat(row["departure_time"].replace("Z", "+00:00")).replace(tzinfo=None)
            base_dt = max(datetime.utcnow(), cur_dt)
        except Exception:
            base_dt = datetime.utcnow()
        new_dt = base_dt + timedelta(minutes=minutes)
        new_departure_time = new_dt.isoformat()
    
    now_iso = datetime.utcnow().isoformat()
    cursor.execute("""
        UPDATE rides 
        SET departure_time = ?, extended_at = ?, extension_prompted = 0, status = 'published'
        WHERE id = ?
    """, (new_departure_time, now_iso, ride_id))
    conn.commit()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    updated_row = cursor.fetchone()
    conn.close()

    updated = map_ride(updated_row)
    if updated_row:
        try:
            add_or_update_ride_in_file(dict(updated_row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on extend_ride] {e}")
    await manager.broadcast("ride_updated", updated)
    await manager.broadcast("ride_time_extended", {
        "id": ride_id,
        "departureTime": new_departure_time,
        "minutes": minutes
    })
    return {"status": "success", "ride": updated, "newDepartureTime": new_departure_time}

@app.patch("/ride/api/rides")
@app.patch("/api/rides")
async def update_ride_patch(payload: Dict[str, Any]):
    ride_id = payload.get("id") or payload.get("ride_id") or payload.get("rideId")
    if not ride_id:
        raise HTTPException(status_code=400, detail="Missing ride id")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Ride not found")

    updates = []
    params = []
    if "status" in payload:
        updates.append("status = ?")
        params.append(payload["status"])
    if "availableSeats" in payload or "available_seats" in payload:
        updates.append("available_seats = ?")
        params.append(int(payload.get("availableSeats") if payload.get("availableSeats") is not None else payload.get("available_seats")))
    if "departureTime" in payload or "departure_time" in payload:
        updates.append("departure_time = ?")
        params.append(payload.get("departureTime") or payload.get("departure_time"))
    if "farePerSeat" in payload or "fare_per_seat" in payload:
        updates.append("fare_per_seat = ?")
        params.append(float(payload.get("farePerSeat") if payload.get("farePerSeat") is not None else payload.get("fare_per_seat")))

    if updates:
        params.append(ride_id)
        cursor.execute(f"UPDATE rides SET {', '.join(updates)} WHERE id = ?", params)
        conn.commit()

    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    updated_row = cursor.fetchone()
    conn.close()

    updated = map_ride(updated_row) if updated_row else {}
    if updated.get("status") in ("cancelled", "completed"):
        try:
            remove_ride_from_file(ride_id)
        except Exception:
            pass
    elif updated_row:
        try:
            add_or_update_ride_in_file(dict(updated_row))
        except Exception:
            pass

    await manager.broadcast("ride_updated", updated)
    return updated

@app.get("/ride/api/rides/{ride_id}")
@app.get("/api/rides/{ride_id}")
def get_ride_by_id(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Ride not found")
    return map_ride(row)

@app.delete("/ride/api/rides/{ride_id}")
@app.delete("/api/rides/{ride_id}")
@app.delete("/ride/api/rides")
@app.delete("/api/rides")
@app.post("/ride/api/rides/{ride_id}/delete")
@app.post("/api/rides/{ride_id}/delete")
@app.post("/ride/api/rides/delete")
@app.post("/api/rides/delete")
async def delete_ride_endpoint(
    ride_id: Optional[str] = None,
    id: Optional[str] = Query(None),
    request: Request = None
):
    target_id = ride_id or id
    if not target_id and request:
        try:
            body = await request.json()
            target_id = body.get("id") or body.get("ride_id") or body.get("rideId")
        except Exception:
            pass
    if not target_id:
        raise HTTPException(status_code=400, detail="Missing ride_id to delete")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM rides WHERE id = ? OR id LIKE ?", (target_id, f"%{target_id}%"))
    cursor.execute("DELETE FROM bookings WHERE ride_id = ? OR ride_id LIKE ?", (target_id, f"%{target_id}%"))
    cursor.execute("DELETE FROM messages WHERE ride_id = ? OR ride_id LIKE ?", (target_id, f"%{target_id}%"))
    try:
        cursor.execute("DELETE FROM shared_locations WHERE ride_id = ? OR ride_id LIKE ?", (target_id, f"%{target_id}%"))
        cursor.execute("DELETE FROM driver_locations WHERE ride_id = ? OR ride_id LIKE ?", (target_id, f"%{target_id}%"))
    except Exception:
        pass
    conn.commit()
    conn.close()

    try:
        remove_ride_from_file(target_id)
    except Exception as e:
        print(f"[ACTIVE RIDES FILE ERROR on delete_ride] {e}")

    await manager.broadcast("ride_deleted", {"id": target_id})
    await manager.broadcast("post_deleted", {"id": target_id, "type": "ride"})
    print(f"[RIDE DELETED] Successfully purged ride {target_id} from database and broadcasted.")
    return {"status": "success", "message": f"Ride {target_id} deleted successfully", "id": target_id}

@app.post("/ride/api/rides/{ride_id}/start")
@app.post("/api/rides/{ride_id}/start")
async def start_ride(ride_id: str, payload: Optional[Dict[str, Any]] = None):
    conn = get_db()
    cursor = conn.cursor()
    now = datetime.utcnow().isoformat()
    lat = payload.get("latitude") if payload else None
    lng = payload.get("longitude") if payload else None

    if lat is not None and lng is not None:
        start_maps_link = f"https://www.google.com/maps/search/?api=1&query={lat},{lng}"
        cursor.execute("""
        UPDATE rides SET status = 'active', rider_confirmed = 1, passenger_confirmed = 1, start_lat = ?, start_lng = ?, start_time = ?, start_maps_link = ? WHERE id = ?
        """, (float(lat), float(lng), now, start_maps_link, ride_id))
    else:
        cursor.execute("UPDATE rides SET status = 'active', rider_confirmed = 1, passenger_confirmed = 1, start_time = ? WHERE id = ?", (now, ride_id))

    cursor.execute("""
        UPDATE bookings 
        SET rider_confirmed = 1, passenger_confirmed = 1, status = 'accepted', trip_status = 'in_progress', started_at = COALESCE(started_at, ?)
        WHERE ride_id = ? OR ride_id LIKE ?
    """, (now, ride_id, f"%{ride_id}%"))
    conn.commit()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()

    # Auto-cleanup previous published feeds/posts for this driver so feeds are cleared
    if row:
        driver_id = row["driver_id"]
        driver_phone = row["driver_phone"] if "driver_phone" in row.keys() else None
        cursor.execute(
            "SELECT id FROM rides WHERE id != ? AND (driver_id = ? OR (driver_phone IS NOT NULL AND driver_phone != '' AND driver_phone = ?)) AND status = 'published'",
            (ride_id, driver_id, driver_phone)
        )
        stale_rows = cursor.fetchall()
        for s_r in stale_rows:
            cursor.execute("DELETE FROM rides WHERE id = ?", (s_r["id"],))
            cursor.execute("DELETE FROM bookings WHERE ride_id = ?", (s_r["id"],))
            await manager.broadcast("ride_deleted", {"id": s_r["id"]})
        conn.commit()

    conn.close()
    if row:
        updated = map_ride(row)
        start_maps = row["start_maps_link"] or ""
        start_txt = f"🚀 Ride Officially Started! Driver is on the way with live GPS tracking: {start_maps}" if start_maps else "🚀 Ride Officially Started! Driver is en route to pickup point."
        await _save_and_broadcast_message(ride_id, {
            "rideId": ride_id,
            "senderId": "system",
            "senderName": "DIU Ride System",
            "text": start_txt,
            "isLocationShare": bool(start_maps),
            "sharedLat": row["start_lat"],
            "sharedLng": row["start_lng"],
            "timestamp": now,
        })
        await manager.broadcast("ride_session_status_changed", {
            "rideId": ride_id,
            "status": "in_progress",
            "startTime": row["start_time"] or now,
            "startMapsLink": start_maps,
        })
        await manager.broadcast("ride_updated", updated)
        return updated
    raise HTTPException(status_code=404, detail="Ride not found")

@app.post("/ride/api/rides/{ride_id}/complete")
@app.post("/api/rides/{ride_id}/complete")
async def complete_ride(ride_id: str, payload: Optional[Dict[str, Any]] = None):
    conn = get_db()
    cursor = conn.cursor()
    now = datetime.utcnow().isoformat()
    lat = payload.get("latitude") if payload else None
    lng = payload.get("longitude") if payload else None

    # Check origin or start GPS to generate full route directions link
    cursor.execute("SELECT start_lat, start_lng, origin_lat, origin_lng FROM rides WHERE id = ?", (ride_id,))
    ride_info = cursor.fetchone()
    route_maps_link = None
    end_maps_link = None

    if lat is not None and lng is not None:
        end_maps_link = f"https://www.google.com/maps/search/?api=1&query={lat},{lng}"
        if ride_info:
            o_lat = ride_info["start_lat"] if ride_info["start_lat"] is not None else ride_info["origin_lat"]
            o_lng = ride_info["start_lng"] if ride_info["start_lng"] is not None else ride_info["origin_lng"]
            route_maps_link = f"https://www.google.com/maps/dir/?api=1&origin={o_lat},{o_lng}&destination={lat},{lng}&travelmode=driving"

        cursor.execute("""
        UPDATE rides SET status = 'completed', end_lat = ?, end_lng = ?, end_time = ?, end_maps_link = ?, route_maps_link = ? WHERE id = ?
        """, (float(lat), float(lng), now, end_maps_link, route_maps_link, ride_id))
    else:
        cursor.execute("UPDATE rides SET status = 'completed', end_time = ? WHERE id = ?", (now, ride_id))

    conn.commit()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()

    if row:
        # Resolve duration in minutes
        start_t_str = row["start_time"] or now
        try:
            dt_start = datetime.fromisoformat(start_t_str.replace("Z", "+00:00"))
            dt_end = datetime.fromisoformat(now.replace("Z", "+00:00"))
            duration_mins = max(1.0, round((dt_end - dt_start).total_seconds() / 60.0, 1))
        except Exception:
            duration_mins = 15.0

        cursor.execute("SELECT passenger_id, passenger_name, passenger_phone FROM bookings WHERE ride_id = ? AND status = 'accepted' LIMIT 1", (ride_id,))
        b_row = cursor.fetchone()
        p_id = b_row["passenger_id"] if b_row else ""
        p_name = b_row["passenger_name"] if b_row else ""
        p_phone = b_row["passenger_phone"] if b_row else ""

        # Resolve verified varsity student details for driver & passenger
        cursor.execute("SELECT student_id, department, phone FROM users WHERE id = ? OR student_id = ? OR email = ?", (row["driver_id"], row["driver_id"], row["driver_id"]))
        u_drv = cursor.fetchone()
        driver_sid = u_drv["student_id"] if u_drv and u_drv["student_id"] else (row["driver_id"] if "-" in str(row["driver_id"]) else "")
        driver_dept = u_drv["department"] if u_drv and u_drv["department"] else "DIU Student"
        driver_phone = row["driver_phone"] or (u_drv["phone"] if u_drv else "")

        cursor.execute("SELECT student_id, department, phone FROM users WHERE id = ? OR student_id = ? OR email = ?", (p_id, p_id, p_id))
        u_pass = cursor.fetchone()
        passenger_sid = u_pass["student_id"] if u_pass and u_pass["student_id"] else (p_id if "-" in str(p_id) else "")
        passenger_dept = u_pass["department"] if u_pass and u_pass["department"] else "DIU Student"
        passenger_phone = p_phone or (u_pass["phone"] if u_pass else "")

        # Always construct full Google Maps directions route link
        import urllib.parse
        if not route_maps_link:
            o_q = f"{row['start_lat']},{row['start_lng']}" if row['start_lat'] is not None and row['start_lng'] is not None else urllib.parse.quote(row['origin_name'])
            d_q = f"{lat},{lng}" if lat is not None and lng is not None else urllib.parse.quote(row['destination_name'])
            route_maps_link = f"https://www.google.com/maps/dir/?api=1&origin={o_q}&destination={d_q}&travelmode=driving"

        tracking_notes = (
            f"DIU Campus Commute Log: {row['origin_name']} ➔ {row['destination_name']}. "
            f"Biker: {row['driver_name']} (ID: {driver_sid or 'N/A'}, Dept: {driver_dept}, Ph: {driver_phone}). "
            f"Passenger: {p_name or 'Student'} (ID: {passenger_sid or 'N/A'}, Dept: {passenger_dept}, Ph: {passenger_phone}). "
            f"Duration: {duration_mins:.0f} mins. Status: Safely Completed."
        )

        # Save into completed_rides historical table
        comp_id = f"comp_{ride_id}_{int(datetime.utcnow().timestamp())}"
        cursor.execute("""
        INSERT OR REPLACE INTO completed_rides (
            id, ride_id, driver_id, driver_name, passenger_id, passenger_name,
            origin_name, destination_name, start_time, completed_time, fare,
            start_maps_link, end_maps_link, rating, feedback, created_at,
            driver_phone, driver_dept, driver_student_id,
            passenger_phone, passenger_dept, passenger_student_id,
            route_maps_link, duration_minutes, tracking_notes
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (
            comp_id, ride_id, row["driver_id"], row["driver_name"], p_id, p_name,
            row["origin_name"], row["destination_name"], row["start_time"], now,
            float(row["fare_per_seat"]), row["start_maps_link"], row["end_maps_link"],
            5.0, "", now,
            driver_phone, driver_dept, driver_sid,
            passenger_phone, passenger_dept, passenger_sid,
            route_maps_link, duration_mins, tracking_notes
        ))
        conn.commit()

        # Automatic CSV persistence for historical analysis & compliance
        append_completed_trip_csv({
            "trip_id": comp_id,
            "rider_id": row["driver_id"],
            "rider_name": row["driver_name"],
            "rider_phone": driver_phone,
            "passenger_id": p_id,
            "passenger_name": p_name,
            "passenger_phone": passenger_phone,
            "origin": row["origin_name"],
            "destination": row["destination_name"],
            "fare": float(row["fare_per_seat"]),
            "start_time": row["start_time"],
            "start_lat": row["start_lat"],
            "start_lng": row["start_lng"],
            "start_maps_link": row["start_maps_link"],
            "end_time": now,
            "end_lat": lat,
            "end_lng": lng,
            "end_maps_link": end_maps_link,
            "total_duration_minutes": duration_mins,
            "route_maps_link": route_maps_link,
            "completed_time": now,
        })

        # If complete, mark bookings as completed
        cursor.execute("""
            UPDATE bookings 
            SET status = 'completed', trip_status = 'completed', completed_at = ?, total_duration_minutes = ?
            WHERE ride_id = ? OR ride_id LIKE ?
        """, (now, duration_mins, ride_id, f"%{ride_id}%"))
        conn.commit()

    conn.close()

    try:
        remove_ride_from_file(ride_id)
    except Exception as e:
        print(f"[ACTIVE RIDES FILE ERROR on complete_ride] {e}")
    if row:
        updated = map_ride(row)
        end_maps = row["end_maps_link"] or ""
        try:
            time_formatted = datetime.fromisoformat(now.replace("Z", "+00:00")).strftime("%I:%M %p, %b %d")
        except Exception:
            time_formatted = now
        
        comp_txt = (
            f"🏁 DIU Commute Completed & Verified!\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📍 Corridor: {row['origin_name']} ➔ {row['destination_name']}\n"
            f"⏱️ Duration: {duration_mins:.0f} min(s) | 💰 Total Fare: ৳{float(row['fare_per_seat']):.0f}\n"
            f"🏍️ Biker: {row['driver_name']} ({driver_dept}) • {driver_phone or 'Verified'}\n"
            f"🎒 Passenger: {p_name or 'Student'} ({passenger_dept}) • {passenger_phone or 'Verified'}\n\n"
            f"🗺️ View Google Maps Route & Directions:\n"
            f"{route_maps_link}\n\n"
            f"📝 Campus Tracking Notes:\n"
            f"• Trip ended: {time_formatted}\n"
            f"• Verified DIU Student Community Network transit\n"
            f"• Trip logs securely archived for varsity audit\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━"
        )
        
        # Broadcast to ride channel and 1-on-1 canonical DM inbox
        channels_to_notify = {ride_id}
        if row["driver_id"] and p_id and row["driver_id"] != p_id:
            pair = sorted([str(row["driver_id"]).lower().strip(), str(p_id).lower().strip()])
            channels_to_notify.add(f"peer_dm_{pair[0]}__{pair[1]}")

        for ch in channels_to_notify:
            await _save_and_broadcast_message(ch, {
                "rideId": ch,
                "senderId": "system",
                "senderName": "DIU Ride System",
                "text": comp_txt,
                "isLocationShare": True,
                "sharedLat": row["end_lat"] or lat,
                "sharedLng": row["end_lng"] or lng,
                "timestamp": now,
            })
        await manager.broadcast("ride_session_status_changed", {
            "rideId": ride_id,
            "status": "completed",
            "completedTime": now,
            "fare": float(row["fare_per_seat"]),
            "endMapsLink": end_maps,
            "routeMapsLink": route_maps_link,
            "totalDurationMinutes": duration_mins,
        })
        await manager.broadcast("ride_completed", {"rideId": ride_id, "status": "completed"})
        await manager.broadcast("booking_status_updated", {"rideId": ride_id, "status": "completed"})
        await manager.broadcast("ride_updated", updated)
        return updated
    raise HTTPException(status_code=404, detail="Ride not found")

@app.post("/ride/api/rides/{ride_id}/cancel")
@app.post("/api/rides/{ride_id}/cancel")
async def cancel_ride(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE rides SET status = 'cancelled' WHERE id = ?", (ride_id,))
    cursor.execute("""
        UPDATE bookings 
        SET status = 'cancelled', trip_status = 'cancelled' 
        WHERE ride_id = ? OR ride_id LIKE ?
    """, (ride_id, f"%{ride_id}%"))
    conn.commit()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
    conn.close()
    try:
        remove_ride_from_file(ride_id)
    except Exception as e:
        print(f"[ACTIVE RIDES FILE ERROR on cancel_ride] {e}")

    if row:
        updated = map_ride(row)
        await manager.broadcast("ride_updated", updated)
        await manager.broadcast("ride_session_status_changed", {
            "rideId": ride_id,
            "status": "cancelled",
        })
        await manager.broadcast("booking_status_updated", {"rideId": ride_id, "status": "cancelled"})
        return updated
    raise HTTPException(status_code=404, detail="Ride not found")

@app.get("/ride/api/completed-rides")
@app.get("/api/completed-rides")
def get_completed_rides(user_id: Optional[str] = None):
    conn = get_db()
    cursor = conn.cursor()
    if user_id:
        cursor.execute("""
            SELECT * FROM completed_rides 
            WHERE driver_id = ? OR passenger_id = ? 
            ORDER BY completed_time DESC
        """, (user_id, user_id))
    else:
        cursor.execute("SELECT * FROM completed_rides ORDER BY completed_time DESC")
    rows = cursor.fetchall()
    conn.close()
    return [map_completed_ride(r) for r in rows]

@app.get("/ride/api/admin/completed-trips.csv")
@app.get("/api/admin/completed-trips.csv")
def download_completed_trips_csv():
    if not os.path.exists(CSV_FILE):
        append_completed_trip_csv({})
    return FileResponse(
        CSV_FILE,
        media_type="text/csv",
        filename="diu_ride_completed_trips.csv"
    )

class CompletedRideCreate(BaseModel):
    rideId: Optional[str] = ""
    driverId: Optional[str] = ""
    driverName: Optional[str] = ""
    passengerId: Optional[str] = ""
    passengerName: Optional[str] = ""
    origin: Optional[str] = ""
    destination: Optional[str] = ""
    pickup: Optional[str] = ""
    startLat: Optional[float] = None
    startLng: Optional[float] = None
    endLat: Optional[float] = None
    endLng: Optional[float] = None
    fare: Optional[float] = 50.0
    rating: Optional[float] = 5.0

@app.post("/ride/api/completed-rides")
@app.post("/api/completed-rides")
async def create_completed_ride(payload: CompletedRideCreate):
    comp_id = f"comp_{int(datetime.utcnow().timestamp()*1000)}"
    now = datetime.utcnow().isoformat()
    origin_name = payload.origin or payload.pickup or "DIU Campus"
    dest_name = payload.destination or "Destination"
    start_maps = f"https://www.google.com/maps/search/?api=1&query={payload.startLat},{payload.startLng}" if payload.startLat and payload.startLng else ""
    end_maps = f"https://www.google.com/maps/search/?api=1&query={payload.endLat},{payload.endLng}" if payload.endLat and payload.endLng else ""

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO completed_rides (
        id, ride_id, driver_id, driver_name, passenger_id, passenger_name,
        origin_name, destination_name, start_time, completed_time, fare,
        start_maps_link, end_maps_link, rating, created_at
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        comp_id, payload.rideId or comp_id, payload.driverId, payload.driverName,
        payload.passengerId, payload.passengerName, origin_name, dest_name,
        now, now, payload.fare or 50.0, start_maps, end_maps, payload.rating or 5.0, now
    ))
    conn.commit()
    cursor.execute("SELECT * FROM completed_rides WHERE id = ?", (comp_id,))
    row = cursor.fetchone()
    conn.close()

    # Also auto-append to CSV
    append_completed_trip_csv({
        "trip_id": comp_id,
        "rider_id": payload.driverId,
        "rider_name": payload.driverName,
        "passenger_id": payload.passengerId,
        "passenger_name": payload.passengerName,
        "origin": origin_name,
        "destination": dest_name,
        "fare": payload.fare or 50.0,
        "start_time": now,
        "start_lat": payload.startLat,
        "start_lng": payload.startLng,
        "start_maps_link": start_maps,
        "end_time": now,
        "end_lat": payload.endLat,
        "end_lng": payload.endLng,
        "end_maps_link": end_maps,
        "completed_time": now,
    })

    return map_completed_ride(row)

# =====================================================================
# REST Endpoints: Social Search & Student Messaging Lookup
# =====================================================================

@app.get("/ride/api/users/search")
@app.get("/api/users/search")
@app.get("/users/search")
def search_users_endpoint(q: str = "", exclude_id: str = ""):
    conn = get_db()
    cursor = conn.cursor()
    clean_q = q.strip()
    query_str = f"%{clean_q}%" if clean_q else "%"
    clean_norm_id = clean_q.replace("-", "").replace(" ", "").upper()
    query_norm_str = f"%{clean_norm_id}%" if clean_norm_id else "%"

    cursor.execute("""
        SELECT id, student_id, name, email, phone, department, batch, rating, is_biker, is_driver_registered, vehicle_info
        FROM users
        WHERE (name LIKE ? 
           OR student_id LIKE ? 
           OR UPPER(REPLACE(student_id, '-', '')) LIKE ?
           OR LOWER(email) LIKE LOWER(?) 
           OR phone LIKE ? 
           OR department LIKE ?)
          AND id != ?
        ORDER BY name ASC
        LIMIT 40
    """, (query_str, query_str, query_norm_str, query_str, query_str, query_str, exclude_id))
    rows = cursor.fetchall()
    results = []
    for r in rows:
        row_dict = dict(r)
        results.append({
            "id": row_dict["id"],
            "student_id": row_dict["student_id"],
            "studentId": row_dict["student_id"],
            "name": row_dict["name"],
            "email": row_dict["email"],
            "phone": row_dict.get("phone") or "",
            "dept": row_dict.get("department") or "DIU",
            "department": row_dict.get("department") or "DIU",
            "batch": row_dict.get("batch") or "",
            "rating": row_dict.get("rating") or 4.9,
            "isBiker": bool(row_dict.get("is_biker") or row_dict.get("is_driver_registered")),
            "isDriver": bool(row_dict.get("is_driver_registered")),
            "vehicleInfo": row_dict.get("vehicle_info") or ""
        })
    conn.close()
    return results

@app.get("/ride/api/users/{user_id}")
@app.get("/api/users/{user_id}")
@app.get("/users/{user_id}")
def get_user_profile_by_id(user_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, student_id, name, email, phone, department, batch, rating, is_biker, is_driver_registered, vehicle_info
        FROM users
        WHERE id = ? OR student_id = ? OR LOWER(email) = LOWER(?)
        LIMIT 1
    """, (user_id, user_id, user_id))
    r = cursor.fetchone()
    if not r:
        norm_sid = user_id.replace("usr_", "").replace("_", "-")
        cursor.execute("""
            SELECT id, student_id, name, email, phone, department, batch, rating, is_biker, is_driver_registered, vehicle_info
            FROM users
            WHERE student_id = ? OR UPPER(REPLACE(student_id, '-', '')) = UPPER(REPLACE(?, '-', ''))
            LIMIT 1
        """, (norm_sid, norm_sid))
        r = cursor.fetchone()

    if not r:
        # Check messages for actual sender_name
        cursor.execute("""
            SELECT sender_name FROM messages 
            WHERE sender_id = ? AND sender_name NOT LIKE 'usr_%' AND sender_name != 'system' 
            ORDER BY id DESC LIMIT 1
        """, (user_id,))
        m_row = cursor.fetchone()
        real_name = m_row["sender_name"] if m_row and m_row["sender_name"] else (f"Student {user_id.replace('usr_', '').replace('_', '-')}" if user_id.startswith('usr_') else "DIU Student")
        norm_sid = user_id.replace("usr_", "").replace("_", "-") if user_id.startswith("usr_") else ""
        conn.close()
        return {
            "id": user_id,
            "student_id": norm_sid,
            "studentId": norm_sid,
            "name": real_name,
            "email": f"{norm_sid}@diu.edu.bd" if norm_sid else "",
            "phone": "",
            "department": "DIU",
            "dept": "DIU",
            "batch": "DIU",
            "rating": 4.9,
            "isBiker": False,
            "isDriver": False,
            "vehicleInfo": ""
        }

    row_dict = dict(r)
    conn.close()
    return {
        "id": row_dict["id"],
        "student_id": row_dict["student_id"],
        "studentId": row_dict["student_id"],
        "name": row_dict["name"],
        "email": row_dict["email"],
        "phone": row_dict.get("phone") or "",
        "department": row_dict.get("department") or "DIU",
        "dept": row_dict.get("department") or "DIU",
        "batch": row_dict.get("batch") or "",
        "rating": row_dict.get("rating") or 4.9,
        "isBiker": bool(row_dict.get("is_biker") or row_dict.get("is_driver_registered")),
        "isDriver": bool(row_dict.get("is_driver_registered")),
        "vehicleInfo": row_dict.get("vehicle_info") or ""
    }

# =====================================================================
# REST Endpoints: Student Ride Requests (Throw / Post Request & Accept)
# =====================================================================

class PassengerRequestPayload(BaseModel):
    passengerId: str
    passengerName: str
    passengerPhone: Optional[str] = ""
    passengerDept: Optional[str] = "CSE"
    pickup: str
    dropoff: str
    requestedTime: str
    proposedFare: Optional[float] = 50.0
    notes: Optional[str] = ""

@app.get("/ride/api/passenger-requests")
@app.get("/api/passenger-requests")
async def get_passenger_requests(
    status: Optional[str] = "open",
    query: Optional[str] = None,
    location: Optional[str] = None,
    exclude_user_id: Optional[str] = None,
    exclude_phone: Optional[str] = None,
):
    try:
        await check_and_cleanup_expired_scheduled_posts()
    except Exception:
        pass

    conn = get_db()
    cursor = conn.cursor()
    _ensure_seed_passenger_requests(cursor)
    conn.commit()
    sql = "SELECT * FROM passenger_requests WHERE 1=1"
    params = []

    if status and status.lower() != "all":
        sql += " AND status = ?"
        params.append(status)

    if query and query.strip():
        q_val = f"%{query.strip().lower()}%"
        sql += """ AND (
            LOWER(pickup) LIKE ? OR LOWER(dropoff) LIKE ? 
            OR LOWER(passenger_name) LIKE ? OR LOWER(passenger_dept) LIKE ? 
            OR LOWER(notes) LIKE ?
        )"""
        params.extend([q_val, q_val, q_val, q_val, q_val])

    if location and location.strip() and location.strip().lower() != "all":
        loc_val = f"%{location.strip().lower()}%"
        sql += " AND (LOWER(pickup) LIKE ? OR LOWER(dropoff) LIKE ?)"
        params.extend([loc_val, loc_val])

    if exclude_user_id:
        sql += " AND (passenger_id != ? AND passenger_id NOT LIKE ?)"
        params.extend([exclude_user_id, f"%{exclude_user_id}%"])

    if exclude_phone:
        clean_p = "".join(filter(str.isdigit, exclude_phone))
        if len(clean_p) >= 8:
            short_p = clean_p[-8:]
            sql += " AND passenger_phone NOT LIKE ?"
            params.append(f"%{short_p}%")
        else:
            sql += " AND passenger_phone != ?"
            params.append(exclude_phone)

    sql += " ORDER BY created_at DESC"
    cursor.execute(sql, params)
    rows = cursor.fetchall()
    conn.close()

    now_local = get_current_bd_time().replace(tzinfo=None)
    valid_requests = []
    for r in rows:
        req_dict = dict(r)
        req_dt = parse_bd_datetime(req_dict.get("requested_time"))
        # Allow a 60-minute grace window past requested time so peers have time to see and accept
        if req_dt and (now_local - req_dt).total_seconds() > 3600:
            continue
        valid_requests.append(map_passenger_request(r))
    return valid_requests

@app.put("/ride/api/passenger-requests/{request_id}")
@app.put("/api/passenger-requests/{request_id}")
@app.patch("/ride/api/passenger-requests/{request_id}")
@app.patch("/api/passenger-requests/{request_id}")
@app.post("/ride/api/passenger-requests/{request_id}/update")
@app.post("/api/passenger-requests/{request_id}/update")
async def update_passenger_request(request_id: str, payload: Dict[str, Any] = Body(...)):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (request_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Passenger request not found")

    pickup = payload.get("pickup") or row["pickup"]
    dropoff = payload.get("dropoff") or row["dropoff"]
    requested_time = payload.get("requestedTime") or payload.get("requested_time") or row["requested_time"]
    proposed_fare = float(payload.get("proposedFare") if "proposedFare" in payload else (payload.get("proposed_fare") if "proposed_fare" in payload else row["proposed_fare"]))
    notes = payload.get("notes") if "notes" in payload else row["notes"]

    cursor.execute("""
        UPDATE passenger_requests
        SET pickup = ?, dropoff = ?, requested_time = ?, proposed_fare = ?, notes = ?
        WHERE id = ?
    """, (pickup, dropoff, requested_time, proposed_fare, notes, request_id))
    conn.commit()

    cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (request_id,))
    updated_row = cursor.fetchone()
    conn.close()

    updated = map_passenger_request(updated_row)
    await manager.broadcast("passenger_request_updated", updated)
    return {"status": "success", "request": updated}

@app.post("/ride/api/passenger-requests/{request_id}/extend-time")
@app.post("/api/passenger-requests/{request_id}/extend-time")
async def extend_passenger_request_time(request_id: str, payload: Dict[str, Any] = Body(...)):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (request_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Passenger request not found")
    
    minutes = int(payload.get("minutes", 30))
    new_requested_time = payload.get("newRequestedTime")
    if not new_requested_time:
        try:
            cur_dt = datetime.fromisoformat(row["requested_time"].replace("Z", "+00:00")).replace(tzinfo=None)
            base_dt = max(datetime.utcnow(), cur_dt)
        except Exception:
            base_dt = datetime.utcnow()
        new_dt = base_dt + timedelta(minutes=minutes)
        new_requested_time = new_dt.isoformat()
    
    now_iso = datetime.utcnow().isoformat()
    cursor.execute("""
        UPDATE passenger_requests 
        SET requested_time = ?, extended_at = ?, extension_prompted = 0, status = 'open'
        WHERE id = ?
    """, (new_requested_time, now_iso, request_id))
    conn.commit()
    cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (request_id,))
    updated_row = cursor.fetchone()
    conn.close()

    updated = map_passenger_request(updated_row)
    await manager.broadcast("passenger_request_updated", updated)
    await manager.broadcast("passenger_request_extended", {
        "id": request_id,
        "requestedTime": new_requested_time,
        "minutes": minutes
    })
    return {"status": "success", "request": updated, "newRequestedTime": new_requested_time}

@app.post("/ride/api/passenger-requests")
@app.post("/api/passenger-requests")
async def create_passenger_request(payload: PassengerRequestPayload):
    if payload.proposedFare <= 0:
        raise HTTPException(status_code=400, detail="Proposed fare must be greater than zero.")
    pickup = (payload.pickup or "").strip()
    dropoff = (payload.dropoff or "").strip()
    if not pickup or not dropoff:
        raise HTTPException(status_code=400, detail="Pickup and dropoff points cannot be empty.")
    if pickup.lower() == dropoff.lower():
        raise HTTPException(status_code=400, detail="Pickup and dropoff cannot be identical.")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    SELECT COUNT(*) FROM passenger_requests 
    WHERE passenger_id = ? AND status = 'open'
    """, (payload.passengerId,))
    if cursor.fetchone()[0] >= 3:
        conn.close()
        raise HTTPException(status_code=400, detail="You already have 3 active open requests. Please wait or cancel an existing one before posting again.")

    req_id = f"preq_{int(datetime.utcnow().timestamp()*1000)}"
    now_bd = get_current_bd_time()
    post_date_str = now_bd.strftime("%Y-%m-%d")
    post_time_str = now_bd.strftime("%I:%M %p")
    now = now_bd.isoformat()
    cursor.execute("""
    INSERT INTO passenger_requests (
        id, passenger_id, passenger_name, passenger_phone, passenger_dept,
        pickup, dropoff, requested_time, proposed_fare, notes, status, created_at,
        post_date, post_time
    ) VALUES (?,?,?,?,?,?,?,?,?,?,'open',?,?,?)
    """, (
        req_id, payload.passengerId, payload.passengerName, payload.passengerPhone,
        payload.passengerDept, payload.pickup, payload.dropoff, payload.requestedTime,
        payload.proposedFare, payload.notes, now, post_date_str, post_time_str
    ))
    conn.commit()
    cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (req_id,))
    row = cursor.fetchone()
    conn.close()

    created = map_passenger_request(row)
    await manager.broadcast("new_passenger_request", created)
    return created

@app.post("/ride/api/passenger-requests/{request_id}/accept")
@app.post("/api/passenger-requests/{request_id}/accept")
async def accept_passenger_request(request_id: str, payload: Dict[str, Any]):
    driver_id = payload.get("driverId", "drv_usr")
    driver_name = payload.get("driverName", "DIU Rider")
    driver_phone = payload.get("driverPhone", "01712345678")
    driver_bike = payload.get("driverBike", "Yamaha FZ-S")
    driver_student_id = payload.get("driverStudentId") or payload.get("studentId") or ""

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (request_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Request not found")
    if row["status"] != "open":
        conn.close()
        raise HTTPException(status_code=409, detail="This ride request has already been accepted or is no longer open.")

    # Block same user accepting their own student request after switching to Biker mode
    if is_same_account(
        left_ids=[row["passenger_id"]],
        right_ids=[driver_id, driver_student_id],
        left_phone=row["passenger_phone"] if "passenger_phone" in row.keys() else "",
        right_phone=driver_phone,
        left_name=row["passenger_name"] if "passenger_name" in row.keys() else "",
        right_name=driver_name,
    ):
        conn.close()
        raise HTTPException(
            status_code=403,
            detail="You cannot accept your own ride request. Switch modes does not let the same account accept itself.",
        )

    cursor.execute("""
    UPDATE passenger_requests SET 
        status = 'accepted',
        accepted_by_driver_id = ?,
        accepted_by_driver_name = ?,
        accepted_by_driver_phone = ?,
        accepted_by_driver_bike = ?
    WHERE id = ? AND status = 'open'
    """, (driver_id, driver_name, driver_phone, driver_bike, request_id))
    if cursor.rowcount == 0:
        conn.close()
        raise HTTPException(status_code=409, detail="This ride request was just accepted by another rider.")
    conn.commit()

    cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (request_id,))
    row = cursor.fetchone()

    now = datetime.utcnow().isoformat()
    fare_val = float(row["proposed_fare"] or 50.0)

    # Ensure matching record exists in `rides` so session tracking and complete-session work without 404!
    cursor.execute("""
    INSERT OR REPLACE INTO rides (
        id, driver_id, driver_name, driver_phone, origin_name, origin_lat, origin_lng, destination_name, destination_lat, destination_lng,
        departure_time, fare_per_seat, total_seats, available_seats, status,
        vehicle_model, vehicle_type, created_at, passenger_id, passenger_name, rider_confirmed, passenger_confirmed
    ) VALUES (?, ?, ?, ?, ?, 23.8765, 90.3204, ?, 23.8071, 90.3686, ?, ?, 1, 0, 'confirmed', ?, 'bike', ?, ?, ?, 1, 1)
    """, (
        request_id, driver_id, driver_name, driver_phone,
        row["pickup"], row["dropoff"], row["requested_time"],
        fare_val, driver_bike, now, row["passenger_id"], row["passenger_name"]
    ))

    # Also insert or replace into `bookings`
    bkg_id = f"bkg_{request_id}"
    cursor.execute("""
    INSERT OR REPLACE INTO bookings (
        id, ride_id, passenger_id, passenger_name, passenger_phone,
        pickup_point, dropoff_point, seats_booked, total_fare, status, requested_at,
        trip_status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, 'accepted', ?, 'confirmed')
    """, (
        bkg_id, request_id, row["passenger_id"], row["passenger_name"],
        row["passenger_phone"], row["pickup"], row["dropoff"],
        fare_val, now
    ))
    conn.commit()
    conn.close()

    updated = map_passenger_request(row)
    # Broadcast acceptance to passenger and all clients!
    await manager.broadcast("passenger_request_accepted", updated)

    # Insert initial automated chat message so both biker and requester see confirmation in chatbox!
    acc_msg = f"🤝 Ride Request Accepted!\n🏍️ Biker: {driver_name} ({driver_bike})\n📍 Route: {row['pickup']} ➔ {row['dropoff']}\n💰 Fare: ৳{fare_val:.0f}\n⏰ Departure: {row['requested_time']}"
    await _save_and_broadcast_message(request_id, {
        "rideId": request_id,
        "senderId": "system",
        "senderName": "DIU Ride System",
        "text": acc_msg,
        "isLocationShare": False,
        "timestamp": now,
    })

    return updated

@app.delete("/ride/api/passenger-requests/{request_id}")
@app.delete("/api/passenger-requests/{request_id}")
@app.delete("/ride/api/passenger-requests")
@app.delete("/api/passenger-requests")
@app.post("/ride/api/passenger-requests/{request_id}/delete")
@app.post("/api/passenger-requests/{request_id}/delete")
@app.post("/ride/api/passenger-requests/delete")
@app.post("/api/passenger-requests/delete")
async def delete_passenger_request_endpoint(
    request_id: Optional[str] = None,
    id: Optional[str] = Query(None),
    request: Request = None
):
    target_id = request_id or id
    if not target_id and request:
        try:
            body = await request.json()
            target_id = body.get("id") or body.get("requestId") or body.get("request_id")
        except Exception:
            pass
    if not target_id:
        raise HTTPException(status_code=400, detail="Missing request_id to delete")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM passenger_requests WHERE id = ?", (target_id,))
    cursor.execute("DELETE FROM rides WHERE id = ?", (target_id,))
    cursor.execute("DELETE FROM bookings WHERE ride_id = ?", (target_id,))
    conn.commit()
    conn.close()

    await manager.broadcast("passenger_request_deleted", {"id": target_id})
    return {"status": "success", "message": f"Passenger request {target_id} deleted successfully", "id": target_id}

@app.post("/ride/api/admin/clear-all-records")
@app.post("/api/admin/clear-all-records")
@app.delete("/ride/api/admin/clear-all-records")
@app.delete("/api/admin/clear-all-records")
async def clear_all_records_endpoint():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM rides")
    cursor.execute("DELETE FROM bookings")
    cursor.execute("DELETE FROM passenger_requests")
    cursor.execute("DELETE FROM messages")
    cursor.execute("DELETE FROM shared_locations")
    cursor.execute("DELETE FROM driver_locations")
    cursor.execute("DELETE FROM sos_alerts")
    conn.commit()
    conn.close()

    await manager.broadcast("rides_cleared", {"status": "cleared", "timestamp": datetime.utcnow().isoformat()})
    print("[ADMIN] All rides, bookings, requests, messages, and locations cleared from database.")
    return {"status": "success", "message": "All ride records and associated data have been purged successfully."}

# =====================================================================
# REST Endpoints: Alert Ring / Sound Trigger
# =====================================================================

@app.post("/ride/api/alert-ring")
@app.post("/api/alert-ring")
async def trigger_alert_ring(payload: Dict[str, Any]):
    sender_name = str(payload.get("senderName", "Campus Rider")).strip()
    sender_id = str(payload.get("senderId", "")).strip()
    target_user_id = str(payload.get("targetUserId", "")).strip()
    target_name = str(payload.get("targetName", "")).strip()
    ride_id = str(payload.get("rideId", "")).strip()
    ring_id = str(payload.get("ringId", f"ring_{int(datetime.utcnow().timestamp()*1000)}")).strip()
    message = str(payload.get("message", f"🚨 Urgent alert from {sender_name}: Please check your phone!")).strip()
    now = datetime.utcnow().isoformat()

    event_data = {
        "event": "alert_ring",
        "type": "alert_ring",
        "ringId": ring_id,
        "senderId": sender_id,
        "senderName": sender_name,
        "targetUserId": target_user_id,
        "targetName": target_name,
        "rideId": ride_id,
        "message": message,
        "timestamp": now,
    }
    await manager.broadcast("alert_ring", event_data)
    print(f"[ALERT-RING] Dispatched buzzer {ring_id} from {sender_name} to {target_user_id} (ride {ride_id})")
    return {"status": "success", "message": "Alert ring buzzer dispatched successfully", "data": event_data}

@app.post("/ride/api/stop-ring")
@app.post("/api/stop-ring")
async def stop_alert_ring(payload: Dict[str, Any]):
    ring_id = str(payload.get("ringId", "")).strip()
    target_user_id = str(payload.get("targetUserId", "")).strip()
    sender_id = str(payload.get("senderId", "")).strip()
    now = datetime.utcnow().isoformat()

    event_data = {
        "event": "stop_ring",
        "type": "stop_ring",
        "ringId": ring_id,
        "targetUserId": target_user_id,
        "senderId": sender_id,
        "timestamp": now,
    }
    await manager.broadcast("stop_ring", event_data)
    print(f"[STOP-RING] Alert ring {ring_id} stopped for {target_user_id} by {sender_id}")
    return {"status": "success", "message": "Alert ring stopped successfully", "data": event_data}

@app.post("/ride/api/admin/clear-all-records")
@app.post("/api/admin/clear-all-records")
async def clear_all_records():
    conn = get_db()
    cursor = conn.cursor()
    tables = [
        "bookings",
        "messages",
        "shared_locations",
        "driver_locations",
        "sos_alerts",
        "passenger_requests",
        "completed_rides",
        "email_otps",
        "rides",
        "users",
    ]
    for table in tables:
        try:
            cursor.execute(f"DELETE FROM {table};")
        except Exception as e:
            print(f"[ADMIN CLEAR] Error deleting {table}: {e}")
    conn.commit()
    conn.close()
    await manager.broadcast("records_cleared", {"timestamp": datetime.utcnow().isoformat()})
    print("[ADMIN CLEAR] Cleared all records across all tables for fresh production deployment.")
    return {"status": "success", "message": "All records purged cleanly."}

# =====================================================================
# REST Endpoints: Bookings
# =====================================================================

BOOKINGS_JOIN_QUERY = """
    SELECT b.*,
           COALESCE(b.driver_id, r.driver_id, cr.driver_id) AS driver_id,
           COALESCE(b.driver_name, r.driver_name, cr.driver_name) AS driver_name,
           COALESCE(b.driver_phone, r.driver_phone) AS driver_phone,
           COALESCE(b.vehicle_model, r.vehicle_model) AS vehicle_model,
           COALESCE(b.departure_time, r.departure_time) AS departure_time,
           COALESCE(b.origin_name, r.origin_name, cr.origin_name) AS origin_name,
           COALESCE(b.destination_name, r.destination_name, cr.destination_name) AS destination_name,
           COALESCE(r.status, 'completed') AS ride_status
    FROM bookings b
    LEFT JOIN rides r ON b.ride_id = r.id
    LEFT JOIN completed_rides cr ON b.ride_id = cr.ride_id
"""

@app.get("/ride/api/bookings")
@app.get("/api/bookings")
def get_bookings(
    passenger_id: Optional[str] = Query(None),
    ride_id: Optional[str] = Query(None),
):
    conn = get_db()
    cursor = conn.cursor()
    if passenger_id and ride_id:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.passenger_id = ? AND b.ride_id = ? ORDER BY b.requested_at DESC", (passenger_id, ride_id))
    elif passenger_id:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.passenger_id = ? ORDER BY b.requested_at DESC", (passenger_id,))
    elif ride_id:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.ride_id = ? ORDER BY b.requested_at DESC", (ride_id,))
    else:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} ORDER BY b.requested_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [map_booking(b) for b in rows]

@app.patch("/ride/api/bookings")
@app.patch("/api/bookings")
async def update_booking_patch(payload: Dict[str, Any]):
    booking_id = payload.get("id")
    status = payload.get("status", "accepted")
    if not booking_id:
        raise HTTPException(status_code=400, detail="Missing booking id")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Booking not found")

    old_status = row["status"]
    seats = row["seats_booked"]
    ride_id = row["ride_id"]

    cursor.execute("UPDATE bookings SET status = ? WHERE id = ?", (status, booking_id))
    # Soft-interest bookings do not deduct seats at request time.
    # Only restore seats if this booking previously locked them (accepted on occupied ride).
    if status in ("cancelled", "rejected") and old_status == "accepted":
        cursor.execute(
            """
            UPDATE rides
            SET available_seats = MIN(total_seats, available_seats + ?),
                status = CASE WHEN status IN ('occupied', 'suspended') THEN 'published' ELSE status END
            WHERE id = ?
            """,
            (seats, ride_id),
        )
    conn.commit()

    cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.id = ?", (booking_id,))
    updated_row = cursor.fetchone()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    conn.close()

    updated = map_booking(updated_row)
    await manager.broadcast("booking_status_updated", updated)
    if ride_row:
        await manager.broadcast("ride_updated", map_ride(ride_row))
    return updated

@app.get("/ride/api/bookings/my-bookings")
@app.get("/api/bookings/my-bookings")
def get_my_bookings(user_id: Optional[str] = Query(None)):
    conn = get_db()
    cursor = conn.cursor()
    if user_id:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.passenger_id = ? ORDER BY b.requested_at DESC", (user_id,))
    else:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} ORDER BY b.requested_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [map_booking(b) for b in rows]

@app.post("/ride/api/bookings")
@app.post("/api/bookings")
async def create_booking(booking_data: Dict[str, Any]):
    ride_id = booking_data.get("rideId")
    if not ride_id:
        raise HTTPException(status_code=400, detail="Missing rideId.")

    try:
        seats = int(booking_data.get("seatsBooked", 1))
    except (ValueError, TypeError):
        raise HTTPException(status_code=400, detail="Invalid seats count.")
    if seats <= 0:
        raise HTTPException(status_code=400, detail="Must book at least 1 seat.")

    passenger_id = str(booking_data.get("passengerId") or "usr_current").strip()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    if not ride_row:
        conn.close()
        raise HTTPException(status_code=404, detail="Ride not found.")

    ride_status = str(ride_row["status"] or "")
    if ride_status in ("occupied", "suspended", "cancelled", "completed"):
        conn.close()
        raise HTTPException(status_code=400, detail="This ride is no longer available for booking.")
    if ride_status not in ("published", "active"):
        conn.close()
        raise HTTPException(status_code=400, detail="This ride is not available for booking.")

    driver_id = str(ride_row["driver_id"] or "").strip()
    driver_phone = str(ride_row["driver_phone"] or "").strip() if "driver_phone" in ride_row.keys() else ""
    driver_name = str(ride_row["driver_name"] or "").strip() if "driver_name" in ride_row.keys() else ""
    passenger_phone = str(booking_data.get("passengerPhone") or "").strip()
    passenger_name = str(booking_data.get("passengerName") or "").strip()
    passenger_student_id = str(booking_data.get("studentId") or booking_data.get("passengerStudentId") or "").strip()
    # Block same user booking their own biker offer after switching to Student mode
    if is_same_account(
        left_ids=[driver_id],
        right_ids=[passenger_id, passenger_student_id],
        left_phone=driver_phone,
        right_phone=passenger_phone,
        left_name=driver_name,
        right_name=passenger_name,
    ):
        conn.close()
        raise HTTPException(
            status_code=403,
            detail="You cannot book a seat on your own ride. Same account cannot accept its own offer after mode switch.",
        )

    # Duplicate check: same passenger cannot place multiple active bookings on the same ride
    cursor.execute("""
    SELECT id FROM bookings 
    WHERE ride_id = ? AND passenger_id = ? AND status IN ('requested', 'accepted')
    """, (ride_id, passenger_id))
    if cursor.fetchone():
        conn.close()
        raise HTTPException(status_code=400, detail="You already have an active booking on this ride.")

    # Soft interest booking: do NOT deduct seats yet.
    # Post stays visible so multiple students can message the biker.
    # Seats lock only after mutual Confirm Ride from chat.
    if int(ride_row["available_seats"] or 0) <= 0:
        conn.close()
        raise HTTPException(status_code=409, detail="This ride has no open seats.")

    booking_id = booking_data.get("id") or f"b_{int(datetime.utcnow().timestamp()*1000)}"

    cursor.execute("""
    INSERT INTO bookings (
        id, ride_id, passenger_id, passenger_name, passenger_photo_url,
        passenger_dept, passenger_phone, pickup_point, dropoff_point,
        seats_booked, total_fare, status, requested_at,
        driver_id, driver_name, driver_phone, vehicle_model,
        departure_time, origin_name, destination_name
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        booking_id,
        ride_id,
        passenger_id,
        booking_data.get("passengerName", "DIU Student"),
        booking_data.get("passengerPhotoUrl"),
        booking_data.get("passengerDept", "CSE"),
        booking_data.get("passengerPhone", "01712345678"),
        booking_data.get("pickupPoint", "Main Gate"),
        booking_data.get("dropoffPoint", "Destination"),
        seats,
        float(booking_data.get("totalFare", 60.0)),
        booking_data.get("status", "requested"),
        datetime.utcnow().isoformat(),
        ride_row["driver_id"] if ride_row else booking_data.get("driverId"),
        ride_row["driver_name"] if ride_row else booking_data.get("driverName"),
        ride_row["driver_phone"] if ride_row else booking_data.get("driverPhone"),
        ride_row["vehicle_model"] if ride_row else booking_data.get("vehicleModel"),
        ride_row["departure_time"] if ride_row else booking_data.get("departureTime"),
        ride_row["origin_name"] if ride_row else booking_data.get("originName"),
        ride_row["destination_name"] if ride_row else booking_data.get("destinationName"),
    ))
    conn.commit()

    cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.id = ?", (booking_id,))
    row = cursor.fetchone()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    updated_ride_row = cursor.fetchone()
    conn.close()

    created = map_booking(row)
    await manager.broadcast("booking_created", created)
    if updated_ride_row:
        try:
            if int(updated_ride_row["available_seats"] or 0) <= 0:
                remove_ride_from_file(ride_id)
            else:
                add_or_update_ride_in_file(dict(updated_ride_row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on booking] {e}")
        # Dedicated notification to driver
        await manager.broadcast("ride_booking_request", {
            "driverId": updated_ride_row["driver_id"],
            "driverName": updated_ride_row["driver_name"],
            "passengerId": created["passengerId"],
            "passengerName": created["passengerName"],
            "pickup": created["pickupPoint"],
            "dropoff": created["dropoffPoint"],
            "seats": created["seatsBooked"],
            "fare": created["totalFare"],
            "rideId": ride_id,
            "bookingId": booking_id,
            "message": f"🔔 New seat booking request from {created['passengerName']}!",
        })
        await manager.broadcast("ride_updated", map_ride(updated_ride_row))

    return created

@app.post("/ride/api/bookings/{booking_id}/accept")
@app.post("/api/bookings/{booking_id}/accept")
async def accept_booking(booking_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE bookings SET status = 'accepted' WHERE id = ?", (booking_id,))
    # Confirm the ride destination on that location where the passenger requested
    cursor.execute("""
        UPDATE rides 
        SET destination_name = COALESCE((SELECT dropoff_point FROM bookings WHERE id = ?), destination_name),
            passenger_id = (SELECT passenger_id FROM bookings WHERE id = ?),
            passenger_name = (SELECT passenger_name FROM bookings WHERE id = ?)
        WHERE id = (SELECT ride_id FROM bookings WHERE id = ?)
    """, (booking_id, booking_id, booking_id, booking_id))
    cursor.execute("""
        SELECT b.*, r.driver_id, r.driver_name, r.origin_name, r.destination_name
        FROM bookings b LEFT JOIN rides r ON b.ride_id = r.id WHERE b.id = ?
    """, (booking_id,))
    row = cursor.fetchone()
    ride_id = row["ride_id"] if row else None
    ride_row = None
    if ride_id:
        cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
        ride_row = cursor.fetchone()
    conn.commit()
    conn.close()
    if ride_row:
        await manager.broadcast("ride_updated", map_ride(ride_row))
    if row:
        updated = map_booking(row)
        await manager.broadcast("booking_status_updated", updated)
        # Dedicated alert to passenger
        await manager.broadcast("ride_booking_accepted", {
            "passengerId": row["passenger_id"],
            "passengerName": row["passenger_name"],
            "driverId": row["driver_id"],
            "driverName": row["driver_name"],
            "rideId": row["ride_id"],
            "bookingId": booking_id,
            "message": f"✅ Rider {row['driver_name']} accepted your ride request! Tap to open chat.",
        })
        return updated
    raise HTTPException(status_code=404, detail="Booking not found")

@app.post("/ride/api/bookings/{booking_id}/reject")
@app.post("/api/bookings/{booking_id}/reject")
async def reject_booking(booking_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Booking not found")

    if row["status"] in ("rejected", "cancelled"):
        conn.close()
        return map_booking(row)

    seats = row["seats_booked"]
    ride_id = row["ride_id"]
    cursor.execute("UPDATE bookings SET status = 'rejected' WHERE id = ?", (booking_id,))
    cursor.execute("UPDATE rides SET available_seats = MIN(total_seats, available_seats + ?) WHERE id = ?", (seats, ride_id))
    conn.commit()

    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    updated_row = cursor.fetchone()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    conn.close()

    updated = map_booking(updated_row)
    await manager.broadcast("booking_status_updated", updated)
    if ride_row:
        try:
            add_or_update_ride_in_file(dict(ride_row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on reject_booking] {e}")
        await manager.broadcast("ride_updated", map_ride(ride_row))
    return updated

@app.delete("/ride/api/bookings/{booking_id}")
@app.delete("/api/bookings/{booking_id}")
async def delete_booking_endpoint(booking_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM bookings WHERE id = ?", (booking_id,))
    conn.commit()
    conn.close()
    await manager.broadcast("booking_deleted", {"id": booking_id})
    return {"status": "success", "message": "Booking record dismissed"}

@app.post("/ride/api/bookings/{booking_id}/cancel")
@app.post("/api/bookings/{booking_id}/cancel")
async def cancel_booking(booking_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Booking not found")

    if row["status"] == "cancelled":
        conn.close()
        return map_booking(row)

    seats = row["seats_booked"]
    ride_id = row["ride_id"]
    cursor.execute("UPDATE bookings SET status = 'cancelled' WHERE id = ?", (booking_id,))
    # Cancel in time: do not delete the post, make the post refreshed with open seats and published status
    cursor.execute("""
        UPDATE rides 
        SET available_seats = MIN(total_seats, available_seats + ?),
            status = 'published',
            rider_confirmed = 0,
            passenger_confirmed = 0,
            passenger_id = NULL,
            passenger_name = NULL
        WHERE id = ?
    """, (seats, ride_id))
    conn.commit()

    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    updated_row = cursor.fetchone()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    conn.close()

    updated = map_booking(updated_row)
    await manager.broadcast("booking_status_updated", updated)
    if ride_row:
        try:
            add_or_update_ride_in_file(dict(ride_row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on cancel_booking] {e}")
        refreshed_ride = map_ride(ride_row)
        await manager.broadcast("ride_updated", refreshed_ride)
        print(f"[BOOKING CANCELLED] Ride {ride_id} refreshed and reopened for booking.")
    return updated

# =====================================================================
# Realtime Ride Session Lifecycle: Two-Way Confirmation, Cancel, Complete
# =====================================================================

def _resolve_ride_and_booking(cursor, raw_id: str, base_id: Optional[str] = None):
    clean_id = (raw_id or "").strip()
    candidates = []
    if clean_id:
        candidates.append(clean_id)
    if base_id and base_id.strip() and base_id.strip() not in candidates:
        candidates.append(base_id.strip())
    if clean_id and "__" in clean_id:
        part = clean_id.split("__")[0].strip()
        if part and part not in candidates:
            candidates.append(part)

    # 1. Check in rides
    for c in candidates:
        cursor.execute("SELECT * FROM rides WHERE id = ?", (c,))
        r = cursor.fetchone()
        if r:
            cursor.execute("SELECT * FROM bookings WHERE ride_id = ? ORDER BY requested_at DESC LIMIT 1", (c,))
            b = cursor.fetchone()
            return (c, r, b, None)

    # 2. Check in passenger_requests
    for c in candidates:
        cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (c,))
        req = cursor.fetchone()
        if req:
            cursor.execute("SELECT * FROM rides WHERE id = ?", (c,))
            r = cursor.fetchone()
            cursor.execute("SELECT * FROM bookings WHERE ride_id = ? ORDER BY requested_at DESC LIMIT 1", (c,))
            b = cursor.fetchone()
            return (c, r, b, req)

    # 3. Check in bookings
    for c in candidates:
        cursor.execute("SELECT * FROM bookings WHERE id = ? OR ride_id = ?", (c, c))
        b = cursor.fetchone()
        if b:
            cursor.execute("SELECT * FROM rides WHERE id = ?", (b["ride_id"],))
            r = cursor.fetchone()
            return (b["ride_id"], r, b, None)

    # 4. Check peer_dm_{u1}__{u2}
    if clean_id.startswith("peer_dm_"):
        raw_peers = clean_id[len("peer_dm_"):]
        peers = raw_peers.split("__")
        if len(peers) == 2:
            u1, u2 = peers[0], peers[1]
            # 4a. Check active booking between the two users
            cursor.execute("""
                SELECT b.id as booking_id, b.ride_id FROM bookings b
                JOIN rides r ON b.ride_id = r.id
                WHERE ((b.passenger_id = ? AND r.driver_id = ?) OR (b.passenger_id = ? AND r.driver_id = ?))
                  AND r.status IN ('published', 'active', 'confirmed', 'in_progress')
                ORDER BY b.requested_at DESC LIMIT 1
            """, (u1, u2, u2, u1))
            b_found = cursor.fetchone()
            if b_found:
                cursor.execute("SELECT * FROM rides WHERE id = ?", (b_found["ride_id"],))
                r = cursor.fetchone()
                cursor.execute("SELECT * FROM bookings WHERE id = ?", (b_found["booking_id"],))
                b = cursor.fetchone()
                if r:
                    return (r["id"], r, b, None)

            # 4b. Check if either user has an active ride or mutually agreed ride
            cursor.execute("""
                SELECT * FROM rides 
                WHERE (driver_id IN (?, ?) AND passenger_id IN (?, ?))
                   OR (driver_id IN (?, ?) AND status IN ('published', 'active', 'confirmed'))
                ORDER BY created_at DESC LIMIT 1
            """, (u1, u2, u1, u2, u1, u2))
            r = cursor.fetchone()
            if r:
                return (r["id"], r, None, None)
            cursor.execute("""
                SELECT * FROM passenger_requests 
                WHERE passenger_id IN (?, ?)
                ORDER BY created_at DESC LIMIT 1
            """, (u1, u2))
            req = cursor.fetchone()
            if req:
                return (req["id"], None, None, req)

    return (clean_id or (base_id or ""), None, None, None)

@app.post("/ride/api/rides/confirm-session")
@app.post("/api/rides/confirm-session")
async def confirm_ride_session(payload: Dict[str, Any]):
    ride_id = str(payload.get("rideId") or payload.get("ride_id") or "").strip()
    base_id = str(payload.get("baseRideId") or "").strip()
    chat_id = str(payload.get("chatId") or "").strip()
    user_id = payload.get("userId", "")
    user_name = payload.get("userName", "Student")
    role = (payload.get("role") or "").lower() # "rider" or "passenger"
    lat = payload.get("latitude")
    lng = payload.get("longitude")

    target_id = ride_id or base_id or chat_id
    if not target_id:
        return {"status": "pending", "message": "Missing rideId"}

    conn = get_db()
    cursor = conn.cursor()
    resolved_id, ride_row, b_row, req_row = _resolve_ride_and_booking(cursor, ride_id, base_id)
    now = datetime.utcnow().isoformat()
    updated = {}

    if ride_row:
        # Determine exact role based on ride owner vs passenger
        if user_id and str(user_id).strip() == str(ride_row["driver_id"]).strip():
            role = "rider"
        elif user_id and str(user_id).strip() == str(ride_row.get("passenger_id") or "").strip():
            role = "passenger"
        elif not role:
            role = "rider" if role in ("biker", "driver") else "passenger"

        rider_conf = int(ride_row["rider_confirmed"] or 0)
        pass_conf = int(ride_row["passenger_confirmed"] or 0)
        if role in ("rider", "driver", "biker"):
            rider_conf = 1
        else:
            pass_conf = 1
        both_confirmed = (rider_conf == 1 and pass_conf == 1)
        start_time = ride_row["start_time"] or (now if both_confirmed else None)

        if both_confirmed:
            start_maps = f"https://www.google.com/maps/search/?api=1&query={lat},{lng}" if lat and lng else ride_row["start_maps_link"]
            cursor.execute("""
                UPDATE rides 
                SET rider_confirmed = ?, passenger_confirmed = ?, status = 'active', start_time = COALESCE(start_time, ?),
                    start_lat = COALESCE(start_lat, ?), start_lng = COALESCE(start_lng, ?), start_maps_link = COALESCE(start_maps_link, ?)
                WHERE id = ?
            """, (rider_conf, pass_conf, now, lat, lng, start_maps, resolved_id))
            cursor.execute("UPDATE bookings SET rider_confirmed = 1, passenger_confirmed = 1, status = 'accepted', trip_status = 'in_progress', started_at = COALESCE(started_at, ?) WHERE ride_id = ?", (now, resolved_id))
        else:
            cursor.execute("""
                UPDATE rides SET rider_confirmed = ?, passenger_confirmed = ? WHERE id = ?
            """, (rider_conf, pass_conf, resolved_id))
            if role in ("rider", "driver"):
                cursor.execute("UPDATE bookings SET rider_confirmed = 1 WHERE ride_id = ?", (resolved_id,))
            else:
                cursor.execute("UPDATE bookings SET passenger_confirmed = 1 WHERE ride_id = ?", (resolved_id,))
        conn.commit()

        cursor.execute("SELECT * FROM rides WHERE id = ?", (resolved_id,))
        updated_row = cursor.fetchone()
        conn.close()
        updated = map_ride(updated_row) if updated_row else {}

    elif req_row:
        req_id = req_row["id"]
        # Determine role: if user is the student who posted request -> passenger, else biker/rider
        if user_id and str(user_id).strip() == str(req_row["passenger_id"]).strip():
            role = "passenger"
        else:
            role = "rider"

        cursor.execute("SELECT * FROM rides WHERE id = ?", (req_id,))
        existing_ride = cursor.fetchone()
        rider_conf = int(existing_ride["rider_confirmed"] or 0) if (existing_ride and "rider_confirmed" in existing_ride.keys()) else 0
        pass_conf = int(existing_ride["passenger_confirmed"] or 0) if (existing_ride and "passenger_confirmed" in existing_ride.keys()) else 0

        if role in ("rider", "driver", "biker"):
            rider_conf = 1
            cursor.execute("""
                UPDATE passenger_requests SET 
                    status = 'accepted',
                    accepted_by_driver_id = ?,
                    accepted_by_driver_name = ?
                WHERE id = ?
            """, (user_id, user_name, req_id))
        else:
            pass_conf = 1

        both_confirmed = (rider_conf == 1 and pass_conf == 1)

        cursor.execute("""
            INSERT OR REPLACE INTO rides (
                id, driver_id, driver_name, driver_phone, origin_name, origin_lat, origin_lng, destination_name, destination_lat, destination_lng,
                departure_time, fare_per_seat, total_seats, available_seats, status,
                vehicle_model, vehicle_type, created_at, passenger_id, passenger_name, rider_confirmed, passenger_confirmed, start_time
            ) VALUES (?, ?, ?, ?, ?, 23.8765, 90.3204, ?, 23.8071, 90.3686, ?, ?, 1, 0, ?, 'Motorbike', 'bike', ?, ?, ?, ?, ?, ?)
        """, (
            req_id,
            user_id if role in ("rider", "driver", "biker") else (existing_ride["driver_id"] if existing_ride else ""),
            user_name if role in ("rider", "driver", "biker") else (existing_ride["driver_name"] if existing_ride else "Campus Rider"),
            "",
            req_row["pickup"], req_row["dropoff"], req_row["requested_time"],
            float(req_row["proposed_fare"] or 50.0),
            'active' if both_confirmed else 'pending',
            now, req_row["passenger_id"], req_row["passenger_name"],
            rider_conf, pass_conf, now if both_confirmed else None
        ))

        cursor.execute("""
            INSERT OR REPLACE INTO bookings (
                id, ride_id, passenger_id, passenger_name, passenger_phone,
                pickup_point, dropoff_point, seats_booked, total_fare, status, requested_at,
                trip_status, rider_confirmed, passenger_confirmed
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?)
        """, (
            f"bkg_{req_id}", req_id, req_row["passenger_id"], req_row["passenger_name"],
            req_row["passenger_phone"], req_row["pickup"], req_row["dropoff"],
            float(req_row["proposed_fare"] or 50.0),
            'accepted' if both_confirmed else 'requested', now,
            'in_progress' if both_confirmed else 'confirmed',
            rider_conf, pass_conf
        ))
        conn.commit()
        conn.close()
        start_time = now if both_confirmed else None
    else:
        cursor.execute("SELECT * FROM conversations WHERE id = ?", (target_id,))
        conv = cursor.fetchone()
        if conv:
            rider_conf = int(conv["rider_confirmed"] or 0)
            pass_conf = int(conv["passenger_confirmed"] or 0)
            if role in ("rider", "driver", "biker"):
                rider_conf = 1
            else:
                pass_conf = 1
            both_confirmed = (rider_conf == 1 and pass_conf == 1)
            cursor.execute("""
                UPDATE conversations SET
                    rider_confirmed = ?, passenger_confirmed = ?,
                    session_state = ?
                WHERE id = ?
            """, (rider_conf, pass_conf, 'bothConfirmed' if both_confirmed else 'awaitingConfirm', target_id))
            conn.commit()
        else:
            rider_conf = 1 if role in ("rider", "driver", "biker") else 0
            pass_conf = 1 if role not in ("rider", "driver", "biker") else 0
            both_confirmed = False
        conn.close()
        start_time = now if both_confirmed else None

    if both_confirmed:
        sys_msg = f"🚀 Both Rider and Passenger confirmed! Ready to ride! Trip officially started. Live timer is running."
    else:
        sys_msg = f"✅ {user_name} ({role.title()}) confirmed the ride! Waiting for peer confirmation."

    channels_to_notify = {target_id, ride_id, base_id, chat_id, resolved_id} - {"", None}
    for ch in channels_to_notify:
        await _save_and_broadcast_message(ch, {
            "rideId": ch,
            "senderId": "system",
            "senderName": "DIU Ride System",
            "text": sys_msg,
            "isLocationShare": False,
            "timestamp": now,
        })

    if not both_confirmed:
        peer_prompt = {
            "type": "ride_acceptance_prompt",
            "rideId": ride_id or resolved_id,
            "baseRideId": base_id or resolved_id,
            "chatId": chat_id,
            "senderId": user_id,
            "senderName": user_name,
            "role": role,
            "message": f"🔔 {user_name} রাইড এক্সেপ্ট করেছেন! কনফার্ম করতে আপনিও Accept করুন।",
            "title": "Ride Acceptance Required",
        }
        await manager.broadcast("ride_acceptance_prompt", peer_prompt)
        await manager.broadcast("push_notification", peer_prompt)

    session_event = {
        "rideId": ride_id or resolved_id,
        "baseRideId": base_id or resolved_id,
        "chatId": chat_id,
        "riderConfirmed": bool(rider_conf),
        "passengerConfirmed": bool(pass_conf),
        "bothConfirmed": both_confirmed,
        "status": "in_progress" if both_confirmed else "pending",
        "startTime": start_time or now,
        "updaterId": user_id,
        "updaterName": user_name,
        "role": role,
    }
    await manager.broadcast("ride_session_status_changed", session_event)
    if updated:
        await manager.broadcast("ride_updated", updated)

    return session_event

@app.post("/ride/api/rides/cancel-session")
@app.post("/api/rides/cancel-session")
async def cancel_ride_session(payload: Dict[str, Any]):
    ride_id = str(payload.get("rideId") or payload.get("ride_id") or "").strip()
    base_id = str(payload.get("baseRideId") or "").strip()
    chat_id = str(payload.get("chatId") or "").strip()
    user_id = payload.get("userId", "")
    user_name = payload.get("userName", "Student")
    role = (payload.get("role") or "passenger").lower()
    reason = payload.get("reason", "Fare not agreed / Contact not made")

    target_id = ride_id or base_id or chat_id
    if not target_id:
        return {"status": "cancelled", "isClosed": True, "cancelReason": reason}

    conn = get_db()
    cursor = conn.cursor()
    resolved_id, ride_row, b_row, req_row = _resolve_ride_and_booking(cursor, ride_id, base_id)
    now = datetime.utcnow().isoformat()
    refreshed_ride_row = None

    if ride_row:
        # Cancel in time: do not delete the post, make the post refreshed for new passengers!
        cursor.execute("""
            UPDATE rides 
            SET status = 'published',
                available_seats = total_seats,
                rider_confirmed = 0,
                passenger_confirmed = 0,
                passenger_id = NULL,
                passenger_name = NULL,
                start_time = NULL,
                start_maps_link = NULL,
                cancel_reason = ? 
            WHERE id = ?
        """, (reason, resolved_id))
        cursor.execute("UPDATE bookings SET status = 'cancelled', trip_status = 'cancelled', cancel_reason = ? WHERE ride_id = ?", (reason, resolved_id))
        conn.commit()

        cursor.execute("SELECT * FROM rides WHERE id = ?", (resolved_id,))
        refreshed_ride_row = cursor.fetchone()

        # Save cancel event to CSV
        append_completed_trip_csv({
            "trip_id": f"canc_{resolved_id}_{int(datetime.utcnow().timestamp())}",
            "rider_id": ride_row["driver_id"],
            "rider_name": ride_row["driver_name"],
            "rider_phone": ride_row["driver_phone"] if "driver_phone" in ride_row.keys() else "",
            "passenger_id": b_row["passenger_id"] if b_row else (ride_row["passenger_id"] if "passenger_id" in ride_row.keys() else ""),
            "passenger_name": b_row["passenger_name"] if b_row else (ride_row["passenger_name"] if "passenger_name" in ride_row.keys() else ""),
            "passenger_phone": b_row["passenger_phone"] if b_row else "",
            "origin": ride_row["origin_name"],
            "destination": ride_row["destination_name"],
            "fare": float(ride_row["fare_per_seat"]),
            "start_time": ride_row["start_time"] or now,
            "end_time": now,
            "status": "cancelled",
            "cancel_reason": reason,
            "total_duration_minutes": 0.0,
            "completed_time": now,
        })

    if req_row:
        # If it was a student passenger request, reset it back to open so other bikers can take it!
        req_id = req_row["id"]
        cursor.execute("""
            UPDATE passenger_requests SET 
                status = 'open',
                accepted_by_driver_id = NULL,
                accepted_by_driver_name = NULL,
                accepted_by_driver_phone = NULL,
                accepted_by_driver_bike = NULL
            WHERE id = ?
        """, (req_id,))
        cursor.execute("UPDATE bookings SET status = 'cancelled', trip_status = 'cancelled', cancel_reason = ? WHERE ride_id = ?", (reason, req_id))
        cursor.execute("UPDATE rides SET status = 'cancelled', cancel_reason = ? WHERE id = ?", (reason, req_id))
        conn.commit()

        cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (req_id,))
        refreshed_req = cursor.fetchone()
        if refreshed_req:
            await manager.broadcast("passenger_request_updated", map_passenger_request(refreshed_req))

    conn.close()

    # System message: post to all relevant channel IDs
    sys_msg = f"❌ DEAL CLOSED: Trip deal was cancelled by {user_name} ({role.title()}). Reason: {reason}. Deal is now closed for both parties."
    channels_to_notify = {target_id, ride_id, base_id, chat_id, resolved_id} - {"", None}
    for ch in channels_to_notify:
        await _save_and_broadcast_message(ch, {
            "rideId": ch,
            "senderId": "system",
            "senderName": "DIU Ride System",
            "text": sys_msg,
            "isLocationShare": False,
            "timestamp": now,
        })

    session_event = {
        "rideId": ride_id or resolved_id,
        "baseRideId": base_id or resolved_id,
        "chatId": chat_id,
        "status": "cancelled",
        "isClosed": True,
        "cancelReason": reason,
        "cancelledBy": user_name,
        "role": role,
    }
    await manager.broadcast("ride_session_status_changed", session_event)
    await manager.broadcast("booking_status_updated", {
        "id": (b_row["id"] if b_row else (ride_id or resolved_id)),
        "rideId": resolved_id or ride_id,
        "status": "cancelled",
        "cancelReason": reason,
    })
    await manager.broadcast("booking_cancelled", {
        "id": (b_row["id"] if b_row else (ride_id or resolved_id)),
        "rideId": resolved_id or ride_id,
    })

    if refreshed_ride_row:
        try:
            add_or_update_ride_in_file(dict(refreshed_ride_row))
            await manager.broadcast("ride_updated", map_ride(refreshed_ride_row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on cancel_session] {e}")

    return session_event

@app.post("/ride/api/rides/complete-session")
@app.post("/api/rides/complete-session")
async def complete_ride_session(payload: Dict[str, Any]):
    ride_id = str(payload.get("rideId") or payload.get("ride_id") or "").strip()
    base_id = str(payload.get("baseRideId") or "").strip()
    chat_id = str(payload.get("chatId") or "").strip()
    user_id = payload.get("userId", "")
    user_name = payload.get("userName", "Student")
    role = (payload.get("role") or "companion").lower()
    lat = payload.get("latitude")
    lng = payload.get("longitude")

    target_id = ride_id or base_id or chat_id
    if not target_id:
        return {"status": "completed", "isClosed": True}

    conn = get_db()
    cursor = conn.cursor()
    resolved_id, ride_row, b_row, req_row = _resolve_ride_and_booking(cursor, ride_id, base_id)
    now = datetime.utcnow().isoformat()
    duration_mins = 15.0

    if ride_row:
        start_t_str = ride_row["start_time"] or now
        try:
            dt_start = datetime.fromisoformat(start_t_str.replace("Z", "+00:00"))
            dt_end = datetime.fromisoformat(now.replace("Z", "+00:00"))
            duration_mins = max(1.0, round((dt_end - dt_start).total_seconds() / 60.0, 1))
        except Exception:
            duration_mins = 15.0

        end_maps = f"https://www.google.com/maps/search/?api=1&query={lat},{lng}" if lat and lng else ""

        cursor.execute("""
            UPDATE rides 
            SET status = 'completed', end_time = ?, end_lat = COALESCE(?, end_lat), end_lng = COALESCE(?, end_lng),
                end_maps_link = COALESCE(?, end_maps_link), total_duration_minutes = ?
            WHERE id = ?
        """, (now, lat, lng, end_maps, duration_mins, resolved_id))

        cursor.execute("""
            UPDATE bookings 
            SET status = 'completed', trip_status = 'completed', completed_at = ?, total_duration_minutes = ?,
                end_lat = COALESCE(?, end_lat), end_lng = COALESCE(?, end_lng)
            WHERE ride_id = ?
        """, (now, duration_mins, lat, lng, resolved_id))
        conn.commit()

        if not b_row:
            cursor.execute("SELECT passenger_id, passenger_name, passenger_phone, total_fare FROM bookings WHERE ride_id = ? LIMIT 1", (resolved_id,))
            b_row = cursor.fetchone()
        p_id = b_row["passenger_id"] if b_row else ""
        p_name = b_row["passenger_name"] if b_row else ""
        p_phone = b_row["passenger_phone"] if b_row else ""
        fare = float(b_row["total_fare"]) if b_row else float(ride_row["fare_per_seat"])

        # Resolve verified varsity student details for driver & passenger
        cursor.execute("SELECT student_id, department, phone FROM users WHERE id = ? OR student_id = ? OR email = ?", (ride_row["driver_id"], ride_row["driver_id"], ride_row["driver_id"]))
        u_drv = cursor.fetchone()
        driver_sid = u_drv["student_id"] if u_drv and u_drv["student_id"] else (ride_row["driver_id"] if "-" in str(ride_row["driver_id"]) else "")
        driver_dept = u_drv["department"] if u_drv and u_drv["department"] else "DIU Student"
        driver_phone = (ride_row["driver_phone"] if "driver_phone" in ride_row.keys() else None) or (u_drv["phone"] if u_drv else "")

        cursor.execute("SELECT student_id, department, phone FROM users WHERE id = ? OR student_id = ? OR email = ?", (p_id, p_id, p_id))
        u_pass = cursor.fetchone()
        passenger_sid = u_pass["student_id"] if u_pass and u_pass["student_id"] else (p_id if "-" in str(p_id) else "")
        passenger_dept = u_pass["department"] if u_pass and u_pass["department"] else "DIU Student"
        passenger_phone = p_phone or (u_pass["phone"] if u_pass else "")

        # Always construct full Google Maps directions route link
        import urllib.parse
        o_q = f"{ride_row['start_lat']},{ride_row['start_lng']}" if (ride_row.get("start_lat") is not None and ride_row.get("start_lng") is not None) else urllib.parse.quote(ride_row["origin_name"])
        d_q = f"{lat},{lng}" if (lat is not None and lng is not None) else urllib.parse.quote(ride_row["destination_name"])
        route_maps_link = f"https://www.google.com/maps/dir/?api=1&origin={o_q}&destination={d_q}&travelmode=driving"

        tracking_notes = (
            f"DIU Campus Commute Log: {ride_row['origin_name']} ➔ {ride_row['destination_name']}. "
            f"Biker: {ride_row['driver_name']} (ID: {driver_sid or 'N/A'}, Dept: {driver_dept}, Ph: {driver_phone}). "
            f"Passenger: {p_name or 'Student'} (ID: {passenger_sid or 'N/A'}, Dept: {passenger_dept}, Ph: {passenger_phone}). "
            f"Duration: {duration_mins:.0f} mins. Status: Safely Completed."
        )

        comp_id = f"comp_{resolved_id}_{int(datetime.utcnow().timestamp())}"
        cursor.execute("""
            INSERT OR REPLACE INTO completed_rides (
                id, ride_id, driver_id, driver_name, passenger_id, passenger_name,
                origin_name, destination_name, start_time, completed_time, fare,
                start_maps_link, end_maps_link, rating, feedback, created_at,
                driver_phone, driver_dept, driver_student_id,
                passenger_phone, passenger_dept, passenger_student_id,
                route_maps_link, duration_minutes, tracking_notes
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (
            comp_id, resolved_id, ride_row["driver_id"], ride_row["driver_name"], p_id, p_name,
            ride_row["origin_name"], ride_row["destination_name"], start_t_str, now,
            fare, ride_row["start_maps_link"], end_maps, 5.0, "", now,
            driver_phone, driver_dept, driver_sid,
            passenger_phone, passenger_dept, passenger_sid,
            route_maps_link, duration_mins, tracking_notes
        ))
        conn.commit()

        # Update CSV log
        append_completed_trip_csv({
            "trip_id": comp_id,
            "rider_id": ride_row["driver_id"],
            "rider_name": ride_row["driver_name"],
            "rider_phone": driver_phone,
            "passenger_id": p_id,
            "passenger_name": p_name,
            "passenger_phone": passenger_phone,
            "origin": ride_row["origin_name"],
            "destination": ride_row["destination_name"],
            "fare": fare,
            "start_time": start_t_str,
            "start_lat": ride_row["start_lat"],
            "start_lng": ride_row["start_lng"],
            "start_maps_link": ride_row["start_maps_link"],
            "end_time": now,
            "end_lat": lat,
            "end_lng": lng,
            "end_maps_link": end_maps,
            "total_duration_minutes": duration_mins,
            "route_maps_link": route_maps_link,
            "completed_time": now,
        })

        # Update ride row to completed (preserved for trip history & My Rides)
        conn.commit()
        try:
            remove_ride_from_file(resolved_id)
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on complete_ride_session] {e}")

        # Resolve traversed landmarks along DIU corridor
        cursor.execute("SELECT DISTINCT landmark_name FROM trip_route_points WHERE ride_id = ? AND landmark_name IS NOT NULL", (resolved_id,))
        traversed_lm = [r["landmark_name"] for r in cursor.fetchall() if r["landmark_name"]]
        if not traversed_lm:
            traversed_lm = get_canonical_route_landmarks(ride_row['origin_name'], ride_row['destination_name'])
        traversed_str = " ➔ ".join(traversed_lm)

        pdf_link = f"https://servertest.eu.cc/ride/api/rides/{resolved_id}/route-passport-pdf"

        # Automated chat message
        try:
            time_formatted = datetime.fromisoformat(now.replace("Z", "+00:00")).strftime("%I:%M %p, %b %d")
        except Exception:
            time_formatted = now
        sys_msg = (
            f"🏁 DIU Commute Completed & Verified!\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📍 Corridor: {ride_row['origin_name']} ➔ {ride_row['destination_name']}\n"
            f"🗺️ Traversed Route: {traversed_str}\n"
            f"⏱️ Duration: {duration_mins:.0f} min(s) | 💰 Total Fare: ৳{fare:.0f}\n"
            f"🏍️ Biker: {ride_row['driver_name']} ({driver_dept}) • {driver_phone or 'Verified'}\n"
            f"🎒 Passenger: {p_name or 'Student'} ({passenger_dept}) • {passenger_phone or 'Verified'}\n\n"
            f"📄 Official Commute Route Passport (PDF):\n"
            f"{pdf_link}\n\n"
            f"🗺️ View Google Maps Route & Directions:\n"
            f"{route_maps_link}\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━"
        )

    elif req_row:
        req_id = req_row["id"]
        fare = float(req_row["proposed_fare"] or 50.0)
        cursor.execute("UPDATE passenger_requests SET status = 'completed' WHERE id = ?", (req_id,))
        cursor.execute("UPDATE bookings SET status = 'completed', trip_status = 'completed', completed_at = ? WHERE ride_id = ?", (now, req_id))
        conn.commit()

        # Build directions route link for custom student gig request
        import urllib.parse
        p_q = urllib.parse.quote(str(req_row.get('pickup') or 'DIU Permanent Campus'))
        d_q = urllib.parse.quote(str(req_row.get('dropoff') or 'Mirpur 10'))
        route_maps_link = f"https://www.google.com/maps/dir/?api=1&origin={p_q}&destination={d_q}&travelmode=driving"

        comp_id = f"comp_{req_id}_{int(datetime.utcnow().timestamp())}"
        tracking_notes = f"DIU Custom Gig Commute: {req_row.get('pickup')} ➔ {req_row.get('dropoff')}. Completed safely."
        cursor.execute("""
            INSERT OR REPLACE INTO completed_rides (
                id, ride_id, driver_id, driver_name, passenger_id, passenger_name,
                origin_name, destination_name, start_time, completed_time, fare,
                start_maps_link, end_maps_link, rating, feedback, created_at,
                driver_phone, driver_dept, driver_student_id,
                passenger_phone, passenger_dept, passenger_student_id,
                route_maps_link, duration_minutes, tracking_notes
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (
            comp_id, req_id, user_id or "driver", user_name or "DIU Biker", req_row.get("passenger_id", ""), req_row.get("passenger_name", "Student"),
            req_row.get("pickup", "Pickup"), req_row.get("dropoff", "Dropoff"), req_row.get("created_at", now), now,
            fare, "", "", 5.0, "", now,
            "", "DIU Biker", "",
            "", "DIU Student", "",
            route_maps_link, 15.0, tracking_notes
        ))
        conn.commit()

        sys_msg = (
            f"🏁 DIU Commute Completed & Verified!\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📍 Route: {req_row.get('pickup')} ➔ {req_row.get('dropoff')}\n"
            f"💰 Fare: ৳{fare:.0f}\n\n"
            f"🗺️ View Google Maps Route & Directions:\n"
            f"{route_maps_link}\n\n"
            f"📝 Campus Tracking Notes: Student Custom Gig Completed Safely.\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━"
        )
    else:
        fare = 50.0
        sys_msg = f"🏁 Trip Completed!\nCompleted by {user_name} ({role.title()}). Deal closed successfully."

    conn.close()

    channels_to_notify = {target_id, ride_id, base_id, chat_id, resolved_id} - {"", None}
    # Also notify the canonical 1-on-1 DM channel between biker and passenger
    if ride_row and ride_row["driver_id"] and p_id and ride_row["driver_id"] != p_id:
        pair = sorted([str(ride_row["driver_id"]).lower().strip(), str(p_id).lower().strip()])
        channels_to_notify.add(f"peer_dm_{pair[0]}__{pair[1]}")
    for ch in channels_to_notify:
        await _save_and_broadcast_message(ch, {
            "rideId": ch,
            "senderId": "system",
            "senderName": "DIU Ride System",
            "text": sys_msg,
            "isLocationShare": False,
            "timestamp": now,
        })

    session_event = {
        "rideId": ride_id or resolved_id,
        "baseRideId": base_id or resolved_id,
        "chatId": chat_id,
        "status": "completed",
        "totalDurationMinutes": duration_mins,
        "completedAt": now,
        "fare": fare,
        "completedBy": user_name,
        "role": role,
    }
    await manager.broadcast("ride_session_status_changed", session_event)
    await manager.broadcast("ride_completed", session_event)
    await manager.broadcast("booking_status_updated", {"rideId": resolved_id, "status": "completed"})

    return session_event


DIU_CORRIDOR_LANDMARKS = [
    # Campus Hub & Ashulia
    ("DIU Smart City, Ashulia", 23.8765, 90.3204),
    ("Khagan", 23.8820, 90.3150),
    ("Akran", 23.8790, 90.3230),
    ("Charabag", 23.8750, 90.2980),
    ("Ashulia Bazar", 23.9050, 90.3250),
    ("Birulia", 23.8690, 90.3340),
    ("Birulia Bridge", 23.8665, 90.3390),
    ("Panchabati", 23.8620, 90.3420),

    # Northern & Airport Corridor (Uttara, Airport, Kuril)
    ("Diabari", 23.8730, 90.3650),
    ("Uttara North", 23.8760, 90.3800),
    ("Uttara Sector 10", 23.8740, 90.3870),
    ("House Building", 23.8680, 90.3950),
    ("Azampur", 23.8600, 90.4000),
    ("Airport", 23.8500, 90.4050),
    ("Khilkhet", 23.8310, 90.4180),
    ("Kuril Biswa Road", 23.8180, 90.4220),

    # Eastern & Tech Hub Corridor (Banani, Gulshan, Mohakhali, Badda)
    ("Banani", 23.7940, 90.4040),
    ("Gulshan 2", 23.7930, 90.4150),
    ("Gulshan 1", 23.7780, 90.4170),
    ("Mohakhali", 23.7780, 90.4000),
    ("Badda Link Road", 23.7810, 90.4260),
    ("Rampura", 23.7620, 90.4230),

    # Mirpur & Metro Line-6 Corridor
    ("Pallabi", 23.8245, 90.3654),
    ("Mirpur 12", 23.8280, 90.3640),
    ("Mirpur 11", 23.8180, 90.3660),
    ("Mirpur 10", 23.8070, 90.3686),
    ("Mirpur 2", 23.8020, 90.3580),
    ("Mirpur 1", 23.7960, 90.3530),
    ("Kazipara", 23.7990, 90.3730),
    ("Shewrapara", 23.7900, 90.3750),
    ("Agargaon", 23.7780, 90.3780),

    # Central & South Corridor (Farmgate, Shahbagh, Motijheel)
    ("Bijoy Sarani", 23.7650, 90.3860),
    ("Farmgate", 23.7570, 90.3890),
    ("Karwan Bazar", 23.7510, 90.3930),
    ("Shahbagh", 23.7380, 90.3960),
    ("Dhaka University", 23.7330, 90.3930),
    ("Curzon Hall", 23.7270, 90.4010),
    ("High Court", 23.7290, 90.4040),
    ("Paltan", 23.7330, 90.4130),
    ("Motijheel", 23.7320, 90.4180),
    ("Kamalapur", 23.7330, 90.4250),
    ("Sayedabad", 23.7150, 90.4280),

    # Western Corridor (Gabtoli, Dhanmondi, Mohammadpur)
    ("Aminbazar", 23.7850, 90.3320),
    ("Gabtoli", 23.7830, 90.3450),
    ("Technical Mor", 23.7790, 90.3520),
    ("Kalyanpur", 23.7780, 90.3620),
    ("Shyamoli", 23.7720, 90.3660),
    ("Asad Gate", 23.7600, 90.3720),
    ("Mohammadpur", 23.7580, 90.3620),
    ("Dhanmondi 27", 23.7540, 90.3740),
    ("Dhanmondi 32", 23.7510, 90.3780),
    ("Science Lab", 23.7390, 90.3840),
    ("New Market", 23.7340, 90.3850),
    ("Azimpur", 23.7280, 90.3860),

    # Savar, EPZ, Chandra Corridor
    ("Savar Cantonment", 23.8960, 90.2850),
    ("Savar Bazar Stand", 23.8480, 90.2610),
    ("Thana Stand", 23.8440, 90.2580),
    ("Hemayetpur", 23.7980, 90.2720),
    ("C&B Stand", 23.8670, 90.2680),
    ("Jahangirnagar University", 23.8820, 90.2670),
    ("Nabinagar", 23.9180, 90.2630),
    ("Baipayl", 23.9450, 90.2780),
    ("DEPZ", 23.9580, 90.2820),
    ("Zirani", 23.9740, 90.2450),
    ("Chandra", 23.9980, 90.2280),

    # Gazipur & Tongi Corridor
    ("Abdullahpur", 23.8780, 90.4010),
    ("Tongi", 23.8980, 90.4050),
    ("Station Road Tongi", 23.9050, 90.4060),
    ("Board Bazar", 23.9550, 90.3880),
    ("Gazipur Chowrasta", 23.9920, 90.3800),
    ("Shibbari", 24.0040, 90.4120),
]

def detect_nearest_landmark(lat: float, lng: float, max_dist_km: float = 1.8) -> Optional[str]:
    import math
    best_name = None
    min_d = max_dist_km
    for name, lm_lat, lm_lng in DIU_CORRIDOR_LANDMARKS:
        d = math.sqrt(((lat - lm_lat) * 111.0) ** 2 + ((lng - lm_lng) * 111.0 * math.cos(math.radians(lat))) ** 2)
        if d < min_d:
            min_d = d
            best_name = name
    return best_name

def get_canonical_route_landmarks(origin: str, dest: str) -> List[str]:
    """
    Generates realistic traversed corridor milestones for ANY route across Dhaka/Savar/Gazipur.
    """
    orig_l = (origin or "").lower()
    dest_l = (dest or "").lower()

    landmarks = []
    # 1. Starting Landmark
    if "khagan" in orig_l:
        landmarks.append("Khagan")
    elif "savar" in orig_l:
        landmarks.append("Savar")
    elif "uttara" in orig_l:
        landmarks.append("Uttara")
    else:
        landmarks.append("DIU Smart City")

    # 2. Corridor Routing Detection based on Destination
    if any(k in dest_l for k in ["motijheel", "paltan", "shahbagh", "dhaka university", "curzon", "kamalapur", "sayedabad"]):
        # Central & Southern Dhaka Arterial
        landmarks.extend(["Khagan", "Birulia", "Agargaon", "Farmgate", "Shahbagh"])
        if "dhaka university" in dest_l or "curzon" in dest_l:
            landmarks.append("Dhaka University")
        landmarks.append("Motijheel")

    elif any(k in dest_l for k in ["dhanmondi", "mohammadpur", "shyamoli", "science lab", "new market", "kalyanpur", "gabtoli"]):
        # Western Arterial
        landmarks.extend(["Khagan", "Gabtoli", "Shyamoli", "Asad Gate"])
        if "mohammadpur" in dest_l:
            landmarks.append("Mohammadpur")
        landmarks.append("Dhanmondi")
        if any(k in dest_l for k in ["science lab", "new market", "azimpur"]):
            landmarks.append("Science Lab")

    elif any(k in dest_l for k in ["savar", "nabinagar", "baipayl", "depz", "zirani", "chandra", "jahangirnagar", "hemayetpur"]):
        # Savar / Western Highway Arterial
        landmarks.extend(["Khagan", "Charabag", "Savar Bazar"])
        if any(k in dest_l for k in ["jahangirnagar", "ju"]):
            landmarks.append("Jahangirnagar University")
        if any(k in dest_l for k in ["nabinagar", "baipayl", "depz", "chandra"]):
            landmarks.append("Nabinagar")
            landmarks.append("Baipayl / EPZ")
        if "chandra" in dest_l or "zirani" in dest_l:
            landmarks.append("Chandra")

    elif any(k in dest_l for k in ["gazipur", "tongi", "board bazar", "chowrasta", "shibbari", "abdullahpur"]):
        # Northern Gazipur Arterial
        landmarks.extend(["Ashulia Bazar", "Abdullahpur", "Tongi", "Board Bazar", "Gazipur Chowrasta"])

    elif any(k in dest_l for k in ["banani", "gulshan", "mohakhali", "badda", "rampura", "kuril", "bashundhara"]):
        # Eastern Tech Hub Arterial
        landmarks.extend(["Khagan", "Birulia", "Diabari", "Uttara", "Kuril", "Banani"])
        if "gulshan" in dest_l:
            landmarks.append("Gulshan")
        elif "mohakhali" in dest_l:
            landmarks.append("Mohakhali")
        elif "badda" in dest_l or "rampura" in dest_l:
            landmarks.append("Badda / Rampura")

    elif any(k in dest_l for k in ["mirpur", "kazipara", "shewrapara", "agargaon", "ecb"]):
        # Mirpur & Metro Line-6 Arterial
        landmarks.extend(["Khagan", "Akran", "Birulia", "Pallabi", "Mirpur 12", "Mirpur 10"])
        if any(k in dest_l for k in ["kazipara", "shewrapara", "agargaon"]):
            landmarks.append("Agargaon")

    elif any(k in dest_l for k in ["uttara", "diabari", "panchabati", "airport", "khilkhet"]):
        # Uttara & Diabari Arterial
        landmarks.extend(["Khagan", "Akran", "Birulia", "Panchabati", "Diabari", "Uttara North"])
        if "airport" in dest_l:
            landmarks.append("Airport")
        elif "khilkhet" in dest_l:
            landmarks.append("Khilkhet")

    elif "pallabi" in dest_l:
        landmarks.extend(["Khagan", "Akran", "Birulia", "Panchabati", "Diabari", "Pallabi"])

    else:
        # Dynamic Clean Fallback for Any Location
        landmarks.extend(["Khagan", "Birulia Bridge"])
        clean_dest = dest.split(",")[0].strip()
        if clean_dest:
            landmarks.append(clean_dest)

    # Deduplicate while strictly preserving order
    seen = set()
    result = []
    for lm in landmarks:
        norm = lm.lower().strip()
        if norm not in seen:
            seen.add(norm)
            result.append(lm)
    return result

@app.post("/ride/api/rides/{ride_id}/record-gps")
@app.post("/api/rides/{ride_id}/record-gps")
async def record_trip_gps(ride_id: str, payload: Dict[str, Any]):
    user_id = str(payload.get("userId") or "").strip()
    role = str(payload.get("role") or "rider").lower()
    lat = float(payload.get("latitude") or 0.0)
    lng = float(payload.get("longitude") or 0.0)

    if lat == 0.0 or lng == 0.0:
        return {"status": "ignored", "reason": "invalid_coordinates"}

    lm = detect_nearest_landmark(lat, lng)
    now = datetime.utcnow().isoformat()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO trip_route_points (ride_id, user_id, role, latitude, longitude, landmark_name, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (ride_id, user_id, role, lat, lng, lm, now))
    conn.commit()
    conn.close()

    # Broadcast location update via WebSocket
    await manager.broadcast({
        "event": "trip_gps_point",
        "rideId": ride_id,
        "userId": user_id,
        "role": role,
        "latitude": lat,
        "longitude": lng,
        "landmark": lm,
        "timestamp": now,
    })

    return {"status": "recorded", "landmark": lm, "timestamp": now}

@app.get("/ride/api/rides/{ride_id}/route-trajectory")
@app.get("/api/rides/{ride_id}/route-trajectory")
def get_ride_trajectory(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT latitude, longitude, landmark_name, role, created_at
        FROM trip_route_points
        WHERE ride_id = ?
        ORDER BY id ASC
    """, (ride_id,))
    rows = cursor.fetchall()

    points = []
    detected_landmarks = []
    seen_lm = set()
    for r in rows:
        points.append({
            "lat": r["latitude"],
            "lng": r["longitude"],
            "role": r["role"],
            "landmark": r["landmark_name"],
            "time": r["created_at"]
        })
        lm = r["landmark_name"]
        if lm and lm not in seen_lm:
            seen_lm.add(lm)
            detected_landmarks.append(lm)

    # If no live GPS points were recorded yet, synthesize canonical corridor
    if not detected_landmarks:
        cursor.execute("SELECT origin_name, destination_name FROM rides WHERE id = ?", (ride_id,))
        ride_info = cursor.fetchone()
        if ride_info:
            detected_landmarks = get_canonical_route_landmarks(ride_info["origin_name"], ride_info["destination_name"])
        else:
            detected_landmarks = ["DIU Smart City", "Khagan", "Akran", "Birulia", "Panchabati", "Uttara"]

    conn.close()
    return {
        "rideId": ride_id,
        "landmarks": detected_landmarks,
        "routeSummary": " ➔ ".join(detected_landmarks),
        "totalPoints": len(points),
        "points": points
    }

@app.get("/ride/api/rides/{ride_id}/route-passport-pdf")
@app.get("/api/rides/{ride_id}/route-passport-pdf")
def get_commute_passport_pdf(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()

    # 1. Look up ride
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()

    # 2. Look up booking
    cursor.execute("SELECT * FROM bookings WHERE ride_id = ? ORDER BY id DESC LIMIT 1", (ride_id,))
    b_row = cursor.fetchone()

    # 3. Look up trajectory landmarks
    cursor.execute("SELECT DISTINCT landmark_name FROM trip_route_points WHERE ride_id = ? AND landmark_name IS NOT NULL", (ride_id,))
    lm_rows = cursor.fetchall()
    traversed_lm = [r["landmark_name"] for r in lm_rows if r["landmark_name"]]

    driver_name = ride_row["driver_name"] if ride_row else "Rahat Mahamud"
    driver_id = ride_row["driver_id"] if ride_row else "usr_252_15_234"
    driver_phone = ride_row["driver_phone"] if ride_row else "01777085732"
    origin = ride_row["origin_name"] if ride_row else "DIU Smart City, Ashulia"
    destination = ride_row["destination_name"] if ride_row else "Uttara North Commute"
    fare = float(ride_row["fare_per_seat"] or 70.0) if ride_row else 70.0
    start_t = ride_row["start_time"] if ride_row and "start_time" in ride_row.keys() else None
    end_t = ride_row["end_time"] if ride_row and "end_time" in ride_row.keys() else None
    vehicle = f"{ride_row['vehicle_model']} ({ride_row['vehicle_plate'] or 'DIU Verified'})" if ride_row else "Yamaha FZ-X 150 (Dhaka Metro Ha 12-3456)"

    passenger_name = b_row["passenger_name"] if b_row else "Abud Hasan"
    passenger_id = b_row["passenger_id"] if b_row else "usr_253_15_789"
    passenger_phone = b_row["passenger_phone"] if b_row else "01888123456"

    # Normalize student IDs
    d_sid = driver_id.replace("usr_", "").replace("_", "-") if driver_id.startswith("usr_") else driver_id
    p_sid = passenger_id.replace("usr_", "").replace("_", "-") if passenger_id.startswith("usr_") else passenger_id

    if not traversed_lm:
        traversed_lm = get_canonical_route_landmarks(origin, destination)

    conn.close()

    pdf_bytes = generate_commute_passport_pdf(
        ride_id=ride_id,
        driver_name=driver_name,
        driver_student_id=d_sid,
        driver_phone=driver_phone,
        passenger_name=passenger_name,
        passenger_student_id=p_sid,
        passenger_phone=passenger_phone,
        traversed_landmarks=traversed_lm,
        origin=origin,
        destination=destination,
        fare=fare,
        start_time=start_t,
        end_time=end_t,
        distance_km=12.5,
        vehicle_info=vehicle,
    )

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'inline; filename="commute_passport_{ride_id}.pdf"',
            "Cache-Control": "no-cache",
        }
    )

@app.get("/ride/api/rides/{ride_id}/session-status")
@app.get("/api/rides/{ride_id}/session-status")
def get_ride_session_status(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()

    def _get_aliases(uid: str):
        u_clean = uid.lower().strip()
        cursor.execute("SELECT id, student_id, email, name FROM users WHERE LOWER(id)=? OR LOWER(student_id)=? OR LOWER(email)=?", (u_clean, u_clean, u_clean))
        u_r = cursor.fetchone()
        aliases = {u_clean}
        if u_r:
            if u_r["id"]: aliases.add(str(u_r["id"]).lower().strip())
            if u_r["student_id"]: aliases.add(str(u_r["student_id"]).lower().strip())
            if u_r["email"]: aliases.add(str(u_r["email"]).lower().strip())
            if u_r["name"]: aliases.add(str(u_r["name"]).lower().strip())
        return aliases

    # If peer DM, check if an active ride booking or accepted request connects them
    if ride_id.startswith("peer_dm_"):
        dm_clean = ride_id[len("peer_dm_"):]
        p_parts = dm_clean.split("__")
        if len(p_parts) >= 2:
            u1_set = _get_aliases(p_parts[0])
            u2_set = _get_aliases(p_parts[1])
            u1_ph = ",".join("?" * len(u1_set))
            u2_ph = ",".join("?" * len(u2_set))

            # 1. Check for active booking between u1 and u2
            query = f"""
                SELECT r.id FROM rides r
                JOIN bookings b ON r.id = b.ride_id
                WHERE ((LOWER(r.driver_id) IN ({u1_ph}) AND LOWER(b.passenger_id) IN ({u2_ph}))
                    OR (LOWER(r.driver_id) IN ({u2_ph}) AND LOWER(b.passenger_id) IN ({u1_ph})))
                  AND r.status NOT IN ('completed', 'cancelled')
                  AND b.status NOT IN ('completed', 'cancelled', 'declined', 'rejected')
                ORDER BY r.created_at DESC LIMIT 1
            """
            params = list(u1_set) + list(u2_set) + list(u2_set) + list(u1_set)
            cursor.execute(query, params)
            active_b = cursor.fetchone()
            if active_b:
                conn.close()
                return get_ride_session_status(active_b["id"])

            # 2. Check for active passenger request between u1 and u2
            query2 = f"""
                SELECT id FROM passenger_requests
                WHERE ((LOWER(accepted_by_driver_id) IN ({u1_ph}) AND LOWER(passenger_id) IN ({u2_ph}))
                    OR (LOWER(accepted_by_driver_id) IN ({u2_ph}) AND LOWER(passenger_id) IN ({u1_ph})))
                  AND status NOT IN ('completed', 'cancelled', 'declined')
                ORDER BY created_at DESC LIMIT 1
            """
            cursor.execute(query2, params)
            active_req = cursor.fetchone()
            if active_req:
                conn.close()
                return get_ride_session_status(active_req["id"])

        conn.close()
        return {
            "rideId": ride_id,
            "resolvedRideId": None,
            "hasActiveTrip": False,
            "status": "none",
            "rawStatus": "none",
            "riderConfirmed": False,
            "passengerConfirmed": False,
            "bothConfirmed": False,
            "startTime": None,
            "endTime": None,
            "origin": "",
            "destination": "",
            "fare": 0.0,
            "driverId": "",
            "driverName": "",
            "driverPhone": "",
            "passengerId": "",
            "passengerName": "",
            "passengerPhone": "",
            "totalDurationMinutes": 0.0,
            "cancelReason": "",
        }

    resolved_id, ride_row, b_row, req_row = _resolve_ride_and_booking(cursor, ride_id)
    
    if ride_row:
        if not b_row:
            cursor.execute("SELECT * FROM bookings WHERE ride_id = ? ORDER BY requested_at DESC LIMIT 1", (resolved_id,))
            b_row = cursor.fetchone()
        conn.close()

        r_conf = bool(ride_row["rider_confirmed"]) if ("rider_confirmed" in ride_row.keys() and ride_row["rider_confirmed"]) else False
        p_conf = bool(ride_row["passenger_confirmed"]) if ("passenger_confirmed" in ride_row.keys() and ride_row["passenger_confirmed"]) else False
        status = ride_row["status"]
        booking_status = b_row["status"] if b_row else "none"

        is_completed = status == "completed" or booking_status == "completed"
        is_cancelled = status == "cancelled" or booking_status in ("cancelled", "declined", "rejected")

        if status in ("active", "in_progress") or (ride_row["start_time"] and not is_completed and not is_cancelled):
            session_status = "in_progress"
            r_conf = True
            p_conf = True
        elif is_completed:
            session_status = "completed"
        elif is_cancelled:
            session_status = "cancelled"
        elif booking_status in ("confirmed", "accepted") and (r_conf and p_conf):
            session_status = "confirmed"
        elif booking_status in ("confirmed", "accepted") or (r_conf or p_conf):
            session_status = "accepted"
        else:
            session_status = "pending"

        has_active = not is_completed and not is_cancelled

        return {
            "rideId": ride_id,
            "resolvedRideId": resolved_id,
            "hasActiveTrip": has_active,
            "status": session_status,
            "rawStatus": status,
            "riderConfirmed": r_conf,
            "passengerConfirmed": p_conf,
            "bothConfirmed": r_conf and p_conf,
            "startTime": ride_row["start_time"],
            "endTime": ride_row["end_time"],
            "origin": ride_row["origin_name"],
            "destination": ride_row["destination_name"],
            "fare": float(ride_row["fare_per_seat"]),
            "driverId": ride_row["driver_id"],
            "driverName": ride_row["driver_name"],
            "driverPhone": ride_row["driver_phone"] if "driver_phone" in ride_row.keys() else "",
            "passengerId": b_row["passenger_id"] if b_row else (ride_row["passenger_id"] if "passenger_id" in ride_row.keys() else ""),
            "passengerName": b_row["passenger_name"] if b_row else (ride_row["passenger_name"] if "passenger_name" in ride_row.keys() else ""),
            "passengerPhone": b_row["passenger_phone"] if b_row else "",
            "totalDurationMinutes": float(ride_row["total_duration_minutes"] or 0.0) if ("total_duration_minutes" in ride_row.keys() and ride_row["total_duration_minutes"]) else 0.0,
            "cancelReason": ride_row["cancel_reason"] if ("cancel_reason" in ride_row.keys()) else "",
        }

    if req_row:
        cursor.execute("SELECT * FROM rides WHERE id = ?", (resolved_id,))
        r_assoc = cursor.fetchone()
        conn.close()

        r_conf = bool(r_assoc["rider_confirmed"]) if (r_assoc and "rider_confirmed" in r_assoc.keys() and r_assoc["rider_confirmed"]) else False
        p_conf = bool(r_assoc["passenger_confirmed"]) if (r_assoc and "passenger_confirmed" in r_assoc.keys() and r_assoc["passenger_confirmed"]) else False
        
        req_status = req_row["status"]
        is_completed = req_status == "completed" or (r_assoc and r_assoc["status"] == "completed")
        is_cancelled = req_status in ("cancelled", "declined") or (r_assoc and r_assoc["status"] == "cancelled")
        is_accepted = bool(req_row["accepted_by_driver_id"] or req_status == "accepted" or r_conf)

        both_conf = (r_conf and p_conf) or (r_assoc and r_assoc["status"] == "active")
        session_status = "in_progress" if both_conf else ("completed" if is_completed else ("cancelled" if is_cancelled else ("accepted" if is_accepted else "pending")))
        has_active = not is_completed and not is_cancelled
        return {
            "rideId": ride_id,
            "resolvedRideId": resolved_id,
            "hasActiveTrip": has_active,
            "status": session_status,
            "rawStatus": req_status,
            "riderConfirmed": r_conf or is_accepted,
            "passengerConfirmed": p_conf,
            "bothConfirmed": both_conf,
            "startTime": req_row["requested_time"],
            "endTime": None,
            "origin": req_row["pickup"],
            "destination": req_row["dropoff"],
            "fare": float(req_row["proposed_fare"] or 50.0),
            "driverId": req_row["accepted_by_driver_id"] or (r_assoc["driver_id"] if r_assoc else ""),
            "driverName": req_row["accepted_by_driver_name"] or (r_assoc["driver_name"] if r_assoc else "Campus Rider"),
            "driverPhone": "",
            "passengerId": req_row["passenger_id"] or "",
            "passengerName": req_row["passenger_name"] or "",
            "passengerPhone": req_row["passenger_phone"] or "",
            "totalDurationMinutes": 0.0,
            "cancelReason": "",
        }

    conn.close()
    return {
        "rideId": ride_id,
        "resolvedRideId": resolved_id,
        "hasActiveTrip": False,
        "status": "none",
        "rawStatus": "none",
        "riderConfirmed": False,
        "passengerConfirmed": False,
        "bothConfirmed": False,
        "startTime": None,
        "endTime": None,
        "origin": "",
        "destination": "",
        "fare": 0.0,
        "driverId": "",
        "driverName": "",
        "driverPhone": "",
        "passengerId": "",
        "passengerName": "",
        "passengerPhone": "",
        "totalDurationMinutes": 0.0,
        "cancelReason": "",
    }

# =====================================================================
# REST Endpoints: Campus News Feed & Student Community
# =====================================================================

@app.get("/ride/api/feed")
@app.get("/api/feed")
def get_campus_feed(author_id: Optional[str] = None, user_id: Optional[str] = None):
    conn = get_db()
    cursor = conn.cursor()
    
    # Auto-delete posts older than 1 week (7 days)
    cutoff_dt = (datetime.utcnow() - timedelta(days=7)).isoformat()
    cursor.execute("SELECT id FROM campus_feed_posts WHERE created_at < ?", (cutoff_dt,))
    expired_posts = cursor.fetchall()
    if expired_posts:
        for exp in expired_posts:
            pid = exp["id"]
            cursor.execute("DELETE FROM campus_feed_posts WHERE id = ?", (pid,))
            cursor.execute("DELETE FROM campus_feed_likes WHERE post_id = ?", (pid,))
            cursor.execute("DELETE FROM campus_feed_comments WHERE post_id = ?", (pid,))
        conn.commit()

    if author_id:
        cursor.execute("SELECT * FROM campus_feed_posts WHERE author_id = ? ORDER BY created_at DESC", (author_id,))
    else:
        cursor.execute("SELECT * FROM campus_feed_posts ORDER BY created_at DESC")
    rows = cursor.fetchall()
    
    posts = []
    for r in rows:
        p_dict = dict(r)
        if "image_url" not in p_dict or p_dict["image_url"] is None:
            p_dict["image_url"] = ""
        # Guarantee both user_id and author_id are available
        p_dict["user_id"] = p_dict.get("author_id") or ""
        has_liked = False
        if user_id:
            cursor.execute("SELECT 1 FROM campus_feed_likes WHERE post_id = ? AND user_id = ?", (r["id"], user_id))
            has_liked = cursor.fetchone() is not None
        p_dict["has_liked"] = has_liked
        posts.append(p_dict)
    conn.close()
    return posts

@app.post("/ride/api/feed")
@app.post("/api/feed")
async def create_campus_post(payload: Dict[str, Any]):
    content = (payload.get("content") or "").strip()
    image_url = (payload.get("imageUrl") or payload.get("image_url") or "").strip()
    if not content and not image_url:
        raise HTTPException(status_code=400, detail="Post content or image cannot be empty")
    
    author_id = payload.get("authorId") or payload.get("author_id", "anon")
    author_name = payload.get("authorName") or payload.get("author_name", "Student")
    author_dept = payload.get("authorDept") or payload.get("author_dept", "CSE")
    author_student_id = payload.get("authorStudentId") or payload.get("author_student_id", "")
    category = payload.get("category", "General")
    
    post_id = f"post_{int(datetime.utcnow().timestamp() * 1000)}"
    now = datetime.utcnow().isoformat()
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO campus_feed_posts (id, author_id, author_name, author_dept, author_student_id, content, category, image_url, likes_count, comments_count, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?)
    """, (post_id, author_id, author_name, author_dept, author_student_id, content, category, image_url, now))
    conn.commit()
    conn.close()
    
    new_post = {
        "id": post_id,
        "author_id": author_id,
        "author_name": author_name,
        "author_dept": author_dept,
        "author_student_id": author_student_id,
        "content": content,
        "category": category,
        "image_url": image_url,
        "likes_count": 0,
        "comments_count": 0,
        "created_at": now,
        "has_liked": False
    }
    await manager.broadcast("campus_feed_new_post", new_post)
    return {"status": "success", "post": new_post}

@app.post("/ride/api/feed/{post_id}/like")
@app.post("/api/feed/{post_id}/like")
async def toggle_post_like(post_id: str, payload: Dict[str, Any]):
    user_id = payload.get("userId") or payload.get("user_id", "")
    if not user_id:
        raise HTTPException(status_code=400, detail="Missing userId")
        
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT 1 FROM campus_feed_likes WHERE post_id = ? AND user_id = ?", (post_id, user_id))
    already_liked = cursor.fetchone() is not None
    
    if already_liked:
        cursor.execute("DELETE FROM campus_feed_likes WHERE post_id = ? AND user_id = ?", (post_id, user_id))
        cursor.execute("UPDATE campus_feed_posts SET likes_count = MAX(0, likes_count - 1) WHERE id = ?", (post_id,))
        liked = False
    else:
        cursor.execute("INSERT OR REPLACE INTO campus_feed_likes (post_id, user_id) VALUES (?, ?)", (post_id, user_id))
        cursor.execute("UPDATE campus_feed_posts SET likes_count = likes_count + 1 WHERE id = ?", (post_id,))
        liked = True
        
    conn.commit()
    cursor.execute("SELECT likes_count FROM campus_feed_posts WHERE id = ?", (post_id,))
    row = cursor.fetchone()
    count = row["likes_count"] if row else 0
    conn.close()
    
    update_data = {"postId": post_id, "likesCount": count, "hasLiked": liked, "userId": user_id}
    await manager.broadcast("campus_feed_like_updated", update_data)
    return {"status": "success", "has_liked": liked, "likes_count": count}

@app.get("/ride/api/feed/{post_id}/comments")
@app.get("/api/feed/{post_id}/comments")
def get_post_comments(post_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM campus_feed_comments WHERE post_id = ? ORDER BY created_at ASC", (post_id,))
    rows = cursor.fetchall()
    comments = []
    for r in rows:
        d = dict(r)
        d["comment_text"] = d.get("content", "")
        d["user_id"] = d.get("author_id", "")
        comments.append(d)
    conn.close()
    return {"status": "success", "total": len(comments), "comments": comments}

@app.post("/ride/api/feed/{post_id}/comments")
@app.post("/api/feed/{post_id}/comments")
async def add_post_comment(post_id: str, payload: Dict[str, Any]):
    text = (payload.get("content") or payload.get("comment_text") or payload.get("text") or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Comment text cannot be empty")
        
    author_id = payload.get("authorId") or payload.get("author_id") or payload.get("user_id") or "anon"
    author_name = payload.get("authorName") or payload.get("author_name") or "DIU Student"
    author_dept = payload.get("authorDept") or payload.get("author_dept") or payload.get("author_department") or "CSE"
    comment_id = f"cmt_{int(datetime.utcnow().timestamp() * 1000)}"
    now = datetime.utcnow().isoformat()
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO campus_feed_comments (id, post_id, author_id, author_name, author_dept, content, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (comment_id, post_id, author_id, author_name, author_dept, text, now))
    cursor.execute("UPDATE campus_feed_posts SET comments_count = comments_count + 1 WHERE id = ?", (post_id,))
    conn.commit()
    cursor.execute("SELECT comments_count FROM campus_feed_posts WHERE id = ?", (post_id,))
    row_count = cursor.fetchone()
    count = row_count["comments_count"] if row_count else 1
    conn.close()
    
    comment_obj = {
        "id": comment_id,
        "post_id": post_id,
        "author_id": author_id,
        "user_id": author_id,
        "author_name": author_name,
        "author_dept": author_dept,
        "content": text,
        "comment_text": text,
        "created_at": now
    }
    await manager.broadcast("campus_feed_comment_added", {
        "postId": post_id,
        "post_id": post_id,
        "comment": comment_obj,
        "commentsCount": count,
        "comments_count": count
    })
    return {"status": "success", "comment": comment_obj, "comments_count": count}

@app.delete("/ride/api/feed/{post_id}")
@app.delete("/api/feed/{post_id}")
async def delete_campus_post(post_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM campus_feed_posts WHERE id = ?", (post_id,))
    cursor.execute("DELETE FROM campus_feed_likes WHERE post_id = ?", (post_id,))
    cursor.execute("DELETE FROM campus_feed_comments WHERE post_id = ?", (post_id,))
    conn.commit()
    conn.close()
    await manager.broadcast("campus_feed_post_deleted", {"postId": post_id})
    return {"status": "success", "deleted_id": post_id}

# =====================================================================
# REST Endpoints: Chat & Realtime Messaging
# =====================================================================

def get_channel_id(ride_id: str, u1: str, u2: str) -> str:
    """Computes a deterministic, isolated 1-on-1 channel ID between two users for a given ride."""
    if not u1 or not u2 or str(u1).strip().lower() == str(u2).strip().lower():
        return ride_id
    base = ride_id.split('__')[0] if '__' in ride_id else ride_id
    pair = sorted([str(u1).strip().lower(), str(u2).strip().lower()])
    return f"{base}__{pair[0]}__{pair[1]}"

def _fetch_messages(target_ride_id: Optional[str]):
    """Fetch messages strictly for the given ride_id/channel_id only.
    No cross-ride or cross-peer joining — each 1-on-1 conversation is isolated."""
    conn = get_db()
    cursor = conn.cursor()
    if not target_ride_id:
        cursor.execute("SELECT * FROM messages ORDER BY timestamp ASC")
        rows = cursor.fetchall()
        conn.close()
        return [map_message(m) for m in rows]

    if target_ride_id.startswith("peer_dm_"):
        dm_clean = target_ride_id[len("peer_dm_"):]
        p_parts = dm_clean.split("__")
        if len(p_parts) >= 2:
            u1, u2 = p_parts[0], p_parts[1]
            cursor.execute(
                """
                SELECT * FROM messages 
                WHERE ride_id = ? 
                   OR ride_id LIKE ? 
                   OR ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))
                ORDER BY timestamp ASC
                """,
                (target_ride_id, f"%__{u1}__{u2}%", u1, u2, u2, u1)
            )
        else:
            cursor.execute("SELECT * FROM messages WHERE ride_id = ? ORDER BY timestamp ASC", (target_ride_id,))
    elif "__" in target_ride_id:
        parts = target_ride_id.split("__")
        if len(parts) >= 3:
            base_id = parts[0]
            u1 = parts[1]
            u2 = parts[2]
            cursor.execute(
                """
                SELECT * FROM messages 
                WHERE ride_id = ? 
                   OR (ride_id = ? AND ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)))
                   OR ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))
                ORDER BY timestamp ASC
                """,
                (target_ride_id, base_id, u1, u2, u2, u1, u1, u2, u2, u1)
            )
        elif len(parts) == 2:
            u1 = parts[0]
            u2 = parts[1]
            cursor.execute(
                """
                SELECT * FROM messages 
                WHERE ride_id = ? 
                   OR ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))
                ORDER BY timestamp ASC
                """,
                (target_ride_id, u1, u2, u2, u1)
            )
        else:
            cursor.execute("SELECT * FROM messages WHERE ride_id = ? ORDER BY timestamp ASC", (target_ride_id,))
    else:
        cursor.execute(
            "SELECT * FROM messages WHERE ride_id = ? OR ride_id LIKE ? ORDER BY timestamp ASC",
            (target_ride_id, f"{target_ride_id}__%")
        )
    rows = cursor.fetchall()
    if not rows and target_ride_id and not target_ride_id.startswith("peer_dm_") and "__" not in target_ride_id:
        cursor.execute("SELECT driver_id, passenger_id FROM rides WHERE id = ?", (target_ride_id,))
        r_info = cursor.fetchone()
        if r_info and r_info["driver_id"] and r_info["passenger_id"]:
            u1, u2 = r_info["driver_id"], r_info["passenger_id"]
            cursor.execute(
                """
                SELECT * FROM messages 
                WHERE ride_id = ? 
                   OR ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))
                ORDER BY timestamp ASC
                """,
                (f"peer_dm_{min(u1, u2)}__{max(u1, u2)}", u1, u2, u2, u1)
            )
            rows = cursor.fetchall()

    conn.close()
    return [map_message(m) for m in rows]

async def _save_and_broadcast_message(target_ride_id: str, msg_data: Dict[str, Any]):
    msg_id = msg_data.get("id") or f"msg_{int(datetime.utcnow().timestamp()*1000)}"
    text = msg_data.get("text", "")
    is_loc = bool(msg_data.get("isLocationShare", False))
    shared_lat = msg_data.get("sharedLat")
    shared_lng = msg_data.get("sharedLng")
    sender_id = str(msg_data.get("senderId", "usr_anonymous")).strip()
    receiver_id = str(msg_data.get("receiverId", "")).strip() or None
    message_type = msg_data.get("messageType", "text")
    ride_event = msg_data.get("rideEvent")
    ride_event_at = msg_data.get("rideEventAt")

    conn = get_db()
    cursor = conn.cursor()

    # Determine the two human users involved: user_a and user_b
    user_a = None
    user_b = None

    if target_ride_id.startswith("peer_dm_"):
        dm_clean = target_ride_id[len("peer_dm_"):]
        p_parts = dm_clean.split("__")
        if len(p_parts) >= 2:
            u1, u2 = p_parts[0].lower().strip(), p_parts[1].lower().strip()
            if sender_id and sender_id != "system":
                if sender_id.lower().strip() == u1:
                    user_a, user_b = u1, u2
                    if not receiver_id or receiver_id == "system": receiver_id = u2
                else:
                    user_a, user_b = u2, u1
                    if not receiver_id or receiver_id == "system": receiver_id = u1
            else:
                user_a, user_b = u1, u2
                if not receiver_id or receiver_id == "system": receiver_id = u2
    elif "__" in target_ride_id:
        parts = target_ride_id.split("__")
        if len(parts) >= 3:
            u1, u2 = parts[1].lower().strip(), parts[2].lower().strip()
            user_a, user_b = u1, u2
            if not receiver_id or receiver_id == "system":
                receiver_id = u2 if sender_id == u1 else u1
    elif target_ride_id and not target_ride_id.startswith("peer_dm_") and target_ride_id != "ride_general":
        cursor.execute("SELECT driver_id FROM rides WHERE id = ?", (target_ride_id,))
        r_row = cursor.fetchone()
        if r_row:
            driver_id = str(r_row["driver_id"]).lower().strip()
            cursor.execute("SELECT passenger_id FROM bookings WHERE ride_id = ? ORDER BY requested_at DESC LIMIT 1", (target_ride_id,))
            b_row = cursor.fetchone()
            if b_row:
                pass_id = str(b_row["passenger_id"]).lower().strip()
                user_a, user_b = driver_id, pass_id
                if not receiver_id or receiver_id == "system":
                    receiver_id = pass_id if sender_id.lower().strip() == driver_id else driver_id
        else:
            cursor.execute("SELECT passenger_id, accepted_by_driver_id FROM passenger_requests WHERE id = ?", (target_ride_id,))
            pr_row = cursor.fetchone()
            if pr_row and pr_row["accepted_by_driver_id"]:
                driver_id = str(pr_row["accepted_by_driver_id"]).lower().strip()
                pass_id = str(pr_row["passenger_id"]).lower().strip()
                user_a, user_b = driver_id, pass_id
                if not receiver_id or receiver_id == "system":
                    receiver_id = pass_id if sender_id.lower().strip() == driver_id else driver_id

    # Fallback to sender_id and receiver_id if both are human users
    if (not user_a or not user_b) and sender_id and receiver_id and sender_id != "system" and receiver_id != "system":
        user_a = sender_id.lower().strip()
        user_b = receiver_id.lower().strip()

    # Compute canonical channel and conversation ID
    if user_a and user_b and user_a != user_b and user_a != "system" and user_b != "system":
        # Resolve canonical user IDs
        cursor.execute("SELECT id FROM users WHERE LOWER(id)=? OR LOWER(student_id)=? OR LOWER(email)=?", (user_a, user_a, user_a))
        ua_row = cursor.fetchone()
        if ua_row: user_a = str(ua_row["id"]).lower()

        cursor.execute("SELECT id FROM users WHERE LOWER(id)=? OR LOWER(student_id)=? OR LOWER(email)=?", (user_b, user_b, user_b))
        ub_row = cursor.fetchone()
        if ub_row: user_b = str(ub_row["id"]).lower()

        pair = sorted([user_a, user_b])
        # Canonical Messenger-style thread id (same for A→B and B→A)
        channel_id = f"peer_dm_{pair[0]}__{pair[1]}"
        conv_id = channel_id
    else:
        channel_id = target_ride_id
        conv_id = target_ride_id

    # If sharing location, automatically ensure Google Maps link is included in text if not present
    if is_loc and shared_lat is not None and shared_lng is not None:
        maps_url = f"https://www.google.com/maps/search/?api=1&query={shared_lat},{shared_lng}"
        if "google.com/maps" not in text and "maps.google.com" not in text:
            text = f"📍 Shared Live GPS Location: {maps_url}"

    msg_timestamp = msg_data.get("timestamp", datetime.utcnow().isoformat())

    # Resolve sender's exact registered profile name from users table
    sender_name = msg_data.get("senderName")
    if sender_id and sender_id != "system":
        u_row = cursor.execute(
            "SELECT name FROM users WHERE id = ? OR student_id = ? OR LOWER(email) = LOWER(?)",
            (sender_id, sender_id, sender_id)
        ).fetchone()
        if u_row and u_row["name"]:
            sender_name = u_row["name"]

    if not sender_name or str(sender_name).strip() in ("Me", "DIU Student", "Commuter", "null", "undefined", ""):
        sender_name = "DIU Student"

    sender_mode = str(msg_data.get("senderMode") or msg_data.get("sender_mode") or "chat").lower()

    # Receiver messages start unread (Messenger/WhatsApp style)
    is_system = sender_id.lower() in ("system", "diu ride system")
    msg_is_read = 1 if is_system else 0

    cursor.execute("""
    INSERT OR REPLACE INTO messages (
        id, ride_id, conversation_id, sender_id, sender_name, receiver_id, text, timestamp,
        is_read, is_location_share, shared_lat, shared_lng, message_type, ride_event, ride_event_at, sender_mode
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        msg_id,
        channel_id,
        conv_id,
        sender_id,
        sender_name,
        receiver_id,
        text,
        msg_timestamp,
        msg_is_read,
        1 if is_loc else 0,
        shared_lat,
        shared_lng,
        message_type,
        ride_event,
        ride_event_at,
        sender_mode,
    ))

    # Update conversations table (ONLY FOR THE TWO REAL HUMAN USERS, NEVER 'system')
    if user_a and user_b and user_a != user_b and user_a != "system" and user_b != "system":
        pair = sorted([user_a, user_b])
        cursor.execute("""
            INSERT OR IGNORE INTO conversations (id, user_a_id, user_b_id, ride_id, context_type, created_at)
            VALUES (?, ?, ?, ?, 'ride', ?)
        """, (conv_id, pair[0], pair[1], channel_id, msg_timestamp))
        # Also merge legacy hash-id rows onto canonical peer_dm id if present
        cursor.execute("""
            UPDATE conversations SET last_message=?, last_message_at=?, last_sender_id=?,
                ride_id=COALESCE(NULLIF(?, ''), ride_id)
            WHERE id=? OR id=?
        """, (text[:120], msg_timestamp, sender_id, target_ride_id if target_ride_id != channel_id else channel_id, conv_id, conv_id))

        # Increment unread for the peer (not the sender)
        sender_l = sender_id.lower().strip()
        if not is_system:
            if sender_l == pair[0]:
                cursor.execute("UPDATE conversations SET unread_b = COALESCE(unread_b,0) + 1 WHERE id = ?", (conv_id,))
            elif sender_l == pair[1]:
                cursor.execute("UPDATE conversations SET unread_a = COALESCE(unread_a,0) + 1 WHERE id = ?", (conv_id,))
            else:
                # sender matched alias of user_a or user_b
                cursor.execute(
                    "UPDATE conversations SET unread_b = COALESCE(unread_b,0) + 1 WHERE id = ? AND LOWER(user_a_id) = ?",
                    (conv_id, sender_l),
                )
                cursor.execute(
                    "UPDATE conversations SET unread_a = COALESCE(unread_a,0) + 1 WHERE id = ? AND LOWER(user_b_id) = ?",
                    (conv_id, sender_l),
                )

    conn.commit()
    cursor.execute("SELECT * FROM messages WHERE id = ?", (msg_id,))
    row = cursor.fetchone()
    conn.close()

    message = map_message(row)
    sender_u = str(sender_id or '').strip()
    receiver_u = str(receiver_id or '').strip()
    if not receiver_u and user_a and user_b:
        receiver_u = user_b if sender_u == user_a else user_a

    if sender_u and receiver_u and receiver_u.lower() not in ('system', 'general', 'all'):
        await manager.send_to_pair(sender_u, receiver_u, "chat_message", message)
        if target_ride_id != channel_id:
            fallback_msg = dict(message)
            fallback_msg["rideId"] = target_ride_id
            await manager.send_to_pair(sender_u, receiver_u, "chat_message", fallback_msg)
    else:
        await manager.broadcast("chat_message", message)
        if target_ride_id != channel_id:
            fallback_msg = dict(message)
            fallback_msg["rideId"] = target_ride_id
            await manager.broadcast("chat_message", fallback_msg)
    return message

@app.get("/ride/api/messages")
@app.get("/api/messages")
def get_chat_messages_query(ride_id: Optional[str] = None):
    return _fetch_messages(ride_id)

@app.get("/ride/api/chat/{ride_id}/messages")
@app.get("/api/chat/{ride_id}/messages")
def get_chat_messages_path(ride_id: str):
    return _fetch_messages(ride_id)

@app.post("/ride/api/messages")
@app.post("/api/messages")
async def post_chat_messages_body(msg_data: Dict[str, Any]):
    target = msg_data.get("rideId") or "ride_general"
    return await _save_and_broadcast_message(target, msg_data)

@app.post("/ride/api/chat/{ride_id}/messages")
@app.post("/api/chat/{ride_id}/messages")
async def post_chat_messages_path(ride_id: str, msg_data: Dict[str, Any]):
    return await _save_and_broadcast_message(ride_id, msg_data)

@app.post("/ride/api/messages/mark-read")
@app.post("/api/messages/mark-read")
@app.post("/ride/api/chat/mark-read")
@app.post("/api/chat/mark-read")
async def mark_messages_read(payload: Dict[str, Any]):
    """Opened a thread → clear unread + mark peer messages read (WhatsApp-style)."""
    user_id = str(payload.get("userId") or "").strip().lower()
    conv_id = str(payload.get("conversationId") or payload.get("rideId") or "").strip()
    if not user_id or not conv_id:
        raise HTTPException(status_code=400, detail="userId and conversationId required")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM conversations WHERE id = ?", (conv_id,))
    conv = cursor.fetchone()
    if not conv and conv_id.startswith("peer_dm_"):
        # Try loose match
        cursor.execute(
            "SELECT * FROM conversations WHERE id = ? OR ride_id = ?",
            (conv_id, conv_id),
        )
        conv = cursor.fetchone()

    if conv:
        ua = str(conv["user_a_id"]).lower()
        ub = str(conv["user_b_id"]).lower()
        if user_id == ua or user_id in ua:
            cursor.execute("UPDATE conversations SET unread_a = 0 WHERE id = ?", (conv["id"],))
        elif user_id == ub or user_id in ub:
            cursor.execute("UPDATE conversations SET unread_b = 0 WHERE id = ?", (conv["id"],))
        else:
            cursor.execute(
                "UPDATE conversations SET unread_a = 0 WHERE id = ? AND LOWER(user_a_id) LIKE ?",
                (conv["id"], f"%{user_id}%"),
            )
            cursor.execute(
                "UPDATE conversations SET unread_b = 0 WHERE id = ? AND LOWER(user_b_id) LIKE ?",
                (conv["id"], f"%{user_id}%"),
            )

    # Mark messages addressed to this user as read
    cursor.execute(
        """
        UPDATE messages SET is_read = 1
        WHERE (ride_id = ? OR conversation_id = ?)
          AND LOWER(sender_id) != ?
          AND COALESCE(is_read, 0) = 0
        """,
        (conv_id, conv_id, user_id),
    )
    conn.commit()
    conn.close()

    event = {"conversationId": conv_id, "readerId": user_id}
    await manager.broadcast("messages_read", event)
    return {"status": "ok", **event}

@app.get("/ride/api/conversations")
@app.get("/api/conversations")
def get_user_conversations(user_id: Optional[str] = None):
    conn = get_db()
    cursor = conn.cursor()

    # Clean up any bad legacy rows with 'system', 'unknown', or 'drv'
    cursor.execute("DELETE FROM conversations WHERE user_a_id IN ('system', 'unknown', 'drv', 'driver') OR user_b_id IN ('system', 'unknown', 'drv', 'driver')")
    conn.commit()

    if not user_id:
        conn.close()
        return []

    uid_clean = user_id.strip()
    cursor.execute("SELECT * FROM users WHERE id = ? OR student_id = ? OR LOWER(email) = LOWER(?)", (uid_clean, uid_clean, uid_clean))
    u_row = cursor.fetchone()
    canonical_id = u_row["id"] if u_row else uid_clean
    my_student_id = u_row["student_id"] if u_row else uid_clean

    my_aliases = {canonical_id.lower(), uid_clean.lower()}
    if my_student_id: my_aliases.add(my_student_id.lower())

    cursor.execute("""
        SELECT c.*,
            CASE WHEN LOWER(c.user_a_id) IN (?, ?) THEN c.user_b_id ELSE c.user_a_id END as peer_id,
            CASE WHEN LOWER(c.user_a_id) IN (?, ?) THEN c.unread_a ELSE c.unread_b END as my_unread
        FROM conversations c
        WHERE LOWER(c.user_a_id) IN (?, ?) OR LOWER(c.user_b_id) IN (?, ?)
        ORDER BY c.last_message_at DESC
    """, (canonical_id.lower(), uid_clean.lower(), canonical_id.lower(), uid_clean.lower(),
          canonical_id.lower(), uid_clean.lower(), canonical_id.lower(), uid_clean.lower()))
    conv_rows = cursor.fetchall()

    peer_grouped: Dict[str, Dict[str, Any]] = {}

    for cr in conv_rows:
        peer_raw = cr["peer_id"]
        if not peer_raw or str(peer_raw).lower() in ("system", "unknown", "drv", "driver", canonical_id.lower(), uid_clean.lower()):
            continue

        # Resolve peer canonical user info
        cursor.execute("SELECT id, name, department, phone, is_biker, student_id, email FROM users WHERE id = ? OR student_id = ? OR LOWER(email) = LOWER(?)", (peer_raw, peer_raw, peer_raw))
        peer_u = cursor.fetchone()
        if not peer_u:
            norm_sid = peer_raw.replace("usr_", "").replace("_", "-")
            cursor.execute("SELECT id, name, department, phone, is_biker, student_id, email FROM users WHERE student_id = ? OR UPPER(REPLACE(student_id, '-', '')) = UPPER(REPLACE(?, '-', ''))", (norm_sid, norm_sid))
            peer_u = cursor.fetchone()

        peer_id = peer_u["id"] if peer_u else peer_raw
        peer_student_id = peer_u["student_id"] if peer_u else (peer_raw.replace("usr_", "").replace("_", "-") if peer_raw.startswith("usr_") else peer_raw)
        peer_email = peer_u["email"] if peer_u and "email" in peer_u.keys() else ""
        
        # Proper name resolution: avoid raw usr_ IDs
        peer_name = None
        if peer_u and peer_u["name"] and not peer_u["name"].startswith("usr_"):
            peer_name = peer_u["name"]
        if not peer_name:
            cursor.execute("SELECT sender_name FROM messages WHERE sender_id = ? AND sender_name NOT LIKE 'usr_%' AND sender_name != 'system' ORDER BY id DESC LIMIT 1", (peer_raw,))
            m_row = cursor.fetchone()
            if m_row and m_row["sender_name"]:
                peer_name = m_row["sender_name"]
            else:
                peer_name = f"Student {peer_student_id}" if peer_student_id != peer_raw else "DIU Student"

        peer_dept = peer_u["department"] if peer_u else "DIU Student"
        peer_phone = peer_u["phone"] if peer_u and peer_u["phone"] else ""
        peer_is_biker = bool(peer_u["is_biker"]) if peer_u else False

        peer_key = peer_id.lower().strip()
        if peer_key in my_aliases:
            continue

        # Look up ACTIVE trip/order between me and peer
        cursor.execute("""
            SELECT r.id as ride_id, r.status as ride_status, r.driver_id, r.origin_name, r.destination_name,
                   r.fare_per_seat, r.vehicle_model, b.id as booking_id, b.status as booking_status
            FROM rides r
            JOIN bookings b ON r.id = b.ride_id
            WHERE ((LOWER(r.driver_id) IN (?, ?) AND LOWER(b.passenger_id) IN (?, ?))
                OR (LOWER(r.driver_id) IN (?, ?) AND LOWER(b.passenger_id) IN (?, ?)))
              AND r.status NOT IN ('completed', 'cancelled')
              AND b.status NOT IN ('completed', 'cancelled', 'declined', 'rejected')
            ORDER BY b.requested_at DESC LIMIT 1
        """, (canonical_id.lower(), uid_clean.lower(), peer_id.lower(), peer_student_id.lower(),
              peer_id.lower(), peer_student_id.lower(), canonical_id.lower(), uid_clean.lower()))
        active_order = cursor.fetchone()

        if not active_order:
            cursor.execute("""
                SELECT pr.id as ride_id, pr.status as ride_status, pr.accepted_by_driver_id as driver_id,
                       pr.pickup as origin_name, pr.dropoff as destination_name, pr.proposed_fare as fare_per_seat,
                       'Motorbike' as vehicle_model, '' as booking_id, pr.status as booking_status
                FROM passenger_requests pr
                WHERE ((LOWER(pr.accepted_by_driver_id) IN (?, ?) AND LOWER(pr.passenger_id) IN (?, ?))
                    OR (LOWER(pr.accepted_by_driver_id) IN (?, ?) AND LOWER(pr.passenger_id) IN (?, ?)))
                  AND pr.status NOT IN ('completed', 'cancelled', 'declined')
                ORDER BY pr.created_at DESC LIMIT 1
            """, (canonical_id.lower(), uid_clean.lower(), peer_id.lower(), peer_student_id.lower(),
                  peer_id.lower(), peer_student_id.lower(), canonical_id.lower(), uid_clean.lower()))
            active_order = cursor.fetchone()

        has_active_trip = active_order is not None
        if has_active_trip:
            is_me_driver = str(active_order["driver_id"]).lower() in my_aliases
            peer_role = "Passenger" if is_me_driver else "Rider"
            origin = active_order["origin_name"] or ""
            destination = active_order["destination_name"] or ""
            vehicle_model = active_order["vehicle_model"] or "DIU Verified Bike"
            fare = float(active_order["fare_per_seat"] or 0.0)
            ride_status = active_order["booking_status"] or active_order["ride_status"]
            active_ride_id = active_order["ride_id"]
            context_type = "ride"
        else:
            peer_role = ""  # After trip end or default -> NO role badge!
            origin = ""
            destination = ""
            vehicle_model = "Campus Chat"
            fare = 0.0
            ride_status = "default"
            active_ride_id = ""
            context_type = "chat"

        # Canonical pair channel ID
        pair = sorted([canonical_id.lower(), peer_id.lower()])
        canonical_channel = f"peer_dm_{pair[0]}__{pair[1]}"

        db_session_state = cr["session_state"] if ("session_state" in cr.keys() and cr["session_state"]) else ("inProgress" if has_active_trip else "idle")
        db_chat_context = cr["chat_context"] if ("chat_context" in cr.keys() and cr["chat_context"]) else ("from_ride_post" if has_active_trip else "peer")
        db_source_post_id = cr["source_post_id"] if ("source_post_id" in cr.keys() and cr["source_post_id"]) else (active_order["ride_id"] if active_order else "")

        conv_item = {
            "id": canonical_channel,
            "rideId": canonical_channel,
            "peerId": peer_id,
            "peerName": peer_name,
            "peerRole": peer_role,
            "peerPhone": peer_phone,
            "peerDept": peer_dept,
            "peerStudentId": peer_student_id,
            "peerEmail": peer_email,
            "peerIsBiker": peer_is_biker,
            "contextType": context_type,
            "chatContext": db_chat_context,
            "sourcePostId": db_source_post_id,
            "sessionState": db_session_state,
            "hasActiveTrip": has_active_trip or (db_session_state in ("inProgress", "awaitingEnd", "bothConfirmed")),
            "route": f"{origin} ➔ {destination}" if origin else (f"{cr['origin']} ➔ {cr['destination']}" if ("origin" in cr.keys() and cr["origin"]) else ""),
            "origin": origin or (cr["origin"] if "origin" in cr.keys() and cr["origin"] else ""),
            "destination": destination or (cr["destination"] if "destination" in cr.keys() and cr["destination"] else ""),
            "vehicleModel": vehicle_model or (cr["vehicle_model"] if "vehicle_model" in cr.keys() and cr["vehicle_model"] else "Campus Ride"),
            "fare": fare or (float(cr["fare"] or 0.0) if "fare" in cr.keys() else 0.0),
            "status": db_session_state if db_session_state != "idle" else ride_status,
            "bookingId": active_order["booking_id"] if active_order else "",
            "lastMessage": cr["last_message"] or "Tap to open conversation",
            "lastTimestamp": cr["last_message_at"] or cr["created_at"],
            "lastSenderName": cr["last_sender_id"] or "",
            "unreadCount": int(cr["my_unread"] or 0),
        }

        if peer_key not in peer_grouped or (conv_item["lastTimestamp"] > peer_grouped[peer_key]["lastTimestamp"]):
            peer_grouped[peer_key] = conv_item

    # If no conversations in stable table, check messages for any historical peer chats
    if not peer_grouped:
        cursor.execute("""
            SELECT DISTINCT
                CASE WHEN LOWER(sender_id) IN (?, ?) THEN receiver_id ELSE sender_id END as peer_id,
                MAX(timestamp) as last_ts
            FROM messages
            WHERE (LOWER(sender_id) IN (?, ?) OR LOWER(receiver_id) IN (?, ?))
              AND sender_id NOT IN ('system', 'unknown', 'drv', 'driver')
              AND receiver_id NOT IN ('system', 'unknown', 'drv', 'driver', '')
              AND receiver_id IS NOT NULL
            GROUP BY peer_id
            ORDER BY last_ts DESC
        """, (canonical_id.lower(), uid_clean.lower(), canonical_id.lower(), uid_clean.lower(), canonical_id.lower(), uid_clean.lower()))
        legacy_peers = cursor.fetchall()
        for lp in legacy_peers:
            p_id = lp["peer_id"]
            if not p_id or p_id.lower() in my_aliases: continue
            cursor.execute("SELECT id, name, department, phone, is_biker FROM users WHERE id = ? OR student_id = ? OR LOWER(email) = LOWER(?)", (p_id, p_id, p_id))
            pu = cursor.fetchone()
            p_name = pu["name"] if pu else p_id
            pair = sorted([canonical_id.lower(), p_id.lower()])
            c_chan = f"peer_dm_{pair[0]}__{pair[1]}"
            cursor.execute("SELECT text, timestamp, sender_name FROM messages WHERE ride_id = ? OR ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) ORDER BY timestamp DESC LIMIT 1", (c_chan, canonical_id, p_id, p_id, canonical_id))
            last_m = cursor.fetchone()
            peer_grouped[p_id.lower()] = {
                "id": c_chan, "rideId": c_chan, "peerId": p_id, "peerName": p_name,
                "peerRole": "", "peerPhone": pu["phone"] if pu else "", "peerDept": pu["department"] if pu else "DIU Student",
                "peerIsBiker": bool(pu["is_biker"]) if pu else False, "contextType": "chat", "hasActiveTrip": False,
                "route": "", "origin": "", "destination": "", "vehicleModel": "Campus Chat", "fare": 0.0, "status": "default",
                "bookingId": "", "lastMessage": last_m["text"] if last_m else "Tap to open conversation",
                "lastTimestamp": last_m["timestamp"] if last_m else lp["last_ts"],
                "lastSenderName": last_m["sender_name"] if last_m else "", "unreadCount": 0
            }

    conn.close()
    return sorted(peer_grouped.values(), key=lambda c: c.get("lastTimestamp", ""), reverse=True)

@app.post("/ride/api/conversations/initiate")
@app.post("/api/conversations/initiate")
async def initiate_conversation(body: Dict[str, Any]):
    import hashlib
    user_a = str(body.get("userId", "")).strip()
    user_b = str(body.get("peerId", "")).strip()
    ride_id = body.get("rideId")
    context_type = body.get("contextType", "ride")  # 'ride' | 'bike' | 'friend'

    if not user_a or not user_b:
        raise HTTPException(status_code=400, detail="userId and peerId are required")

    conv_id = hashlib.sha256("_".join(sorted([user_a, user_b])).encode()).hexdigest()[:24]
    now = get_current_bd_time().isoformat()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        INSERT OR IGNORE INTO conversations
        (id, user_a_id, user_b_id, ride_id, context_type, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (conv_id, user_a, user_b, ride_id, context_type, now))
    if ride_id:
        cursor.execute("UPDATE conversations SET ride_id=COALESCE(?,ride_id), context_type=? WHERE id=?",
                       (ride_id, context_type, conv_id))
    conn.commit()
    cursor.execute("SELECT * FROM conversations WHERE id = ?", (conv_id,))
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else {"id": conv_id, "userId": user_a, "peerId": user_b, "contextType": context_type}


@app.get("/ride/api/users/search")
@app.get("/api/users/search")
def search_users(q: str = Query("", min_length=0), exclude_id: Optional[str] = None):
    conn = get_db()
    cursor = conn.cursor()
    q_clean = q.strip()
    if q_clean:
        q_val = f"%{q_clean}%"
        cursor.execute("""
            SELECT id, name, department, student_id, phone, is_biker, rating
            FROM users
            WHERE (name LIKE ? OR student_id LIKE ? OR department LIKE ?) AND id != ?
            ORDER BY name ASC LIMIT 30
        """, (q_val, q_val, q_val, exclude_id or ""))
    else:
        cursor.execute("""
            SELECT id, name, department, student_id, phone, is_biker, rating
            FROM users
            WHERE id != ?
            ORDER BY name ASC LIMIT 30
        """, (exclude_id or "",))
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "name": r["name"],
        "department": r["department"],
        "studentId": r["student_id"],
        "phone": r["phone"] or "",
        "isBiker": bool(r["is_biker"]),
        "rating": float(r["rating"] or 4.9),
    } for r in rows]


@app.get("/ride/api/nearby-riders")
@app.get("/api/nearby-riders")
def get_nearby_riders(
    lat: float = Query(...),
    lng: float = Query(...),
    radius_km: float = Query(10.0),
    role: str = Query("passenger"),  # 'passenger' or 'rider'
):
    """
    Returns nearest available rides (role=passenger) or open passenger requests (role=rider).
    Uses Haversine formula via SQLite math functions.
    """
    conn = get_db()
    cursor = conn.cursor()

    if role == "passenger":
        # Passenger wants nearest available biker/rider rides
        cursor.execute("""
            SELECT *,
                (6371 * (
                    (origin_lat - ?) * (origin_lat - ?) * 0.0001 +
                    (origin_lng - ?) * (origin_lng - ?) * 0.0001
                )) AS approx_dist
            FROM rides
            WHERE status = 'published' AND available_seats > 0
            ORDER BY approx_dist ASC
            LIMIT 20
        """, (lat, lat, lng, lng))
        rows = cursor.fetchall()
        conn.close()
        result = []
        for r in rows:
            # Precise haversine filter
            import math
            dlat = math.radians(float(r["origin_lat"]) - lat)
            dlng = math.radians(float(r["origin_lng"]) - lng)
            a = math.sin(dlat/2)**2 + math.cos(math.radians(lat)) * math.cos(math.radians(float(r["origin_lat"]))) * math.sin(dlng/2)**2
            dist = 6371 * 2 * math.asin(math.sqrt(a))
            if dist <= radius_km:
                mapped = map_ride(r)
                mapped["distanceFromYouKm"] = round(dist, 2)
                result.append(mapped)
        return result
    else:
        # Rider wants nearest open passenger requests
        cursor.execute("""
            SELECT *,
                (6371 * (
                    (COALESCE(pickup_lat, 23.8765) - ?) * (COALESCE(pickup_lat, 23.8765) - ?) * 0.0001 +
                    (COALESCE(pickup_lng, 90.3204) - ?) * (COALESCE(pickup_lng, 90.3204) - ?) * 0.0001
                )) AS approx_dist
            FROM passenger_requests
            WHERE status = 'open'
            ORDER BY approx_dist ASC
            LIMIT 20
        """, (lat, lat, lng, lng))
        rows = cursor.fetchall()
        conn.close()
        result = []
        import math
        for r in rows:
            p_lat = float(r["pickup_lat"]) if r["pickup_lat"] else lat
            p_lng = float(r["pickup_lng"]) if r["pickup_lng"] else lng
            dlat = math.radians(p_lat - lat)
            dlng = math.radians(p_lng - lng)
            a = math.sin(dlat/2)**2 + math.cos(math.radians(lat)) * math.cos(math.radians(p_lat)) * math.sin(dlng/2)**2
            dist = 6371 * 2 * math.asin(math.sqrt(a))
            if dist <= radius_km:
                mapped = map_passenger_request(r)
                mapped["distanceFromYouKm"] = round(dist, 2)
                result.append(mapped)
        return result

# =====================================================================
# REST Endpoints: Live Location Sharing (Driver & Passenger GPS + Google Maps)
# =====================================================================

@app.post("/ride/api/location/share")
@app.post("/api/location/share")
async def share_user_location(payload: Dict[str, Any]):
    ride_id = payload.get("rideId", "ride_default")
    user_id = payload.get("userId", "usr_peer")
    user_name = payload.get("userName", "DIU Commuter")
    role = payload.get("role", "passenger") # passenger or driver
    lat = float(payload.get("latitude", 23.8765))
    lng = float(payload.get("longitude", 90.3204))
    now = datetime.utcnow().isoformat()
    loc_id = f"loc_{ride_id}_{user_id}"
    maps_link = f"https://www.google.com/maps/search/?api=1&query={lat},{lng}"

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT OR REPLACE INTO shared_locations (
        id, ride_id, user_id, user_name, role, latitude, longitude, maps_link, updated_at
    ) VALUES (?,?,?,?,?,?,?,?,?)
    """, (loc_id, ride_id, user_id, user_name, role, lat, lng, maps_link, now))
    conn.commit()
    conn.close()

    event_data = {
        "id": loc_id,
        "rideId": ride_id,
        "userId": user_id,
        "userName": user_name,
        "role": role,
        "latitude": lat,
        "longitude": lng,
        "mapsLink": maps_link,
        "updatedAt": now,
    }
    # Broadcast to all connected clients over WebSocket
    await manager.broadcast("location_shared", event_data)

    # ALSO record as a chat message so it immediately appears in the chatbox!
    loc_msg = {
        "id": f"msg_loc_{int(datetime.utcnow().timestamp()*1000)}",
        "rideId": ride_id,
        "senderId": user_id,
        "senderName": user_name,
        "text": f"📍 Shared Live GPS ({role.title()}): {maps_link}",
        "timestamp": now,
        "isLocationShare": True,
        "sharedLat": lat,
        "sharedLng": lng,
    }
    await _save_and_broadcast_message(ride_id, loc_msg)

    return {"status": "ok", "data": event_data}

@app.get("/ride/api/rides/{ride_id}/shared-locations")
@app.get("/api/rides/{ride_id}/shared-locations")
def get_shared_locations(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM shared_locations WHERE ride_id = ? ORDER BY updated_at DESC", (ride_id,))
    rows = cursor.fetchall()
    conn.close()
    return [
        {
            "id": r["id"],
            "rideId": r["ride_id"],
            "userId": r["user_id"],
            "userName": r["user_name"],
            "role": r["role"],
            "latitude": float(r["latitude"]),
            "longitude": float(r["longitude"]),
            "mapsLink": r["maps_link"],
            "updatedAt": r["updated_at"],
        }
        for r in rows
    ]

# =====================================================================
# REST Endpoints: Live Driver Location
# =====================================================================

@app.post("/ride/api/location/driver")
@app.post("/api/location/driver")
async def update_driver_location(payload: Dict[str, Any]):
    driver_id = payload.get("driverId", "drv_default")
    ride_id = payload.get("rideId", "ride_default")
    lat = float(payload.get("latitude", 23.8765))
    lng = float(payload.get("longitude", 90.3204))
    heading = float(payload.get("heading", 0.0))
    speed = float(payload.get("speed", 0.0))
    eta = int(payload.get("etaMinutes", 5))
    dist = float(payload.get("distanceRemainingKm", 1.0))
    now = datetime.utcnow().isoformat()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT OR REPLACE INTO driver_locations (
        driver_id, ride_id, latitude, longitude, heading, speed, eta_minutes, distance_remaining_km, updated_at
    ) VALUES (?,?,?,?,?,?,?,?,?)
    """, (driver_id, ride_id, lat, lng, heading, speed, eta, dist, now))
    conn.commit()
    conn.close()

    event_data = {
        "driverId": driver_id,
        "rideId": ride_id,
        "latitude": lat,
        "longitude": lng,
        "heading": heading,
        "speed": speed,
        "etaMinutes": eta,
        "distanceRemainingKm": dist,
        "timestamp": now,
    }
    await manager.broadcast("driver_location_update", event_data)
    return {"status": "ok", "data": event_data}

# =====================================================================
# REST Endpoints: Safety & SOS
# =====================================================================

@app.post("/ride/api/safety/sos")
@app.post("/api/safety/sos")
async def trigger_sos(payload: Dict[str, Any]):
    sos_id = f"sos_{int(datetime.utcnow().timestamp()*1000)}"
    now = datetime.utcnow().isoformat()
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO sos_alerts (
        id, student_id, student_name, student_phone, location_name, latitude, longitude, created_at
    ) VALUES (?,?,?,?,?,?,?,?)
    """, (
        sos_id,
        payload.get("studentId", "Unknown"),
        payload.get("studentName", "DIU Student"),
        payload.get("studentPhone", "01712345678"),
        payload.get("locationName", "Ashulia Highway"),
        payload.get("latitude", 23.8765),
        payload.get("longitude", 90.3204),
        now,
    ))
    conn.commit()
    conn.close()

    sos_data = {
        "sosId": sos_id,
        "studentId": payload.get("studentId"),
        "studentName": payload.get("studentName"),
        "timestamp": now,
        "location": payload.get("locationName"),
    }
    await manager.broadcast("sos_alert", sos_data)
    return {"status": "dispatched", "sos": sos_data}

@app.get("/ride/api/safety/emergency-contacts")
@app.get("/api/safety/emergency-contacts")
def emergency_contacts():
    return [
        {"name": "DIU Campus Security (Main Gate)", "phone": "+8801713493011", "dept": "Security"},
        {"name": "DIU Medical Center (Emergency)", "phone": "+8801713493022", "dept": "Healthcare"},
        {"name": "DIU Proctor Office", "phone": "+8801713493033", "dept": "Administration"},
        {"name": "DIU Transport Department", "phone": "+8801713493044", "dept": "Transport"},
        {"name": "National Emergency Service", "phone": "999", "dept": "Bangladesh Police / Ambulance"},
    ]

# =====================================================================
# WebSocket Endpoints
# =====================================================================

@app.websocket("/ride/ws")
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket, user_id: Optional[str] = Query(None)):
    await manager.connect(websocket, user_id=user_id)
    try:
        while True:
            raw_text = await websocket.receive_text()
            try:
                msg = json.loads(raw_text)
                event = msg.get("event")
                data = msg.get("data", {})

                if event == "ping":
                    await websocket.send_text(json.dumps({"event": "pong", "time": datetime.utcnow().isoformat()}))
                elif event == "identify":
                    uid = data.get("userId") or data.get("user_id")
                    if uid:
                        manager.register_user(websocket, uid)
                elif event == "driver_location_update":
                    await manager.broadcast("driver_location_update", data)
                elif event == "chat_message":
                    # Persist-then-broadcast only (WhatsApp-style). Do not relay
                    # unpersisted client payloads — REST /messages owns the write.
                    try:
                        await _save_and_broadcast_message(
                            str(data.get("rideId") or data.get("ride_id") or "general"),
                            data if isinstance(data, dict) else {},
                        )
                    except Exception as e:
                        print(f"[WS chat_message persist error] {e}")
                elif event == "messages_read":
                    # Client ack that a thread was opened; broadcast to peer for read receipts
                    await manager.broadcast("messages_read", data)
                elif event:
                    await manager.broadcast(event, data)
            except Exception as e:
                print(f"[WS Error] Parsing: {e}")
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        print(f"[WS Loop Error]: {e}")
        manager.disconnect(websocket)

# =====================================================================

# =====================================================================
# Realtime Messaging & Trip State Machine (DIU Ride Lifecycle)
# =====================================================================

def haversine_distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2.0)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2.0)**2
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return R * c

@app.post("/ride/api/chat/session/get-or-create")
@app.post("/api/chat/session/get-or-create")
async def get_or_create_chat_session(payload: Dict[str, Any]):
    user_a = str(payload.get("userId") or "").strip()
    user_b = str(payload.get("peerId") or "").strip()
    chat_context = str(payload.get("chatContext") or "peer").strip() # 'peer' | 'from_ride_post' | 'from_passenger_request'
    source_post_id = str(payload.get("sourcePostId") or payload.get("rideId") or "").strip()

    if not user_a or not user_b:
        raise HTTPException(status_code=400, detail="userId and peerId are required.")

    # Canonical unique pair ID
    pair = sorted([user_a.lower(), user_b.lower()])
    conv_id = f"peer_dm_{pair[0]}__{pair[1]}"
    now = get_current_bd_time().isoformat()

    conn = get_db()
    cursor = conn.cursor()

    # Look up existing conversation
    cursor.execute("SELECT * FROM conversations WHERE id = ?", (conv_id,))
    conv_row = cursor.fetchone()

    # Look up route and post info if source_post_id is provided
    origin = ""
    destination = ""
    fare = 0.0
    vehicle_model = "Campus Ride"
    if source_post_id:
        cursor.execute("SELECT * FROM rides WHERE id = ?", (source_post_id,))
        r_info = cursor.fetchone()
        if r_info:
            origin = r_info["origin_name"] or ""
            destination = r_info["destination_name"] or ""
            fare = float(r_info["fare_per_seat"] or 0.0)
            vehicle_model = r_info["vehicle_model"] or "Motorbike"
        else:
            cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (source_post_id,))
            req_info = cursor.fetchone()
            if req_info:
                origin = req_info["pickup"] or ""
                destination = req_info["dropoff"] or ""
                fare = float(req_info["proposed_fare"] or 50.0)
                vehicle_model = "Requested Bike"

    if not conv_row:
        initial_state = "awaitingConfirm" if source_post_id else "idle"
        cursor.execute("""
            INSERT INTO conversations (
                id, user_a_id, user_b_id, ride_id, context_type, created_at,
                chat_context, source_post_id, session_state, origin, destination, fare, vehicle_model
            ) VALUES (?, ?, ?, ?, 'ride', ?, ?, ?, ?, ?, ?, ?, ?)
        """, (conv_id, pair[0], pair[1], source_post_id or conv_id, now,
              chat_context, source_post_id, initial_state, origin, destination, fare, vehicle_model))
        conn.commit()
    else:
        # Existing conversation: if it came from a new post and previous session was closed/idle, update
        current_state = conv_row["session_state"] or "idle"
        if source_post_id and current_state in ("idle", "completed", "cancelled"):
            cursor.execute("""
                UPDATE conversations SET
                    chat_context = ?,
                    source_post_id = ?,
                    session_state = 'awaitingConfirm',
                    rider_confirmed = 0,
                    passenger_confirmed = 0,
                    trip_starter_a = 0,
                    trip_starter_b = 0,
                    trip_ender_a = 0,
                    trip_ender_b = 0,
                    trip_started_at = NULL,
                    trip_ended_at = NULL,
                    canceller_id = NULL,
                    cancel_reason = NULL,
                    diverge_started_at = NULL,
                    diverge_alerted = 0,
                    origin = COALESCE(NULLIF(?, ''), origin),
                    destination = COALESCE(NULLIF(?, ''), destination),
                    fare = CASE WHEN ? > 0 THEN ? ELSE fare END,
                    vehicle_model = COALESCE(NULLIF(?, ''), vehicle_model)
                WHERE id = ?
            """, (chat_context, source_post_id, origin, destination, fare, fare, vehicle_model, conv_id))
            conn.commit()

    cursor.execute("SELECT * FROM conversations WHERE id = ?", (conv_id,))
    res_row = cursor.fetchone()
    conn.close()

    return dict(res_row) if res_row else {"id": conv_id, "sessionState": "idle"}

@app.get("/ride/api/chat/session/active-user-trip")
@app.get("/api/chat/session/active-user-trip")
def get_active_user_trip(user_id: str = Query(...)):
    uid = user_id.strip().lower()
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM conversations
        WHERE (LOWER(user_a_id) = ? OR LOWER(user_b_id) = ?)
          AND session_state IN ('inProgress', 'awaitingEnd')
        ORDER BY last_message_at DESC LIMIT 1
    """, (uid, uid))
    row = cursor.fetchone()
    if not row:
        conn.close()
        return {"hasActiveTrip": False}

    d = dict(row)
    peer_id = d["user_b_id"] if uid == d["user_a_id"].lower() else d["user_a_id"]
    cursor.execute("SELECT name, phone, student_id FROM users WHERE LOWER(id)=? OR LOWER(student_id)=?", (peer_id.lower(), peer_id.lower()))
    p_user = cursor.fetchone()
    conn.close()

    peer_name = p_user["name"] if p_user and p_user["name"] else "Companion"
    return {
        "hasActiveTrip": True,
        "conversationId": d["id"],
        "sessionState": d["session_state"],
        "peerId": peer_id,
        "peerName": peer_name,
        "origin": d["origin"] or "DIU Campus",
        "destination": d["destination"] or "Destination Spot",
        "fare": float(d["fare"] or 0.0),
        "vehicleModel": d["vehicle_model"] or "Motorbike",
        "tripStartedAt": d["trip_started_at"],
    }

@app.get("/ride/api/chat/session/{conversation_id}")
@app.get("/api/chat/session/{conversation_id}")
def get_chat_session(conversation_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM conversations WHERE id = ?", (conversation_id,))
    row = cursor.fetchone()
    conn.close()
    if not row:
        return {"conversationId": conversation_id, "sessionState": "idle"}
    return dict(row)

@app.post("/ride/api/chat/session/confirm")
@app.post("/api/chat/session/confirm")
async def confirm_chat_session(payload: Dict[str, Any]):
    conv_id = str(payload.get("conversationId") or "").strip()
    user_id = str(payload.get("userId") or "").strip().lower()
    user_name = str(payload.get("userName") or "Companion").strip()
    role = str(payload.get("role") or "").lower() # 'rider' | 'passenger'

    if not conv_id or not user_id:
        raise HTTPException(status_code=400, detail="conversationId and userId are required.")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM conversations WHERE id = ?", (conv_id,))
    conv = cursor.fetchone()
    if not conv:
        conn.close()
        raise HTTPException(status_code=404, detail="Conversation not found.")

    r_conf = int(conv["rider_confirmed"] or 0)
    p_conf = int(conv["passenger_confirmed"] or 0)

    # Determine if user is rider or passenger
    if role in ("rider", "driver", "biker"):
        r_conf = 1
    elif role in ("passenger",):
        p_conf = 1
    else:
        # Default based on pair position or is_biker
        if user_id == conv["user_a_id"].lower():
            r_conf = 1
        else:
            p_conf = 1

    both_conf = (r_conf == 1 and p_conf == 1)
    new_state = "bothConfirmed" if both_conf else "awaitingConfirm"
    now = get_current_bd_time().isoformat()
    post_id = conv["source_post_id"] if "source_post_id" in conv.keys() else None

    cursor.execute("""
        UPDATE conversations SET
            rider_confirmed = ?,
            passenger_confirmed = ?,
            session_state = ?
        WHERE id = ?
    """, (r_conf, p_conf, new_state, conv_id))

    if both_conf:
        clear_confirm_wait(cursor, conv_id)
        # Soft-lock seats on mutual confirm
        if post_id:
            cursor.execute(
                "UPDATE rides SET status = 'occupied', available_seats = 0 WHERE id = ?",
                (post_id,),
            )
            cursor.execute(
                "UPDATE passenger_requests SET status = 'accepted' WHERE id = ?",
                (post_id,),
            )
    else:
        # Student confirmed, waiting for biker (or reverse) → start 2-min x3 reminder clock
        waiting_for = "rider" if p_conf == 1 and r_conf == 0 else "passenger"
        mark_one_sided_confirm_wait(cursor, conv_id, waiting_for)

    conn.commit()
    user_a = conv["user_a_id"]
    user_b = conv["user_b_id"]
    conn.close()

    # System message in chat
    if both_conf:
        sys_txt = "✅ Both Rider and Passenger confirmed the ride! When you meet to go, both tap 'Start Trip'."
    else:
        waiting = "biker" if (p_conf == 1 and r_conf == 0) else "student"
        sys_txt = (
            f"⏳ {user_name} confirmed the ride. Waiting for {waiting} confirmation. "
            f"Reminders every 2 minutes (max 3). If not confirmed, the post will be suspended."
        )

    await _save_and_broadcast_message(conv_id, {
        "rideId": conv_id,
        "senderId": "system",
        "senderName": "DIU Ride System",
        "text": sys_txt,
        "isLocationShare": False,
        "timestamp": now,
    })

    # Mutual confirm → notify other chatting students/bikers + hide post
    if both_conf and post_id:
        try:
            await notify_other_parties_after_mutual_confirm(
                winning_conv_id=conv_id,
                source_post_id=post_id,
                winner_a=user_a,
                winner_b=user_b,
                winner_name=user_name,
            )
        except Exception as e:
            print(f"[MUTUAL CONFIRM NOTIFY ERROR] {e}")

    event_data = {
        "conversationId": conv_id,
        "sessionState": new_state,
        "riderConfirmed": bool(r_conf),
        "passengerConfirmed": bool(p_conf),
        "bothConfirmed": both_conf,
        "sourcePostId": post_id,
    }
    await manager.send_to_pair(user_a, user_b, "chat_session_state_changed", event_data)
    if not both_conf:
        await manager.broadcast("ride_acceptance_prompt", {
            "conversationId": conv_id,
            "sourcePostId": post_id,
            "senderId": user_id,
            "senderName": user_name,
            "role": role,
            "pendingRole": "rider" if p_conf == 1 and r_conf == 0 else "passenger",
            "message": sys_txt,
            "title": "Confirm ride reminder",
        })
    return event_data

@app.post("/ride/api/chat/session/start")
@app.post("/api/chat/session/start")
async def start_chat_session(payload: Dict[str, Any]):
    conv_id = str(payload.get("conversationId") or "").strip()
    user_id = str(payload.get("userId") or "").strip().lower()
    user_name = str(payload.get("userName") or "Companion").strip()

    if not conv_id or not user_id:
        raise HTTPException(status_code=400, detail="conversationId and userId are required.")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM conversations WHERE id = ?", (conv_id,))
    conv = cursor.fetchone()
    if not conv:
        conn.close()
        raise HTTPException(status_code=404, detail="Conversation not found.")

    starter_a = int(conv["trip_starter_a"] or 0)
    starter_b = int(conv["trip_starter_b"] or 0)

    if user_id == conv["user_a_id"].lower():
        starter_a = 1
    else:
        starter_b = 1

    both_started = (starter_a == 1 and starter_b == 1)
    new_state = "inProgress" if both_started else "awaitingStart"
    now = get_current_bd_time().isoformat()

    cursor.execute("""
        UPDATE conversations SET
            trip_starter_a = ?,
            trip_starter_b = ?,
            session_state = ?,
            trip_started_at = CASE WHEN ? THEN COALESCE(trip_started_at, ?) ELSE trip_started_at END
        WHERE id = ?
    """, (starter_a, starter_b, new_state, both_started, now, conv_id))

    post_id = conv["source_post_id"]
    if both_started and post_id:
        cursor.execute("UPDATE rides SET status = 'in_progress', start_time = COALESCE(start_time, ?) WHERE id = ?", (now, post_id))

    conn.commit()
    conn.close()

    if both_started:
        sys_txt = "🚀 Both tapped 'Start Trip'! Trip is now active and in progress. Live ride banner is running."
    else:
        sys_txt = f"⏳ {user_name} tapped 'Start Trip'. Waiting for companion to tap 'Start Trip'."

    await _save_and_broadcast_message(conv_id, {
        "rideId": conv_id,
        "senderId": "system",
        "senderName": "DIU Ride System",
        "text": sys_txt,
        "isLocationShare": False,
        "timestamp": now,
    })

    event_data = {
        "conversationId": conv_id,
        "sessionState": new_state,
        "tripStarterA": bool(starter_a),
        "tripStarterB": bool(starter_b),
        "bothStarted": both_started,
        "tripStartedAt": now if both_started else conv["trip_started_at"],
        "sourcePostId": post_id,
    }
    await manager.send_to_pair(conv["user_a_id"], conv["user_b_id"], "chat_session_state_changed", event_data)
    return event_data

@app.post("/ride/api/chat/session/end")
@app.post("/api/chat/session/end")
async def end_chat_session(payload: Dict[str, Any]):
    conv_id = str(payload.get("conversationId") or "").strip()
    user_id = str(payload.get("userId") or "").strip().lower()
    user_name = str(payload.get("userName") or "Companion").strip()

    if not conv_id or not user_id:
        raise HTTPException(status_code=400, detail="conversationId and userId are required.")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM conversations WHERE id = ?", (conv_id,))
    conv = cursor.fetchone()
    if not conv:
        conn.close()
        raise HTTPException(status_code=404, detail="Conversation not found.")

    ender_a = int(conv["trip_ender_a"] or 0)
    ender_b = int(conv["trip_ender_b"] or 0)

    if user_id == conv["user_a_id"].lower():
        ender_a = 1
    else:
        ender_b = 1

    both_ended = (ender_a == 1 and ender_b == 1)
    new_state = "completed" if both_ended else "awaitingEnd"
    now = get_current_bd_time().isoformat()

    cursor.execute("""
        UPDATE conversations SET
            trip_ender_a = ?,
            trip_ender_b = ?,
            session_state = ?,
            trip_ended_at = CASE WHEN ? THEN ? ELSE trip_ended_at END
        WHERE id = ?
    """, (ender_a, ender_b, new_state, both_ended, now, conv_id))

    post_id = conv["source_post_id"]
    if both_ended and post_id:
        cursor.execute("UPDATE rides SET status = 'completed', end_time = ? WHERE id = ?", (now, post_id))
        cursor.execute("UPDATE bookings SET status = 'completed' WHERE ride_id = ?", (post_id,))
        cursor.execute("UPDATE passenger_requests SET status = 'completed' WHERE id = ?", (post_id,))

        # Record to completed CSV
        append_completed_trip_csv({
            "trip_id": f"comp_{conv_id}_{int(datetime.utcnow().timestamp())}",
            "rider_id": conv["user_a_id"],
            "rider_name": "DIU Biker",
            "rider_phone": "",
            "passenger_id": conv["user_b_id"],
            "passenger_name": "DIU Passenger",
            "passenger_phone": "",
            "origin": conv["origin"] or "DIU Campus",
            "destination": conv["destination"] or "Destination Spot",
            "fare": float(conv["fare"] or 0.0),
            "start_time": conv["trip_started_at"] or now,
            "end_time": now,
            "status": "completed",
            "cancel_reason": "",
            "total_duration_minutes": 15.0,
            "completed_time": now,
        })

    conn.commit()
    conn.close()

    if both_ended:
        sys_txt = "🎉 Both confirmed End Trip! Ride completed successfully. Thank you for riding with DIU Ride."
    else:
        sys_txt = f"🏁 {user_name} tapped 'End Trip'. Waiting for companion to confirm End Trip."

    await _save_and_broadcast_message(conv_id, {
        "rideId": conv_id,
        "senderId": "system",
        "senderName": "DIU Ride System",
        "text": sys_txt,
        "isLocationShare": False,
        "timestamp": now,
    })

    event_data = {
        "conversationId": conv_id,
        "sessionState": new_state,
        "tripEnderA": bool(ender_a),
        "tripEnderB": bool(ender_b),
        "bothEnded": both_ended,
        "tripEndedAt": now if both_ended else conv["trip_ended_at"],
        "sourcePostId": post_id,
    }
    await manager.send_to_pair(conv["user_a_id"], conv["user_b_id"], "chat_session_state_changed", event_data)
    return event_data

@app.post("/ride/api/chat/session/cancel")
@app.post("/api/chat/session/cancel")
async def cancel_chat_session(payload: Dict[str, Any]):
    conv_id = str(payload.get("conversationId") or "").strip()
    user_id = str(payload.get("userId") or "").strip().lower()
    user_name = str(payload.get("userName") or "Companion").strip()
    reason = str(payload.get("reason") or "Cancelled by user").strip()

    if not conv_id or not user_id:
        raise HTTPException(status_code=400, detail="conversationId and userId are required.")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM conversations WHERE id = ?", (conv_id,))
    conv = cursor.fetchone()
    if not conv:
        conn.close()
        raise HTTPException(status_code=404, detail="Conversation not found.")

    # Any 1 user cancelling resets the session
    now = get_current_bd_time().isoformat()
    cursor.execute("""
        UPDATE conversations SET
            session_state = 'cancelled',
            rider_confirmed = 0,
            passenger_confirmed = 0,
            trip_starter_a = 0,
            trip_starter_b = 0,
            trip_ender_a = 0,
            trip_ender_b = 0,
            canceller_id = ?,
            cancel_reason = ?,
            diverge_started_at = NULL,
            diverge_alerted = 0
        WHERE id = ?
    """, (user_id, reason, conv_id))

    # Re-open original post so others can view it
    post_id = conv["source_post_id"]
    if post_id:
        if not str(post_id).startswith('preq_'):
            cursor.execute("UPDATE rides SET status = 'published', available_seats = total_seats WHERE id = ?", (post_id,))
        cursor.execute("UPDATE passenger_requests SET status = 'open' WHERE id = ?", (post_id,))

    conn.commit()
    conn.close()

    sys_txt = f"❌ Trip cancelled by {user_name}. Reason: {reason}. The chat is now in standard messaging mode."
    await _save_and_broadcast_message(conv_id, {
        "rideId": conv_id,
        "senderId": "system",
        "senderName": "DIU Ride System",
        "text": sys_txt,
        "isLocationShare": False,
        "timestamp": now,
    })

    event_data = {
        "conversationId": conv_id,
        "sessionState": "cancelled",
        "cancelledBy": user_name,
        "cancellerId": user_id,
        "cancelReason": reason,
        "sourcePostId": post_id,
    }
    await manager.send_to_pair(conv["user_a_id"], conv["user_b_id"], "chat_session_state_changed", event_data)
    return event_data

@app.post("/ride/api/chat/session/proximity-ping")
@app.post("/api/chat/session/proximity-ping")
async def proximity_ping_chat_session(payload: Dict[str, Any]):
    conv_id = str(payload.get("conversationId") or "").strip()
    user_id = str(payload.get("userId") or "").strip().lower()
    user_name = str(payload.get("userName") or "Companion").strip()
    lat = float(payload.get("latitude") or 0.0)
    lng = float(payload.get("longitude") or 0.0)

    if not conv_id or not user_id or lat == 0.0 or lng == 0.0:
        return {"status": "skipped"}

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM conversations WHERE id = ?", (conv_id,))
    conv = cursor.fetchone()
    if not conv:
        conn.close()
        return {"status": "conversation_not_found"}

    now = get_current_bd_time().isoformat()
    # Update shared_locations for user
    loc_id = f"loc_{user_id}_{conv_id}"
    maps_link = f"https://www.google.com/maps/search/?api=1&query={lat},{lng}"
    cursor.execute("""
        INSERT OR REPLACE INTO shared_locations (id, ride_id, user_id, user_name, role, latitude, longitude, maps_link, updated_at)
        VALUES (?, ?, ?, ?, 'commuter', ?, ?, ?, ?)
    """, (loc_id, conv_id, user_id, user_name, lat, lng, maps_link, now))
    conn.commit()

    # Check proximity only if inProgress
    if conv["session_state"] == "inProgress":
        peer_id = conv["user_b_id"] if user_id == conv["user_a_id"].lower() else conv["user_a_id"]
        cursor.execute("SELECT latitude, longitude, updated_at FROM shared_locations WHERE user_id = ? AND ride_id = ? ORDER BY updated_at DESC LIMIT 1", (peer_id, conv_id))
        peer_loc = cursor.fetchone()

        if peer_loc:
            dist_km = haversine_distance_km(lat, lng, peer_loc["latitude"], peer_loc["longitude"])
            if dist_km > 0.8: # 800m threshold (user specified 2-3 mins apart)
                diverge_start = conv["diverge_started_at"]
                if not diverge_start:
                    cursor.execute("UPDATE conversations SET diverge_started_at = ? WHERE id = ?", (now, conv_id))
                    conn.commit()
                else:
                    try:
                        start_dt = datetime.fromisoformat(diverge_start.replace("Z", "+00:00"))
                        now_dt = datetime.fromisoformat(now.replace("Z", "+00:00"))
                        seconds_diff = (now_dt - start_dt).total_seconds()
                        if seconds_diff >= 120 and not int(conv["diverge_alerted"] or 0):
                            cursor.execute("UPDATE conversations SET diverge_alerted = 1 WHERE id = ?", (conv_id,))
                            conn.commit()
                            alert_payload = {
                                "conversationId": conv_id,
                                "event": "trip_diverge_alert",
                                "title": "Are you end the ride?",
                                "message": "You and your companion are 800m+ apart. Did you complete the ride?",
                            }
                            await manager.send_to_pair(conv["user_a_id"], conv["user_b_id"], "trip_diverge_alert", alert_payload)
                    except Exception:
                        pass
            else:
                # Still together, reset diverge timer
                cursor.execute("UPDATE conversations SET diverge_started_at = NULL, diverge_alerted = 0 WHERE id = ?", (conv_id,))
                conn.commit()

    conn.close()
    return {"status": "ok"}


# Production Diagnostics & System Info
# =====================================================================

@app.get("/ride/api/system/info")
@app.get("/api/system/info")
def system_info():
    return {
        "status": "production_ready",
        "service": "DIU Ride Production Unified Backend",
        "environment": "Ubuntu Linux (Production)",
        "database": "SQLite WAL High-Concurrency Mode",
        "active_ws_connections": len(manager.active_connections),
        "auth_provider": "Self-Hosted DIU Server (Firebase Email Verification Gateway)",
        "timestamp": datetime.utcnow().isoformat(),
    }

# =====================================================================
# Static Web App Hosting for Flutter Web (Production Ubuntu)
# =====================================================================

import mimetypes
mimetypes.init()
mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/json", ".json")
mimetypes.add_type("text/css", ".css")
mimetypes.add_type("font/woff2", ".woff2")
mimetypes.add_type("font/woff", ".woff")
mimetypes.add_type("font/ttf", ".ttf")

# Check server/web_build first (deployed bundle), then fallback to parent web_build
web_dir = os.path.join(os.path.dirname(__file__), "web_build")
if not os.path.exists(web_dir):
    web_dir = os.path.join(os.path.dirname(__file__), "..", "web_build")

def _get_media_type(path: str) -> Optional[str]:
    mt, _ = mimetypes.guess_type(path)
    return mt

def _no_cache_response(file_path: str):
    response = FileResponse(file_path, media_type=_get_media_type(file_path))
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    response.headers["Surrogate-Control"] = "no-store"
    response.headers["CDN-Cache-Control"] = "no-store"
    response.headers["Cloudflare-CDN-Cache-Control"] = "no-store"
    return response

@app.get("/ride/api/app-update-info")
@app.get("/api/app-update-info")
def get_app_update_info():
    """Returns the latest app version and direct GitHub release download link."""
    return {
        "status": "success",
        "latestVersion": "1.0.9",
        "latestBuildNumber": 10,
        "githubReleaseUrl": "https://github.com/rahat300809/Diu_Rides/releases/latest",
        "githubDownloadUrl": "https://github.com/rahat300809/Diu_Rides/releases/latest/download/diu_ride.apk",
        "serverDownloadUrl": "https://servertest.eu.cc/ride/download-apk",
        "changelog": "Accurate authentication flow, student verifications database, leaving-now time fix, and live tracking."
    }

@app.api_route("/diu_ride.apk", methods=["GET", "HEAD"])
@app.api_route("/download-apk", methods=["GET", "HEAD"])
@app.api_route("/ride/diu_ride.apk", methods=["GET", "HEAD"])
@app.api_route("/ride/download-apk", methods=["GET", "HEAD"])
def download_apk():
    """
    Serves the latest DIU Ride Android APK directly from local server storage.
    No GitHub login required - 100% direct high-speed download.
    """
    candidates = [
        "/home/rahat/diu_ride/server/web_build/diu_ride.apk",
        "/home/rahat/diu_ride/web_build/diu_ride.apk",
        "/home/rahat/diu_ride/diu_ride.apk",
        os.path.join(web_dir, "diu_ride.apk"),
        os.path.join(os.path.dirname(__file__), "web_build", "diu_ride.apk"),
        os.path.join(os.path.dirname(__file__), "..", "web_build", "diu_ride.apk"),
        os.path.join(os.path.dirname(__file__), "diu_ride.apk"),
        os.path.join(os.path.dirname(__file__), "..", "diu_ride.apk"),
        os.path.join(os.path.dirname(__file__), "..", "build", "app", "outputs", "flutter-apk", "app-release.apk"),
    ]
    for apk_path in candidates:
        if os.path.isfile(apk_path):
            return FileResponse(
                apk_path,
                media_type="application/vnd.android.package-archive",
                filename="diu_ride.apk",
                headers={
                    "Content-Disposition": 'attachment; filename="diu_ride.apk"',
                    "Cache-Control": "public, max-age=300"
                }
            )
    github_url = "https://github.com/rahat300809/Diu_Rides/releases/latest/download/diu_ride.apk"
    return RedirectResponse(url=github_url, status_code=302)

@app.get("/ride/api/ai/live-rides")
@app.get("/api/ai/live-rides")
def get_live_rides_file_endpoint():
    rides = get_active_rides_from_file()
    return {
        "status": "success",
        "file": os.path.basename(ACTIVE_RIDES_JSON_PATH),
        "total_active_rides": len(rides),
        "rides": rides
    }

@app.get("/ride/api/ai/live-rides-markdown")
@app.get("/api/ai/live-rides-markdown")
def get_live_rides_markdown_endpoint():
    if os.path.exists(ACTIVE_RIDES_MD_PATH):
        with open(ACTIVE_RIDES_MD_PATH, "r", encoding="utf-8") as f:
            content = f.read()
    else:
        content = "# No active rides file found."
    return HTMLResponse(content=f"<pre style='font-family: monospace; white-space: pre-wrap; padding: 20px;'>{content}</pre>")

@app.post("/ride/api/ai/chat")
@app.post("/api/ai/chat")
async def ai_chat_endpoint(request: Request):
    try:
        payload = await request.json()
    except Exception:
        payload = {}
    conn = get_db()
    try:
        response = process_ai_chat_request(conn, payload)
        return response
    finally:
        conn.close()

@app.get("/")
def serve_root():
    if os.path.exists(web_dir):
        index_file = os.path.join(web_dir, "index.html")
        if os.path.isfile(index_file):
            return _no_cache_response(index_file)
    return JSONResponse({"status": "running", "service": "DIU Ride Production", "app_path": "/ride"})

@app.api_route("/ride", methods=["GET", "HEAD"])
def redirect_to_ride_slash(request: Request):
    query_str = request.url.query
    target = "/ride/" + (f"?{query_str}" if query_str else "")
    return RedirectResponse(url=target, status_code=307)

@app.api_route("/ride/", methods=["GET", "HEAD"])
def serve_ride_root():
    if os.path.exists(web_dir):
        index_file = os.path.join(web_dir, "index.html")
        if os.path.isfile(index_file):
            return _no_cache_response(index_file)
    return JSONResponse({"status": "running", "service": "DIU Ride Production"})

@app.get("/ride/flutter_bootstrap.js")
def serve_bootstrap():
    f = os.path.join(web_dir, "flutter_bootstrap.js")
    if os.path.isfile(f):
        return _no_cache_response(f)
    raise HTTPException(status_code=404, detail="Not found")

@app.get("/ride/flutter_service_worker.js")
def serve_sw():
    f = os.path.join(web_dir, "flutter_service_worker.js")
    if os.path.isfile(f):
        return _no_cache_response(f)
    raise HTTPException(status_code=404, detail="Not found")

@app.get("/ride/main.dart.js")
def serve_main_dart():
    f = os.path.join(web_dir, "main.dart.js")
    if os.path.isfile(f):
        return _no_cache_response(f)
    raise HTTPException(status_code=404, detail="Not found")

@app.api_route("/ride/admin", methods=["GET", "HEAD"], response_class=HTMLResponse)
@app.api_route("/ride/admin/", methods=["GET", "HEAD"], response_class=HTMLResponse)
@app.api_route("/admin", methods=["GET", "HEAD"], response_class=HTMLResponse)
@app.api_route("/admin/", methods=["GET", "HEAD"], response_class=HTMLResponse)
def serve_admin_direct():
    return HTMLResponse(content=ADMIN_HTML)

@app.api_route("/ride/{full_path:path}", methods=["GET", "HEAD"])
def serve_spa(full_path: str):
    if full_path in ("admin", "admin/"):
        return HTMLResponse(content=ADMIN_HTML)

    # Strictly prevent SPA from swallowing API 404s or WebSocket calls
    if full_path.startswith("api/") or full_path == "api" or full_path.startswith("ws"):
        raise HTTPException(status_code=404, detail=f"API route not found: /{full_path}")

    if os.path.exists(web_dir):
        file_path = os.path.join(web_dir, full_path)
        if os.path.isfile(file_path):
            if full_path.endswith((".html", ".js", ".json")):
                return _no_cache_response(file_path)
            return FileResponse(file_path, media_type=_get_media_type(file_path))
        index_file = os.path.join(web_dir, "index.html")
        if os.path.isfile(index_file):
            return _no_cache_response(index_file)
    return JSONResponse({"status": "running", "service": "DIU Ride", "path": full_path})


# Bind after all helpers exist (module import time).
try:
    bind_confirm_flow(
        get_db=get_db,
        manager=manager,
        save_and_broadcast_message=_save_and_broadcast_message,
        get_current_bd_time=get_current_bd_time,
        remove_ride_from_file=remove_ride_from_file,
        map_ride=map_ride,
    )
    print("[CONFIRM FLOW] helpers bound", flush=True)
except Exception as e:
    print(f"[CONFIRM FLOW BIND ERROR] {e}", flush=True)


@app.on_event("startup")
async def start_confirm_flow_workers():
    """Start 2-minute x3 confirm reminder background loop."""
    try:
        asyncio.create_task(periodic_confirm_reminder_task())
        print("[CONFIRM FLOW] reminder task started", flush=True)
    except Exception as e:
        print(f"[CONFIRM FLOW INIT ERROR] {e}", flush=True)

