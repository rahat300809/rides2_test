import os
import csv
import io
import json
import sqlite3
import hashlib
from datetime import datetime
from typing import Dict, Any, Optional, List
from fastapi import APIRouter, HTTPException, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from ai_service import (
    init_ai_settings_table,
    get_all_ai_settings,
    save_ai_settings,
    process_ai_chat_request,
    DEFAULT_SYSTEM_PROMPT,
    DEFAULT_GROQ_API_KEY,
    DEFAULT_MODEL_NAME,
)
from active_rides_manager import (
    sync_active_rides_file,
    get_active_rides_from_file,
    ACTIVE_RIDES_JSON_PATH,
    ACTIVE_RIDES_MD_PATH,
)
from hex_spatial_engine import (
    DROPPING_ZONES,
    find_nearest_dropping_zone,
    rank_bikers_by_hex_spatial_proximity,
    lat_lng_to_hex8,
    haversine_distance_m,
)

admin_router = APIRouter()

SALT = "diu_ride_salt_varsity_2026"

def hash_password(password: str) -> str:
    return hashlib.sha256((SALT + password).encode("utf-8")).hexdigest()

import hmac

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return hmac.compare_digest(hash_password(plain_password), hashed_password)
    except Exception:
        return False

def get_db_path():
    return os.path.join(os.path.dirname(__file__), "rides.db")

def get_admin_db():
    conn = sqlite3.connect(get_db_path(), timeout=20.0, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn

def init_admin_tables():
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS admins (
        id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT DEFAULT 'superadmin',
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        last_login TEXT
    );
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS notices (
        id TEXT PRIMARY KEY,
        admin_id TEXT NOT NULL,
        admin_email TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        target_audience TEXT NOT NULL,
        priority TEXT DEFAULT 'normal',
        created_at TEXT NOT NULL
    );
    """)

    # Pre-seed main admin: 252-15-234@diu.edu.bd
    main_admin_email = "252-15-234@diu.edu.bd"
    cursor.execute("SELECT id FROM admins WHERE email = ?", (main_admin_email,))
    row = cursor.fetchone()
    if not row:
        admin_id = "adm_main_252"
        now = datetime.utcnow().isoformat()
        # Default pass: Admin@diu2026 (changeable in admin portal)
        pwd_hash = hash_password("Admin@diu2026")
        cursor.execute("""
        INSERT INTO admins (id, email, name, password_hash, role, is_active, created_at)
        VALUES (?, ?, ?, ?, ?, 1, ?)
        """, (admin_id, main_admin_email, "Varsity Authority (Main Admin)", pwd_hash, "superadmin", now))
        conn.commit()
        print(f"[ADMIN INIT] Successfully initialized main admin: {main_admin_email}")

    # Initialize AI settings table
    init_ai_settings_table(conn)

    conn.close()

# Call initialization on module load
try:
    init_admin_tables()
except Exception as e:
    print(f"[ADMIN INIT ERROR]: {e}")

# =====================================================================
# REST Endpoints: Admin Authentication & Management
# =====================================================================

@admin_router.post("/ride/api/admin/login")
@admin_router.post("/api/admin/login")
async def admin_login(payload: Dict[str, Any]):
    email = (payload.get("email") or "").strip().lower()
    password = payload.get("password") or ""
    if not email or not password:
        raise HTTPException(status_code=400, detail="Email and password are required")

    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM admins WHERE LOWER(email) = ? AND is_active = 1", (email,))
    admin = cursor.fetchone()

    if not admin or not verify_password(password, admin["password_hash"]):
        conn.close()
        raise HTTPException(status_code=401, detail="Invalid admin credentials")

    now = datetime.utcnow().isoformat()
    cursor.execute("UPDATE admins SET last_login = ? WHERE id = ?", (now, admin["id"]))
    conn.commit()
    conn.close()

    return {
        "status": "success",
        "admin": {
            "id": admin["id"],
            "email": admin["email"],
            "name": admin["name"],
            "role": admin["role"],
            "lastLogin": now
        },
        "token": f"adm_tok_{admin['id']}_{int(datetime.utcnow().timestamp())}"
    }

@admin_router.post("/ride/api/admin/change-password")
@admin_router.post("/api/admin/change-password")
async def admin_change_password(payload: Dict[str, Any]):
    email = (payload.get("email") or "").strip().lower()
    old_password = payload.get("oldPassword") or ""
    new_password = payload.get("newPassword") or ""

    if not email or not new_password:
        raise HTTPException(status_code=400, detail="Email and new password are required")

    if len(new_password) < 6:
        raise HTTPException(status_code=400, detail="New password must be at least 6 characters")

    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM admins WHERE LOWER(email) = ? AND is_active = 1", (email,))
    admin = cursor.fetchone()

    if not admin:
        conn.close()
        raise HTTPException(status_code=404, detail="Admin account not found")

    # If old password provided, verify it (unless bypassed by superadmin)
    if old_password and not verify_password(old_password, admin["password_hash"]):
        conn.close()
        raise HTTPException(status_code=401, detail="Current password does not match")

    new_hash = hash_password(new_password)
    cursor.execute("UPDATE admins SET password_hash = ? WHERE id = ?", (new_hash, admin["id"]))
    conn.commit()
    conn.close()

    return {"status": "success", "message": f"Password updated successfully for {email}"}

@admin_router.post("/ride/api/admin/create-admin")
@admin_router.post("/api/admin/create-admin")
async def admin_create_new(payload: Dict[str, Any]):
    email = (payload.get("email") or "").strip().lower()
    name = (payload.get("name") or "").strip()
    password = payload.get("password") or ""
    role = payload.get("role") or "admin"

    if not email or not name or not password:
        raise HTTPException(status_code=400, detail="Email, name, and password are required")

    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT id FROM admins WHERE LOWER(email) = ?", (email,))
    if cursor.fetchone():
        conn.close()
        raise HTTPException(status_code=400, detail="An admin with this email already exists")

    admin_id = f"adm_{int(datetime.utcnow().timestamp())}"
    now = datetime.utcnow().isoformat()
    pwd_hash = hash_password(password)

    cursor.execute("""
    INSERT INTO admins (id, email, name, password_hash, role, is_active, created_at)
    VALUES (?, ?, ?, ?, ?, 1, ?)
    """, (admin_id, email, name, pwd_hash, role, now))
    conn.commit()
    conn.close()

    return {
        "status": "success",
        "message": f"New administrator {name} ({email}) created successfully",
        "admin": {"id": admin_id, "email": email, "name": name, "role": role, "createdAt": now}
    }

@admin_router.get("/ride/api/admin/admins")
@admin_router.get("/api/admin/admins")
async def admin_list():
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT id, email, name, role, is_active, created_at, last_login FROM admins ORDER BY created_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "email": r["email"],
        "name": r["name"],
        "role": r["role"],
        "isActive": bool(r["is_active"]),
        "createdAt": r["created_at"],
        "lastLogin": r["last_login"] or "Never"
    } for r in rows]

# =====================================================================
# REST Endpoints: Statistics & Database Records Explorer
# =====================================================================

@admin_router.get("/ride/api/admin/stats")
@admin_router.get("/api/admin/stats")
async def admin_stats():
    conn = get_admin_db()
    cursor = conn.cursor()

    cursor.execute("SELECT count(*) FROM users")
    total_users = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM users WHERE is_driver_registered = 1")
    total_drivers = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM rides")
    total_rides = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM rides WHERE status = 'active'")
    active_rides = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM bookings")
    total_bookings = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM completed_rides")
    completed_rides = cursor.fetchone()[0]

    cursor.execute("SELECT COALESCE(SUM(fare), 0.0) FROM completed_rides")
    total_fare_sum = float(cursor.fetchone()[0] or 0.0)

    cursor.execute("SELECT count(*) FROM sos_alerts")
    sos_alerts = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM notices")
    total_notices = cursor.fetchone()[0]

    try:
        cursor.execute("SELECT count(*) FROM passenger_requests")
        total_requests = cursor.fetchone()[0]
    except Exception:
        total_requests = 0

    try:
        cursor.execute("SELECT count(*) FROM passenger_requests WHERE status = 'open'")
        open_requests = cursor.fetchone()[0]
    except Exception:
        open_requests = 0

    try:
        cursor.execute("SELECT count(*) FROM campus_feed_posts")
        total_feed_posts = cursor.fetchone()[0]
    except Exception:
        total_feed_posts = 0

    conn.close()

    return {
        "totalUsers": total_users,
        "totalDrivers": total_drivers,
        "totalPassengers": max(0, total_users - total_drivers),
        "totalRides": total_rides,
        "activeRides": active_rides,
        "totalBookings": total_bookings,
        "completedRides": completed_rides,
        "totalFareSum": round(total_fare_sum, 2),
        "sosAlerts": sos_alerts,
        "totalNotices": total_notices,
        "totalRequests": total_requests,
        "openRequests": open_requests,
        "totalFeedPosts": total_feed_posts,
        "serverTimestamp": datetime.utcnow().isoformat(),
    }

@admin_router.get("/ride/api/admin/verifications")
@admin_router.get("/api/admin/verifications")
async def admin_get_verifications(status: Optional[str] = None, search: Optional[str] = None):
    conn = get_admin_db()
    cursor = conn.cursor()

    query = "SELECT * FROM student_verifications WHERE 1=1"
    params = []

    if status and status.lower() != 'all':
        query += " AND LOWER(verification_status) = LOWER(?)"
        params.append(status.strip())

    if search:
        s = f"%{search.strip()}%"
        query += " AND (full_name LIKE ? OR diu_email LIKE ? OR student_id LIKE ? OR phone LIKE ? OR department LIKE ?)"
        params.extend([s, s, s, s, s])

    query += " ORDER BY created_at DESC"
    cursor.execute(query, params)
    rows = cursor.fetchall()
    conn.close()

    items = []
    for r in rows:
        items.append({
            "id": r["id"],
            "studentId": r["student_id"],
            "fullName": r["full_name"],
            "email": r["diu_email"],
            "phone": r["phone"] or "",
            "department": r["department"] or "CSE",
            "batch": r["batch"] or "",
            "password": r["password_plain"] or r["password_hash"] or "",
            "passwordHash": r["password_hash"] or "",
            "verificationStatus": r["verification_status"] or "pending",
            "isVerified": bool(r["is_verified"]),
            "verificationMethod": r["verification_method"] or "firebase_email",
            "role": r["role"] or "student",
            "vehicleModel": r["vehicle_model"] or "",
            "vehiclePlate": r["vehicle_plate"] or "",
            "createdAt": r["created_at"] or "",
            "verifiedAt": r["verified_at"] or "",
            "lastLoginAt": r["last_login_at"] or "",
        })
    return {"status": "success", "count": len(items), "verifications": items}

@admin_router.post("/ride/api/admin/verifications/{verif_id}/verify")
@admin_router.post("/api/admin/verifications/{verif_id}/verify")
async def admin_verify_student(verif_id: str):
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM student_verifications WHERE id = ? OR student_id = ?", (verif_id, verif_id))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Student verification record not found")

    now = datetime.utcnow().isoformat()
    cursor.execute("""
        UPDATE student_verifications 
        SET is_verified = 1, verification_status = 'verified', verified_at = ?, verification_method = 'admin_approved'
        WHERE id = ?
    """, (now, row["id"]))
    cursor.execute("""
        UPDATE users 
        SET is_verified = 1, verification_status = 'verified', verified_at = ?
        WHERE student_id = ? OR LOWER(email) = LOWER(?)
    """, (now, row["student_id"], row["diu_email"]))
    conn.commit()
    conn.close()
    return {"status": "success", "message": f"Student {row['student_id']} ({row['full_name']}) verified successfully"}

@admin_router.delete("/ride/api/admin/verifications/{verif_id}")
@admin_router.delete("/api/admin/verifications/{verif_id}")
async def admin_delete_verification(verif_id: str):
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT student_id, diu_email FROM student_verifications WHERE id = ? OR student_id = ?", (verif_id, verif_id))
    row = cursor.fetchone()
    if row:
        cursor.execute("DELETE FROM student_verifications WHERE id = ? OR student_id = ?", (verif_id, verif_id))
        cursor.execute("DELETE FROM users WHERE student_id = ? OR LOWER(email) = LOWER(?)", (row[0], row[1].lower()))
        conn.commit()
    conn.close()
    return {"status": "success", "message": "Record removed from verification database"}

@admin_router.get("/ride/api/admin/users")
@admin_router.get("/api/admin/users")
async def admin_get_users(role: Optional[str] = None, search: Optional[str] = None):
    conn = get_admin_db()
    cursor = conn.cursor()

    query = "SELECT * FROM users WHERE 1=1"
    params = []

    if role == "driver":
        query += " AND is_driver_registered = 1"
    elif role == "passenger":
        query += " AND is_driver_registered = 0"

    if search:
        s = f"%{search.strip()}%"
        query += " AND (name LIKE ? OR email LIKE ? OR student_id LIKE ? OR phone LIKE ? OR department LIKE ?)"
        params.extend([s, s, s, s, s])

    query += " ORDER BY created_at DESC"
    cursor.execute(query, params)
    rows = cursor.fetchall()
    conn.close()

    users = []
    for r in rows:
        users.append({
            "id": r["id"],
            "studentId": r["student_id"],
            "name": r["name"],
            "email": r["email"],
            "phone": r["phone"] or "",
            "department": r["department"] or "CSE",
            "batch": r["batch"] or "",
            "rating": float(r["rating"] or 4.90),
            "isDriverRegistered": bool(r["is_driver_registered"]),
            "totalRidesAsDriver": int(r["total_rides_as_driver"] or 0),
            "totalRidesAsPassenger": int(r["total_rides_as_passenger"] or 0),
            "vehicleInfo": r["vehicle_info"] or "",
            "isVerified": bool(r["is_verified"]),
            "createdAt": r["created_at"],
        })
    return users

@admin_router.get("/ride/api/admin/rides")
@admin_router.get("/api/admin/rides")
async def admin_get_rides(status: Optional[str] = None, search: Optional[str] = None):
    conn = get_admin_db()
    cursor = conn.cursor()

    query = "SELECT * FROM rides WHERE 1=1"
    params = []

    if status and status != "all":
        query += " AND status = ?"
        params.append(status)

    if search:
        s = f"%{search.strip()}%"
        query += " AND (driver_name LIKE ? OR origin_name LIKE ? OR destination_name LIKE ? OR vehicle_model LIKE ?)"
        params.extend([s, s, s, s])

    query += " ORDER BY created_at DESC"
    cursor.execute(query, params)
    rows = cursor.fetchall()
    conn.close()

    rides = []
    for r in rows:
        rides.append({
            "id": r["id"],
            "driverId": r["driver_id"],
            "driverName": r["driver_name"],
            "driverPhone": r["driver_phone"] or "",
            "driverDept": r["driver_dept"] or "DIU Student",
            "originName": r["origin_name"],
            "destinationName": r["destination_name"],
            "waypointName": r["waypoint_name"] or "",
            "departureTime": r["departure_time"],
            "farePerSeat": float(r["fare_per_seat"]),
            "totalSeats": int(r["total_seats"]),
            "availableSeats": int(r["available_seats"]),
            "status": r["status"],
            "vehicleModel": r["vehicle_model"],
            "vehiclePlate": r["vehicle_plate"] or "",
            "startTime": r["start_time"] if "start_time" in r.keys() else None,
            "endTime": r["end_time"] if "end_time" in r.keys() else None,
            "startMapsLink": r["start_maps_link"] if "start_maps_link" in r.keys() else None,
            "endMapsLink": r["end_maps_link"] if "end_maps_link" in r.keys() else None,
            "createdAt": r["created_at"],
        })
    return rides

@admin_router.get("/ride/api/admin/bookings")
@admin_router.get("/api/admin/bookings")
async def admin_get_bookings():
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM bookings ORDER BY requested_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "rideId": r["ride_id"],
        "passengerId": r["passenger_id"],
        "passengerName": r["passenger_name"],
        "passengerPhone": r["passenger_phone"] or "",
        "passengerDept": r["passenger_dept"] or "DIU Student",
        "pickupPoint": r["pickup_point"],
        "dropoffPoint": r["dropoff_point"],
        "seatsBooked": int(r["seats_booked"]),
        "totalFare": float(r["total_fare"]),
        "status": r["status"],
        "requestedAt": r["requested_at"],
    } for r in rows]

@admin_router.get("/ride/api/admin/completed-rides")
@admin_router.get("/api/admin/completed-rides")
async def admin_get_completed():
    import urllib.parse
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT cr.*,
               COALESCE(NULLIF(cr.driver_phone, ''), ud.phone, '') as resolved_driver_phone,
               COALESCE(NULLIF(cr.driver_dept, ''), ud.department, 'CSE') as resolved_driver_dept,
               COALESCE(NULLIF(cr.driver_student_id, ''), ud.student_id, '') as resolved_driver_sid,
               COALESCE(NULLIF(cr.passenger_phone, ''), up.phone, '') as resolved_passenger_phone,
               COALESCE(NULLIF(cr.passenger_dept, ''), up.department, 'DIU Student') as resolved_passenger_dept,
               COALESCE(NULLIF(cr.passenger_student_id, ''), up.student_id, '') as resolved_passenger_sid
        FROM completed_rides cr
        LEFT JOIN users ud ON (cr.driver_id = ud.id OR cr.driver_id = ud.student_id OR LOWER(cr.driver_name) = LOWER(ud.name))
        LEFT JOIN users up ON (cr.passenger_id = up.id OR cr.passenger_id = up.student_id OR (cr.passenger_name IS NOT NULL AND LOWER(cr.passenger_name) = LOWER(up.name)))
        ORDER BY cr.completed_time DESC
    """)
    rows = cursor.fetchall()
    conn.close()

    result = []
    for r in rows:
        keys = r.keys()
        r_link = r["route_maps_link"] if "route_maps_link" in keys and r["route_maps_link"] else ""
        if not r_link and r["origin_name"] and r["destination_name"]:
            o_q = urllib.parse.quote(str(r["origin_name"]))
            d_q = urllib.parse.quote(str(r["destination_name"]))
            r_link = f"https://www.google.com/maps/dir/?api=1&origin={o_q}&destination={d_q}&travelmode=driving"

        dur = float(r["duration_minutes"]) if "duration_minutes" in keys and r["duration_minutes"] else 15.0
        notes = r["tracking_notes"] if "tracking_notes" in keys and r["tracking_notes"] else f"Verified DIU community transit: {r['origin_name']} ➔ {r['destination_name']}."

        result.append({
            "id": r["id"],
            "rideId": r["ride_id"],
            "driverId": r["driver_id"],
            "driverName": r["driver_name"],
            "driverPhone": r["resolved_driver_phone"] or "01700000000",
            "driverDept": r["resolved_driver_dept"] or "CSE",
            "driverStudentId": r["resolved_driver_sid"] or (r["driver_id"] if "-" in str(r["driver_id"]) else "DIU-Biker"),
            "passengerId": r["passenger_id"] or "",
            "passengerName": r["passenger_name"] or "Student Commuter",
            "passengerPhone": r["resolved_passenger_phone"] or "01800000000",
            "passengerDept": r["resolved_passenger_dept"] or "DIU Student",
            "passengerStudentId": r["resolved_passenger_sid"] or (r["passenger_id"] if "-" in str(r["passenger_id"]) else "DIU-Passenger"),
            "originName": r["origin_name"],
            "destinationName": r["destination_name"],
            "startTime": r["start_time"] or "",
            "completedTime": r["completed_time"],
            "durationMinutes": dur,
            "fare": float(r["fare"]),
            "startMapsLink": r["start_maps_link"] or "",
            "endMapsLink": r["end_maps_link"] or "",
            "routeMapsLink": r_link,
            "trackingNotes": notes,
            "rating": float(r["rating"] or 5.0),
            "feedback": r["feedback"] or "",
            "createdAt": r["created_at"],
        })
    return result

@admin_router.get("/ride/api/admin/sos-alerts")
@admin_router.get("/api/admin/sos-alerts")
async def admin_get_sos():
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM sos_alerts ORDER BY created_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "studentId": r["student_id"],
        "studentName": r["student_name"],
        "studentPhone": r["student_phone"] or "",
        "locationName": r["location_name"] or "DIU Campus",
        "latitude": r["latitude"],
        "longitude": r["longitude"],
        "status": r["status"],
        "createdAt": r["created_at"]
    } for r in rows]


# =====================================================================
# REST Endpoints: Passenger Commute Requests Management
# =====================================================================

@admin_router.get("/ride/api/admin/passenger-requests")
@admin_router.get("/api/admin/passenger-requests")
async def admin_get_passenger_requests(status: Optional[str] = None, search: Optional[str] = None):
    conn = get_admin_db()
    cursor = conn.cursor()
    query = "SELECT * FROM passenger_requests WHERE 1=1"
    params = []
    if status and status != "all":
        query += " AND status = ?"
        params.append(status)
    if search:
        s = f"%{search.strip()}%"
        query += " AND (passenger_name LIKE ? OR pickup LIKE ? OR dropoff LIKE ? OR passenger_dept LIKE ?)"
        params.extend([s, s, s, s])
    query += " ORDER BY created_at DESC"
    cursor.execute(query, params)
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "passengerId": r["passenger_id"],
        "passengerName": r["passenger_name"],
        "passengerPhone": r["passenger_phone"] or "",
        "passengerDept": r["passenger_dept"] or "CSE",
        "pickup": r["pickup"],
        "dropoff": r["dropoff"],
        "pickupLat": r["pickup_lat"],
        "pickupLng": r["pickup_lng"],
        "dropoffLat": r["dropoff_lat"],
        "dropoffLng": r["dropoff_lng"],
        "requestedTime": r["requested_time"],
        "proposedFare": float(r["proposed_fare"] or 50.0),
        "notes": r["notes"] or "",
        "status": r["status"] or "open",
        "acceptedByDriverName": r["accepted_by_driver_name"] if "accepted_by_driver_name" in r.keys() else "",
        "acceptedByDriverPhone": r["accepted_by_driver_phone"] if "accepted_by_driver_phone" in r.keys() else "",
        "createdAt": r["created_at"],
        "postDate": r["post_date"] if "post_date" in r.keys() else "",
        "postTime": r["post_time"] if "post_time" in r.keys() else "",
    } for r in rows]

@admin_router.delete("/ride/api/admin/passenger-requests/{request_id}")
@admin_router.delete("/api/admin/passenger-requests/{request_id}")
async def admin_delete_passenger_request(request_id: str):
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM passenger_requests WHERE id = ?", (request_id,))
    conn.commit()
    conn.close()
    if ws_manager_ref:
        try:
            await ws_manager_ref.broadcast("passenger_request_deleted", {"id": request_id, "reason": "admin_deleted"})
            await ws_manager_ref.broadcast("post_deleted", {"postId": request_id, "id": request_id, "type": "passenger_request"})
        except Exception:
            pass
    return {"status": "success", "message": f"Student request {request_id} removed by authority"}

# =====================================================================
# REST Endpoints: Campus News Feed Moderation
# =====================================================================

@admin_router.get("/ride/api/admin/feed")
@admin_router.get("/api/admin/feed")
async def admin_get_feed(category: Optional[str] = None, search: Optional[str] = None):
    conn = get_admin_db()
    cursor = conn.cursor()
    query = "SELECT * FROM campus_feed_posts WHERE 1=1"
    params = []
    if category and category != "all":
        query += " AND category = ?"
        params.append(category)
    if search:
        s = f"%{search.strip()}%"
        query += " AND (author_name LIKE ? OR content LIKE ? OR author_dept LIKE ?)"
        params.extend([s, s, s])
    query += " ORDER BY created_at DESC"
    cursor.execute(query, params)
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "authorId": r["author_id"],
        "authorName": r["author_name"],
        "authorDept": r["author_dept"] or "CSE",
        "authorStudentId": r["author_student_id"] or "",
        "content": r["content"],
        "category": r["category"] or "General",
        "imageUrl": r["image_url"] if "image_url" in r.keys() else "",
        "likesCount": int(r["likes_count"] or 0),
        "commentsCount": int(r["comments_count"] or 0),
        "createdAt": r["created_at"],
    } for r in rows]

@admin_router.delete("/ride/api/admin/feed/{post_id}")
@admin_router.delete("/api/admin/feed/{post_id}")
async def admin_delete_feed_post(post_id: str):
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM campus_feed_posts WHERE id = ?", (post_id,))
    cursor.execute("DELETE FROM campus_feed_comments WHERE post_id = ?", (post_id,))
    cursor.execute("DELETE FROM campus_feed_likes WHERE post_id = ?", (post_id,))
    conn.commit()
    conn.close()
    if ws_manager_ref:
        try:
            await ws_manager_ref.broadcast("feed_post_deleted", {"postId": post_id, "id": post_id})
        except Exception:
            pass
    return {"status": "success", "message": f"Feed post {post_id} removed from campus bulletin"}

# =====================================================================
# REST Endpoints: Direct Administrative Actions (Users & Rides)
# =====================================================================

@admin_router.post("/ride/api/admin/users/{user_id}/toggle-verify")
@admin_router.post("/api/admin/users/{user_id}/toggle-verify")
async def admin_toggle_verify_user(user_id: str):
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT is_verified, name FROM users WHERE id = ?", (user_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="User not found")
    new_val = 0 if row["is_verified"] else 1
    cursor.execute("UPDATE users SET is_verified = ? WHERE id = ?", (new_val, user_id))
    conn.commit()
    conn.close()
    status_label = "Verified" if new_val else "Unverified"
    return {"status": "success", "isVerified": bool(new_val), "message": f"User {row['name']} is now marked as {status_label}"}

@admin_router.delete("/ride/api/admin/users/{user_id}")
@admin_router.delete("/api/admin/users/{user_id}")
async def admin_delete_user(user_id: str):
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM users WHERE id = ?", (user_id,))
    cursor.execute("DELETE FROM rides WHERE driver_id = ?", (user_id,))
    cursor.execute("DELETE FROM bookings WHERE passenger_id = ?", (user_id,))
    cursor.execute("DELETE FROM passenger_requests WHERE passenger_id = ?", (user_id,))
    cursor.execute("DELETE FROM messages WHERE sender_id = ? OR receiver_id = ?", (user_id, user_id))
    cursor.execute("DELETE FROM conversations WHERE user_a_id = ? OR user_b_id = ?", (user_id, user_id))
    try:
        cursor.execute("DELETE FROM shared_locations WHERE user_id = ?", (user_id,))
        cursor.execute("DELETE FROM driver_locations WHERE driver_id = ?", (user_id,))
    except Exception:
        pass
    conn.commit()
    sync_active_rides_file(conn)
    conn.close()
    if ws_manager_ref:
        try:
            await ws_manager_ref.broadcast("user_deleted", {"userId": user_id})
        except Exception:
            pass
    return {"status": "success", "message": f"User {user_id} and associated records removed"}

@admin_router.post("/ride/api/admin/rides/{ride_id}/cancel")
@admin_router.post("/api/admin/rides/{ride_id}/cancel")
async def admin_cancel_ride(ride_id: str):
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE rides SET status = 'cancelled' WHERE id = ?", (ride_id,))
    cursor.execute("UPDATE bookings SET status = 'cancelled' WHERE ride_id = ? AND status != 'completed'", (ride_id,))
    conn.commit()
    sync_active_rides_file(conn)
    conn.close()
    if ws_manager_ref:
        try:
            await ws_manager_ref.broadcast("ride_cancelled", {"id": ride_id, "rideId": ride_id, "status": "cancelled"})
            await ws_manager_ref.broadcast("ride_session_status_changed", {"rideId": ride_id, "status": "cancelled", "reason": "Cancelled by varsity authority"})
            await ws_manager_ref.broadcast("booking_status_updated", {"rideId": ride_id, "status": "cancelled"})
        except Exception:
            pass
    return {"status": "success", "message": f"Ride {ride_id} has been cancelled by authority"}

@admin_router.delete("/ride/api/admin/rides/{ride_id}")
@admin_router.delete("/api/admin/rides/{ride_id}")
async def admin_delete_ride(ride_id: str):
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM rides WHERE id = ?", (ride_id,))
    cursor.execute("DELETE FROM bookings WHERE ride_id = ?", (ride_id,))
    conn.commit()
    sync_active_rides_file(conn)
    conn.close()
    if ws_manager_ref:
        try:
            await ws_manager_ref.broadcast("ride_deleted", {"id": ride_id, "rideId": ride_id})
            await ws_manager_ref.broadcast("post_deleted", {"postId": ride_id, "id": ride_id, "type": "ride"})
            await ws_manager_ref.broadcast("booking_status_updated", {"rideId": ride_id, "status": "cancelled"})
        except Exception:
            pass
    return {"status": "success", "message": f"Ride {ride_id} deleted from database"}

# =====================================================================
# REST Endpoints: Varsity Notices & Broadcast System
# =====================================================================

# Global reference to WebSocket connection manager, set by main.py
ws_manager_ref = None

def set_ws_manager(manager):
    global ws_manager_ref
    ws_manager_ref = manager

@admin_router.post("/ride/api/admin/notices")
@admin_router.post("/api/admin/notices")
async def admin_post_notice(payload: Dict[str, Any]):
    title = (payload.get("title") or "").strip()
    content = (payload.get("content") or "").strip()
    target_audience = (payload.get("targetAudience") or "all").lower() # "all", "riders", "passengers"
    priority = (payload.get("priority") or "normal").lower() # "normal", "urgent", "emergency"
    admin_email = payload.get("adminEmail") or "252-15-234@diu.edu.bd"

    if not title or not content:
        raise HTTPException(status_code=400, detail="Notice title and content are required")

    notice_id = f"notc_{int(datetime.utcnow().timestamp()*1000)}"
    now = datetime.utcnow().isoformat()

    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO notices (id, admin_id, admin_email, title, content, target_audience, priority, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (notice_id, "adm_main", admin_email, title, content, target_audience, priority, now))
    conn.commit()
    conn.close()

    notice_data = {
        "id": notice_id,
        "title": title,
        "body": content,
        "content": content,
        "message": content,
        "audience": target_audience,
        "targetAudience": target_audience,
        "priority": priority,
        "sender": "DIU Varsity Authority",
        "senderEmail": admin_email,
        "createdAt": now,
        "timestamp": now,
        "type": "varsity_notice"
    }

    # Broadcast to all active WebSocket clients (mobile app & web)
    if ws_manager_ref:
        try:
            await ws_manager_ref.broadcast("university_notice", notice_data)
            await ws_manager_ref.broadcast("announcement", notice_data)
            print(f"[VARSITY NOTICE BROADCAST] Sent to active WebSocket clients: {title}")
        except Exception as e:
            print(f"[NOTICE BROADCAST ERROR]: {e}")

    return {
        "status": "success",
        "message": f"Notice '{title}' broadcasted successfully to {target_audience.title()}!",
        "notice": notice_data
    }

@admin_router.get("/ride/api/admin/notices")
@admin_router.get("/api/admin/notices")
async def admin_get_notices():
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM notices ORDER BY created_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "adminEmail": r["admin_email"],
        "title": r["title"],
        "content": r["content"],
        "targetAudience": r["target_audience"],
        "priority": r["priority"],
        "createdAt": r["created_at"]
    } for r in rows]

# =====================================================================
# REST Endpoints: AI Assistant Settings & Realtime Chat Proxy
# =====================================================================

@admin_router.get("/ride/api/admin/ai-settings")
@admin_router.get("/api/admin/ai-settings")
async def admin_get_ai_settings():
    conn = get_admin_db()
    try:
        settings = get_all_ai_settings(conn)
        return {"status": "success", "settings": settings}
    finally:
        conn.close()

@admin_router.post("/ride/api/admin/ai-settings")
@admin_router.post("/api/admin/ai-settings")
async def admin_update_ai_settings(payload: Dict[str, Any]):
    conn = get_admin_db()
    try:
        updated = save_ai_settings(conn, payload)
        return {
            "status": "success",
            "message": "AI Assistant settings updated successfully in database!",
            "settings": updated
        }
    finally:
        conn.close()

@admin_router.post("/ride/api/admin/ai-reset-prompt")
@admin_router.post("/api/admin/ai-reset-prompt")
async def admin_reset_ai_prompt():
    conn = get_admin_db()
    try:
        updated = save_ai_settings(conn, {
            "system_prompt": DEFAULT_SYSTEM_PROMPT,
            "groq_api_key": DEFAULT_GROQ_API_KEY,
            "model_name": DEFAULT_MODEL_NAME,
        })
        return {
            "status": "success",
            "message": "System prompt reset to default cordial DIU Ride companion prompt",
            "settings": updated
        }
    finally:
        conn.close()

@admin_router.post("/ride/api/ai/chat")
@admin_router.post("/api/ai/chat")
async def public_ai_chat_endpoint(payload: Dict[str, Any]):
    conn = get_admin_db()
    try:
        res = process_ai_chat_request(conn, payload)
        return res
    finally:
        conn.close()

@admin_router.get("/ride/api/rides/suggest-nearest")
@admin_router.get("/api/rides/suggest-nearest")
async def suggest_nearest_bikers_endpoint(
    lat: float = 23.8775,
    lng: float = 90.3201,
    target_name: str = "",
    is_destination: bool = True,
):
    """
    Ranks live bikers using Google/Uber H3 Hexagonal Spatial Indexing.
    Provides proximity match score, exact meters, and nearest dropping zone.
    """
    active_rides = get_active_rides_from_file()
    nearest_drop_zone = find_nearest_dropping_zone(lat, lng)
    ranked = rank_bikers_by_hex_spatial_proximity(
        active_rides=active_rides,
        target_lat=lat,
        target_lng=lng,
        target_name=target_name,
        is_destination_search=is_destination,
    )
    return {
        "status": "success",
        "target": {
            "name": target_name or nearest_drop_zone["zone_name"],
            "lat": lat,
            "lng": lng,
            "h3_index": lat_lng_to_hex8(lat, lng),
        },
        "nearest_dropping_zone": nearest_drop_zone,
        "total_active_rides": len(active_rides),
        "total_matched": len(ranked),
        "ranked_bikers": ranked,
    }

@admin_router.get("/ride/api/spatial/dropping-zones")
@admin_router.get("/api/spatial/dropping-zones")
async def list_dropping_zones_endpoint():
    """
    Lists all 12 official DIU Campus & Key Dhaka Commute Dropping Zones
    with real-time counts of incoming active bikers.
    """
    active_rides = get_active_rides_from_file()
    zones_with_stats = []
    for zone in DROPPING_ZONES:
        z_copy = dict(zone)
        biker_count = 0
        for r in active_rides:
            d_lat = float(r.get("destination_lat") or r.get("destinationLat") or 23.8765)
            d_lng = float(r.get("destination_lng") or r.get("destinationLng") or 90.3204)
            dist = haversine_distance_m(zone["lat"], zone["lng"], d_lat, d_lng)
            if dist <= 1500:
                biker_count += 1
        z_copy["active_incoming_bikers"] = biker_count
        zones_with_stats.append(z_copy)

    return {
        "status": "success",
        "total_zones": len(zones_with_stats),
        "zones": zones_with_stats,
    }

GOOGLE_API_KEY = "AIzaSyD-hl4Vshm6lqgUopu4rHbwmUbbPNA7kfA"

TYPO_MAP = {
    "motijil": "motijheel",
    "motijl": "motijheel",
    "motijhil": "motijheel",
    "motejheel": "motijheel",
    "motejil": "motijheel",
    "motijel": "motijheel",
    "dhanmondy": "dhanmondi",
    "danmondi": "dhanmondi",
    "dhanmandi": "dhanmondi",
    "mirpor": "mirpur",
    "mirpr": "mirpur",
    "uttora": "uttara",
    "utara": "uttara",
    "asulia": "ashulia",
    "ashulea": "ashulia",
    "farmget": "farmgate",
    "farmgait": "farmgate",
    "gulsan": "gulshan",
    "bonani": "banani",
    "mohakali": "mohakhali",
    "khagon": "khagan",
    "gabtali": "gabtoli",
    "kolyanpur": "kalyanpur",
    "sabar": "savar",
    "diu": "daffodil smart city",
    "dafodil": "daffodil smart city",
    "hatirjil": "hatirjheel",
    "diabari": "uttara north metro",
    "diyabari": "uttara north metro",
}

@admin_router.get("/ride/api/places/autocomplete")
@admin_router.get("/api/places/autocomplete")
async def proxy_places_autocomplete_endpoint(q: str = ""):
    """
    Proxies Google Places (New) autocomplete API for Bangladesh destinations,
    with smart typo correction and phonetic normalization (e.g. motijil -> Motijheel).
    """
    import urllib.request
    clean = (q or "").strip()
    if not clean:
        return {"status": "success", "suggestions": []}

    # Normalize known typos / phonetic spellings
    words = clean.lower().split()
    corrected_words = [TYPO_MAP.get(w, w) for w in words]
    effective_query = " ".join(corrected_words)

    try:
        url = "https://places.googleapis.com/v1/places:autocomplete"
        headers = {
            "X-Goog-Api-Key": GOOGLE_API_KEY,
            "Content-Type": "application/json",
            "User-Agent": "DIU-Ride-Server/1.0",
        }
        data = json.dumps({
            "input": effective_query,
            "includedRegionCodes": ["bd"],
        }).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=6.0) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            return {
                "status": "success",
                "original_query": clean,
                "corrected_query": effective_query if effective_query != clean.lower() else None,
                "data": body
            }
    except Exception as e:
        return {"status": "error", "message": str(e), "suggestions": []}

@admin_router.get("/ride/api/places/routes")
@admin_router.get("/api/places/routes")
async def proxy_places_routes_endpoint(origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float):
    """
    Proxies Google Routes computeRoutes API / OSRM for turn-by-turn road paths.
    """
    import urllib.request
    try:
        url = "https://routes.googleapis.com/directions/v2:computeRoutes"
        headers = {
            "X-Goog-Api-Key": GOOGLE_API_KEY,
            "Content-Type": "application/json",
            "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.description",
            "User-Agent": "DIU-Ride-Server/1.0",
        }
        data = json.dumps({
            "origin": {"location": {"latLng": {"latitude": origin_lat, "longitude": origin_lng}}},
            "destination": {"location": {"latLng": {"latitude": dest_lat, "longitude": dest_lng}}},
            "travelMode": "DRIVE"
        }).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=7.0) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            return {"status": "success", "data": body}
    except Exception:
        # Fallback to OSRM
        try:
            osrm_url = f"https://router.project-osrm.org/route/v1/driving/{origin_lng},{origin_lat};{dest_lng},{dest_lat}?overview=full&geometries=geojson"
            req = urllib.request.Request(osrm_url, headers={"User-Agent": "DIU-Ride-Server/1.0"})
            with urllib.request.urlopen(req, timeout=6.0) as resp:
                body = json.loads(resp.read().decode("utf-8"))
                return {"status": "success", "source": "osrm", "data": body}
        except Exception as e:
            return {"status": "error", "message": str(e)}

@admin_router.get("/ride/api/places/details")
@admin_router.get("/api/places/details")
async def proxy_places_details_endpoint(place_id: str):
    """
    Proxies Google Places (New) Place Details API to fetch exact LatLng for a place ID.
    """
    import urllib.request
    clean_id = (place_id or "").strip().replace("places/", "")
    if not clean_id:
        return {"status": "error", "message": "Missing place_id"}
    try:
        url = f"https://places.googleapis.com/v1/places/{clean_id}?fields=id,displayName,location,formattedAddress"
        headers = {
            "X-Goog-Api-Key": GOOGLE_API_KEY,
            "User-Agent": "DIU-Ride-Server/1.0",
        }
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=6.0) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            loc = body.get("location", {})
            return {
                "status": "success",
                "lat": loc.get("latitude"),
                "lng": loc.get("longitude"),
                "address": body.get("formattedAddress"),
                "data": body
            }
    except Exception as e:
        return {"status": "error", "message": str(e)}

@admin_router.post("/ride/api/admin/sync-active-rides")
@admin_router.post("/api/admin/sync-active-rides")
async def admin_sync_active_rides_endpoint():
    conn = get_admin_db()
    try:
        rides = sync_active_rides_file(conn)
        return {
            "status": "success",
            "message": f"Successfully synchronized {len(rides)} active rides into active_rides_data.json",
            "count": len(rides),
            "file": os.path.basename(ACTIVE_RIDES_JSON_PATH)
        }
    finally:
        conn.close()

@admin_router.get("/ride/api/admin/active-rides-info")
@admin_router.get("/api/admin/active-rides-info")
async def admin_active_rides_info_endpoint():
    rides = get_active_rides_from_file()
    return {
        "status": "success",
        "count": len(rides),
        "file": os.path.basename(ACTIVE_RIDES_JSON_PATH),
        "rides": rides
    }

# =====================================================================
# REST Endpoints: CSV & PDF Data Export
# =====================================================================

@admin_router.get("/ride/api/admin/export/csv")
@admin_router.get("/api/admin/export/csv")
async def export_csv(type: str = "rides"):
    conn = get_admin_db()
    cursor = conn.cursor()
    output = io.StringIO()
    filename = f"diu_ride_{type}_{int(datetime.utcnow().timestamp())}.csv"

    if type == "users" or type == "riders" or type == "passengers":
        if type == "riders":
            cursor.execute("SELECT * FROM users WHERE is_driver_registered = 1 ORDER BY created_at DESC")
        elif type == "passengers":
            cursor.execute("SELECT * FROM users WHERE is_driver_registered = 0 ORDER BY created_at DESC")
        else:
            cursor.execute("SELECT * FROM users ORDER BY created_at DESC")
        rows = cursor.fetchall()
        fieldnames = ["student_id", "name", "email", "phone", "department", "batch", "role", "rating", "total_rides_as_driver", "total_rides_as_passenger", "vehicle_info", "is_verified", "created_at"]
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow({
                "student_id": r["student_id"],
                "name": r["name"],
                "email": r["email"],
                "phone": r["phone"] or "",
                "department": r["department"] or "CSE",
                "batch": r["batch"] or "",
                "role": "Biker / Rider" if r["is_driver_registered"] else "Passenger",
                "rating": r["rating"],
                "total_rides_as_driver": r["total_rides_as_driver"] or 0,
                "total_rides_as_passenger": r["total_rides_as_passenger"] or 0,
                "vehicle_info": r["vehicle_info"] or "",
                "is_verified": "Yes" if r["is_verified"] else "No",
                "created_at": r["created_at"]
            })

    elif type == "completed":
        cursor.execute("""
            SELECT cr.*,
                   COALESCE(NULLIF(cr.driver_phone, ''), ud.phone, '') as resolved_driver_phone,
                   COALESCE(NULLIF(cr.driver_dept, ''), ud.department, 'CSE') as resolved_driver_dept,
                   COALESCE(NULLIF(cr.driver_student_id, ''), ud.student_id, '') as resolved_driver_sid,
                   COALESCE(NULLIF(cr.passenger_phone, ''), up.phone, '') as resolved_passenger_phone,
                   COALESCE(NULLIF(cr.passenger_dept, ''), up.department, 'DIU Student') as resolved_passenger_dept,
                   COALESCE(NULLIF(cr.passenger_student_id, ''), up.student_id, '') as resolved_passenger_sid
            FROM completed_rides cr
            LEFT JOIN users ud ON (cr.driver_id = ud.id OR cr.driver_id = ud.student_id OR LOWER(cr.driver_name) = LOWER(ud.name))
            LEFT JOIN users up ON (cr.passenger_id = up.id OR cr.passenger_id = up.student_id OR (cr.passenger_name IS NOT NULL AND LOWER(cr.passenger_name) = LOWER(up.name)))
            ORDER BY cr.completed_time DESC
        """)
        rows = cursor.fetchall()
        fieldnames = [
            "trip_id", "driver_name", "driver_student_id", "driver_dept", "driver_phone",
            "passenger_name", "passenger_student_id", "passenger_dept", "passenger_phone",
            "origin", "destination", "route_maps_link", "start_time", "completed_time",
            "duration_minutes", "fare", "rating", "tracking_notes"
        ]
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        import urllib.parse
        for r in rows:
            keys = r.keys()
            r_link = r["route_maps_link"] if "route_maps_link" in keys and r["route_maps_link"] else ""
            if not r_link and r["origin_name"] and r["destination_name"]:
                o_q = urllib.parse.quote(str(r["origin_name"]))
                d_q = urllib.parse.quote(str(r["destination_name"]))
                r_link = f"https://www.google.com/maps/dir/?api=1&origin={o_q}&destination={d_q}&travelmode=driving"

            dur = float(r["duration_minutes"]) if "duration_minutes" in keys and r["duration_minutes"] else 15.0
            notes = r["tracking_notes"] if "tracking_notes" in keys and r["tracking_notes"] else f"Verified DIU community transit: {r['origin_name']} ➔ {r['destination_name']}."
            writer.writerow({
                "trip_id": r["id"],
                "driver_name": r["driver_name"],
                "driver_student_id": r["resolved_driver_sid"] or (r["driver_id"] if "-" in str(r["driver_id"]) else ""),
                "driver_dept": r["resolved_driver_dept"] or "CSE",
                "driver_phone": r["resolved_driver_phone"] or "",
                "passenger_name": r["passenger_name"] or "",
                "passenger_student_id": r["resolved_passenger_sid"] or (r["passenger_id"] if "-" in str(r["passenger_id"]) else ""),
                "passenger_dept": r["resolved_passenger_dept"] or "DIU Student",
                "passenger_phone": r["resolved_passenger_phone"] or "",
                "origin": r["origin_name"],
                "destination": r["destination_name"],
                "route_maps_link": r_link,
                "start_time": r["start_time"] or "",
                "completed_time": r["completed_time"],
                "duration_minutes": dur,
                "fare": r["fare"],
                "rating": r["rating"],
                "tracking_notes": notes,
            })

    elif type == "bookings":
        cursor.execute("SELECT * FROM bookings ORDER BY requested_at DESC")
        rows = cursor.fetchall()
        fieldnames = ["booking_id", "ride_id", "passenger_name", "passenger_id", "passenger_phone", "pickup_point", "dropoff_point", "seats_booked", "total_fare", "status", "requested_at"]
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow({
                "booking_id": r["id"],
                "ride_id": r["ride_id"],
                "passenger_name": r["passenger_name"],
                "passenger_id": r["passenger_id"],
                "passenger_phone": r["passenger_phone"] or "",
                "pickup_point": r["pickup_point"],
                "dropoff_point": r["dropoff_point"],
                "seats_booked": r["seats_booked"],
                "total_fare": r["total_fare"],
                "status": r["status"],
                "requested_at": r["requested_at"]
            })

    elif type == "requests":
        cursor.execute("SELECT * FROM passenger_requests ORDER BY created_at DESC")
        rows = cursor.fetchall()
        fieldnames = ["request_id", "passenger_name", "passenger_dept", "passenger_phone", "pickup", "dropoff", "requested_time", "proposed_fare", "notes", "status", "created_at"]
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow({
                "request_id": r["id"],
                "passenger_name": r["passenger_name"],
                "passenger_dept": r["passenger_dept"] or "CSE",
                "passenger_phone": r["passenger_phone"] or "",
                "pickup": r["pickup"],
                "dropoff": r["dropoff"],
                "requested_time": r["requested_time"],
                "proposed_fare": r["proposed_fare"] or 50.0,
                "notes": r["notes"] or "",
                "status": r["status"] or "open",
                "created_at": r["created_at"]
            })

    elif type == "feed":
        cursor.execute("SELECT * FROM campus_feed_posts ORDER BY created_at DESC")
        rows = cursor.fetchall()
        fieldnames = ["post_id", "author_name", "author_dept", "author_student_id", "category", "content", "likes_count", "comments_count", "image_url", "created_at"]
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow({
                "post_id": r["id"],
                "author_name": r["author_name"],
                "author_dept": r["author_dept"] or "CSE",
                "author_student_id": r["author_student_id"] or "",
                "category": r["category"] or "General",
                "content": r["content"],
                "likes_count": r["likes_count"] or 0,
                "comments_count": r["comments_count"] or 0,
                "image_url": r["image_url"] or "",
                "created_at": r["created_at"]
            })

    else: # type == 'rides' or default
        cursor.execute("SELECT * FROM rides ORDER BY created_at DESC")
        rows = cursor.fetchall()
        fieldnames = ["ride_id", "driver_name", "driver_id", "driver_phone", "origin", "destination", "waypoint", "departure_time", "fare_per_seat", "available_seats", "status", "bike_model", "bike_plate", "created_at"]
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow({
                "ride_id": r["id"],
                "driver_name": r["driver_name"],
                "driver_id": r["driver_id"],
                "driver_phone": r["driver_phone"] or "",
                "origin": r["origin_name"],
                "destination": r["destination_name"],
                "waypoint": r["waypoint_name"] or "",
                "departure_time": r["departure_time"],
                "fare_per_seat": r["fare_per_seat"],
                "available_seats": r["available_seats"],
                "status": r["status"],
                "bike_model": r["vehicle_model"],
                "bike_plate": r["vehicle_plate"] or "",
                "created_at": r["created_at"]
            })

    conn.close()
    output.seek(0)
    return StreamingResponse(
        io.BytesIO(output.getvalue().encode("utf-8")),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )

@admin_router.get("/ride/api/admin/export/pdf")
@admin_router.get("/api/admin/export/pdf")
async def export_printable_pdf(type: str = "all"):
    """
    Generates an official, print-ready DIU Varsity Authority Commute Audit Report
    which directly opens the browser's high-resolution print/PDF engine with university letterhead.
    """
    conn = get_admin_db()
    cursor = conn.cursor()

    cursor.execute("SELECT count(*) FROM users")
    tot_users = cursor.fetchone()[0]
    cursor.execute("SELECT count(*) FROM users WHERE is_driver_registered = 1")
    tot_drivers = cursor.fetchone()[0]
    cursor.execute("SELECT count(*) FROM rides")
    tot_rides = cursor.fetchone()[0]
    cursor.execute("SELECT count(*) FROM completed_rides")
    tot_comp = cursor.fetchone()[0]
    cursor.execute("SELECT COALESCE(SUM(fare), 0) FROM completed_rides")
    tot_fare = cursor.fetchone()[0]

    cursor.execute("SELECT * FROM completed_rides ORDER BY completed_time DESC LIMIT 50")
    comp_rows = cursor.fetchall()

    cursor.execute("SELECT * FROM users WHERE is_driver_registered = 1 ORDER BY created_at DESC LIMIT 50")
    driver_rows = cursor.fetchall()

    conn.close()

    now_str = datetime.now().strftime("%B %d, %Y - %I:%M %p")

    comp_table_rows = ""
    for r in comp_rows:
        comp_table_rows += f"""
        <tr>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{r['id']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-weight: bold; font-size: 11px;">{r['driver_name']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{r['passenger_name'] or 'Commuter'}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{r['origin_name']} ➔ {r['destination_name']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{r['completed_time'][:16].replace('T', ' ')}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-weight: bold; font-size: 11px; text-align: right;">৳{r['fare']:.0f}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px; text-align: center;">⭐ {r['rating']}</td>
        </tr>
        """

    drivers_table_rows = ""
    for d in driver_rows:
        drivers_table_rows += f"""
        <tr>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{d['student_id']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-weight: bold; font-size: 11px;">{d['name']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{d['department']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{d['phone']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{d['vehicle_info'] or 'Motorbike'}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px; text-align: center;">{d['total_rides_as_driver']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px; text-align: center;">⭐ {d['rating']}</td>
        </tr>
        """

    html = f"""<!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>DIU Ride Official Audit Report - Daffodil International University</title>
        <style>
            @page {{ size: A4 portrait; margin: 15mm; }}
            body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; color: #1F2937; margin: 0; padding: 20px; }}
            .header {{ display: flex; align-items: center; justify-content: space-between; border-bottom: 3px solid #1B5E20; padding-bottom: 15px; margin-bottom: 20px; }}
            .logo-area h1 {{ margin: 0; font-size: 22px; color: #1B5E20; font-weight: 800; }}
            .logo-area p {{ margin: 3px 0 0; font-size: 12px; color: #6B7280; }}
            .meta {{ text-align: right; font-size: 11px; color: #4B5563; }}
            .badge {{ display: inline-block; background: #E8F5E9; color: #166534; padding: 4px 10px; border-radius: 12px; font-weight: bold; font-size: 11px; margin-bottom: 4px; }}
            .kpi-grid {{ display: grid; grid-template-columns: repeat(5, 1fr); gap: 10px; margin-bottom: 25px; }}
            .kpi-card {{ background: #F9FAFB; border: 1px solid #E5E7EB; border-radius: 8px; padding: 10px; text-align: center; }}
            .kpi-val {{ font-size: 18px; font-weight: 800; color: #111827; }}
            .kpi-lbl {{ font-size: 10px; color: #6B7280; text-transform: uppercase; margin-top: 2px; }}
            h2 {{ font-size: 14px; color: #1B5E20; border-left: 4px solid #E65100; padding-left: 8px; margin: 24px 0 10px 0; }}
            table {{ width: 100%; border-collapse: collapse; margin-bottom: 20px; }}
            th {{ background: #F3F4F6; color: #374151; font-size: 11px; font-weight: 700; text-align: left; padding: 8px; border-bottom: 2px solid #D1D5DB; }}
            .footer-sign {{ margin-top: 50px; display: flex; justify-content: space-between; font-size: 12px; page-break-inside: avoid; }}
            .sign-box {{ width: 220px; text-align: center; border-top: 1px dashed #9CA3AF; padding-top: 8px; }}
            @media print {{
                .no-print {{ display: none !important; }}
                body {{ padding: 0; }}
            }}
        </style>
    </head>
    <body>
        <div class="no-print" style="margin-bottom: 20px; background: #1B5E20; padding: 12px 20px; border-radius: 8px; color: white; display: flex; justify-content: space-between; align-items: center;">
            <div style="font-weight: bold;">🖨️ DIU Transport Authority Official Printable Report</div>
            <div>
                <button onclick="window.print()" style="background: #E65100; color: white; border: none; padding: 8px 16px; border-radius: 6px; font-weight: bold; cursor: pointer;">Save as PDF / Print</button>
                <button onclick="window.close()" style="background: rgba(255,255,255,0.2); color: white; border: none; padding: 8px 14px; border-radius: 6px; margin-left: 8px; cursor: pointer;">Close</button>
            </div>
        </div>

        <div class="header">
            <div class="logo-area">
                <div class="badge">DAFFODIL INTERNATIONAL UNIVERSITY</div>
                <h1>DIU RIDE • CAMPUS COMMUTE AUDIT REPORT</h1>
                <p>Office of the Directorate of Student Affairs & Campus Transport Cell • Daffodil Smart City, Ashulia</p>
            </div>
            <div class="meta">
                <div><strong>Report Date:</strong> {now_str}</div>
                <div><strong>Authority Admin:</strong> 252-15-234@diu.edu.bd</div>
                <div><strong>Classification:</strong> Official University Record</div>
            </div>
        </div>

        <div class="kpi-grid">
            <div class="kpi-card">
                <div class="kpi-val">{tot_users}</div>
                <div class="kpi-lbl">Total Students</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-val">{tot_drivers}</div>
                <div class="kpi-lbl">Verified Bikers</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-val">{tot_rides}</div>
                <div class="kpi-lbl">Total Rides Offered</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-val">{tot_comp}</div>
                <div class="kpi-lbl">Completed Trips</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-val">৳{tot_fare:.0f}</div>
                <div class="kpi-lbl">Fuel Split Fare (BDT)</div>
            </div>
        </div>

        <h2>Section 1: Completed Rides & Route Audit Log (Recent Sample)</h2>
        <table>
            <thead>
                <tr>
                    <th>Trip ID</th>
                    <th>Driver / Biker</th>
                    <th>Passenger</th>
                    <th>Corridor (Route)</th>
                    <th>Completed Time</th>
                    <th style="text-align: right;">Fare</th>
                    <th style="text-align: center;">Rating</th>
                </tr>
            </thead>
            <tbody>
                {comp_table_rows}
            </tbody>
        </table>

        <h2>Section 2: Registered Student Motorbike Providers</h2>
        <table>
            <thead>
                <tr>
                    <th>Student ID</th>
                    <th>Rider Name</th>
                    <th>Department</th>
                    <th>Phone</th>
                    <th>Motorbike Model & Plate</th>
                    <th style="text-align: center;">Rides</th>
                    <th style="text-align: center;">Rating</th>
                </tr>
            </thead>
            <tbody>
                {drivers_table_rows}
            </tbody>
        </table>

        <div class="footer-sign">
            <div class="sign-box">
                Prepared by<br>
                <strong>Transport Operations Desk</strong>
            </div>
            <div class="sign-box">
                Verified by<br>
                <strong>Main Authority Admin (252-15-234)</strong>
            </div>
            <div class="sign-box">
                Approved by<br>
                <strong>Proctor & Student Affairs Cell</strong>
            </div>
        </div>

        <script>
            // Automatically prompt print dialog on load
            window.addEventListener('load', () => {{
                setTimeout(() => {{ window.print(); }}, 500);
            }});
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html)

# =====================================================================
# REST Endpoints: Full Single-Page Admin Portal Web Application
# =====================================================================

ADMIN_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0">
    <title>DIU Ride - Varsity Transit Authority & Operations Portal</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <style>
        :root {
            --sidebar-bg: #0B132B;
            --sidebar-surface: #111C44;
            --sidebar-border: #1E293B;
            --sidebar-text: #94A3B8;
            --sidebar-text-active: #FFFFFF;
            --sidebar-hover: rgba(255, 255, 255, 0.05);
            --sidebar-active-bg: linear-gradient(90deg, rgba(16, 185, 129, 0.16) 0%, rgba(16, 185, 129, 0.02) 100%);
            --sidebar-active-border: #10B981;
            
            --topbar-bg: #0F172A;
            --topbar-border: #1E293B;
            
            --primary: #059669;
            --primary-dark: #064E3B;
            --primary-light: #10B981;
            --accent: #EA580C;
            --accent-light: #F97316;
            
            --bg: #F1F5F9;
            --card-bg: #FFFFFF;
            --border: #E2E8F0;
            --border-hover: #CBD5E1;
            
            --text-main: #0F172A;
            --text-secondary: #334155;
            --text-muted: #64748B;
            
            --danger: #EF4444;
            --danger-bg: #FEF2F2;
            --success: #10B981;
            --success-bg: #ECFDF5;
            --warning: #F59E0B;
            --warning-bg: #FFFBEB;
            --info: #3B82F6;
            --info-bg: #EFF6FF;
            --purple: #8B5CF6;
            --purple-bg: #F5F3FF;
            
            --sidebar-w: 260px;
            --topbar-h: 62px;
            --radius-sm: 8px;
            --radius-md: 12px;
            --radius-lg: 16px;
            --radius-xl: 22px;
            --shadow-sm: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
            --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.08), 0 2px 4px -2px rgba(0, 0, 0, 0.05);
            --shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.08), 0 4px 6px -4px rgba(0, 0, 0, 0.04);
            --shadow-glow: 0 0 20px rgba(16, 185, 129, 0.25);
        }

        * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, sans-serif; }
        body { background-color: var(--bg); color: var(--text-main); min-height: 100vh; display: flex; flex-direction: column; overflow-x: hidden; }

        /* SCROLLBAR */
        ::-webkit-scrollbar { width: 6px; height: 6px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: #CBD5E1; border-radius: 999px; }
        ::-webkit-scrollbar-thumb:hover { background: #94A3B8; }

        /* =====================================================================
           TOP NAVBAR
           ===================================================================== */
        .navbar {
            background: var(--topbar-bg);
            border-bottom: 1px solid var(--topbar-border);
            color: #FFFFFF;
            height: var(--topbar-h);
            padding: 0 24px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            position: sticky;
            top: 0;
            z-index: 50;
            backdrop-filter: blur(8px);
        }

        .brand-box { display: flex; align-items: center; gap: 12px; }
        .brand-icon {
            width: 40px; height: 40px; background: linear-gradient(135deg, #10B981 0%, #059669 100%);
            border-radius: var(--radius-md); display: flex; align-items: center; justify-content: center;
            font-size: 20px; box-shadow: 0 4px 12px rgba(16, 185, 129, 0.35); flex-shrink: 0;
        }
        .brand-text h1 { font-size: 15px; font-weight: 800; letter-spacing: -0.2px; color: #FFFFFF; display: flex; align-items: center; gap: 8px; }
        .brand-badge {
            font-size: 10px; font-weight: 700; background: rgba(16, 185, 129, 0.2);
            color: #34D399; border: 1px solid rgba(16, 185, 129, 0.4); padding: 2px 8px; border-radius: 999px;
            text-transform: uppercase; letter-spacing: 0.5px;
        }
        .brand-text p { font-size: 11px; color: #94A3B8; font-weight: 500; margin-top: 1px; }

        .nav-actions { display: flex; align-items: center; gap: 8px; }
        
        .btn {
            padding: 8px 14px; border-radius: var(--radius-sm); font-weight: 600; font-size: 12px;
            cursor: pointer; border: none; transition: all 0.15s ease; display: inline-flex; align-items: center; gap: 6px;
            text-decoration: none; line-height: 1; user-select: none;
        }
        .btn-accent { background: linear-gradient(135deg, #F97316 0%, #EA580C 100%); color: white; box-shadow: 0 2px 8px rgba(234, 88, 12, 0.3); }
        .btn-accent:hover { background: linear-gradient(135deg, #FB923C 0%, #EA580C 100%); transform: translateY(-1px); box-shadow: 0 4px 12px rgba(234, 88, 12, 0.4); }
        .btn-outline { background: rgba(255, 255, 255, 0.08); color: #F1F5F9; border: 1px solid rgba(255, 255, 255, 0.15); }
        .btn-outline:hover { background: rgba(255, 255, 255, 0.15); border-color: rgba(255, 255, 255, 0.25); color: #FFFFFF; }
        .btn-secondary { background: #E2E8F0; color: #1E293B; }
        .btn-secondary:hover { background: #CBD5E1; color: #0F172A; }
        .btn-primary { background: linear-gradient(135deg, #10B981 0%, #059669 100%); color: white; box-shadow: 0 2px 8px rgba(16, 185, 129, 0.25); }
        .btn-primary:hover { background: linear-gradient(135deg, #34D399 0%, #059669 100%); transform: translateY(-1px); box-shadow: 0 4px 12px rgba(16, 185, 129, 0.35); }
        .btn-danger { background: #FEE2E2; color: #B91C1C; }
        .btn-danger:hover { background: #FCA5A5; color: #7F1D1D; }
        .btn-sm { padding: 5px 9px; font-size: 11px; border-radius: 6px; }

        /* LIVE STATUS PILL */
        .live-status-pill {
            display: inline-flex; align-items: center; gap: 7px;
            background: rgba(16, 185, 129, 0.12); border: 1px solid rgba(16, 185, 129, 0.3);
            padding: 5px 12px; border-radius: 999px; font-size: 11px; font-weight: 700; color: #34D399;
            font-family: 'JetBrains Mono', monospace;
        }
        .live-pulse {
            width: 7px; height: 7px; background: #10B981; border-radius: 50%;
            box-shadow: 0 0 0 rgba(16, 185, 129, 0.7);
            animation: pulse-ring 2s infinite;
        }
        @keyframes pulse-ring {
            0% { transform: scale(0.95); box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.7); }
            70% { transform: scale(1); box-shadow: 0 0 0 6px rgba(16, 185, 129, 0); }
            100% { transform: scale(0.95); box-shadow: 0 0 0 0 rgba(16, 185, 129, 0); }
        }

        .select-export {
            outline: none; background: rgba(255, 255, 255, 0.08); color: #F1F5F9;
            border: 1px solid rgba(255, 255, 255, 0.15); border-radius: var(--radius-sm);
            padding: 7px 12px; font-size: 12px; font-weight: 600; cursor: pointer;
        }
        .select-export option { background: #0F172A; color: #FFFFFF; }

        /* MOBILE MENU TOGGLE */
        .menu-toggle {
            display: none; width: 38px; height: 38px;
            background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.15);
            border-radius: var(--radius-sm); color: white; font-size: 18px;
            cursor: pointer; align-items: center; justify-content: center;
        }

        /* MOBILE DRAWER */
        .mobile-drawer {
            display: none; flex-direction: column; gap: 8px; padding: 14px 16px;
            background: #0B132B; border-top: 1px solid #1E293B; border-bottom: 1px solid #1E293B;
            box-shadow: var(--shadow-lg); position: sticky; top: var(--topbar-h); z-index: 49;
        }
        .mobile-drawer.open { display: flex; }
        .mobile-drawer .btn { width: 100%; justify-content: center; padding: 10px; font-size: 13px; }

        .mobile-section-picker {
            display: none; width: 100%; padding: 12px 14px; background: white;
            border: 1.5px solid var(--border); border-radius: var(--radius-md); font-size: 13.5px;
            font-weight: 700; color: var(--text-main); outline: none; margin-bottom: 12px;
            box-shadow: var(--shadow-sm);
        }

        /* =====================================================================
           APP LAYOUT
           ===================================================================== */
        .layout { display: flex; flex: 1; padding: 20px 24px; gap: 24px; }

        /* =====================================================================
           SIDEBAR (DARK THEME, CATEGORIZED, SLEEK)
           ===================================================================== */
        .sidebar {
            width: var(--sidebar-w); flex-shrink: 0; display: flex; flex-direction: column;
            background: var(--sidebar-bg); padding: 16px 12px; border-radius: var(--radius-lg);
            border: 1px solid var(--sidebar-border); box-shadow: var(--shadow-md);
            height: calc(100vh - var(--topbar-h) - 40px); overflow-y: auto; position: sticky; top: calc(var(--topbar-h) + 20px);
        }
        .sidebar::-webkit-scrollbar { width: 4px; }
        .sidebar::-webkit-scrollbar-thumb { background: #334155; border-radius: 4px; }

        .sidebar-header-box {
            padding: 8px 10px 14px 10px; border-bottom: 1px solid var(--sidebar-border); margin-bottom: 10px;
            display: flex; align-items: center; justify-content: space-between;
        }
        .sidebar-header-label { font-size: 11px; font-weight: 700; color: #64748B; text-transform: uppercase; letter-spacing: 0.8px; }
        .sidebar-header-badge { font-size: 10px; font-weight: 800; background: rgba(16, 185, 129, 0.15); color: #34D399; padding: 2px 6px; border-radius: 6px; }

        .nav-category {
            font-size: 10px; font-weight: 800; text-transform: uppercase;
            letter-spacing: 0.9px; color: #475569; padding: 14px 10px 6px 10px;
            display: flex; align-items: center; justify-content: space-between;
        }
        .nav-tab {
            display: flex; align-items: center; justify-content: space-between;
            padding: 9px 12px; border-radius: var(--radius-sm); font-size: 12.5px; font-weight: 600;
            color: var(--sidebar-text); cursor: pointer; transition: all 0.15s ease;
            margin-bottom: 2px; position: relative;
        }
        .nav-tab:hover { background: var(--sidebar-hover); color: var(--sidebar-text-active); }
        .nav-tab.active {
            background: var(--sidebar-active-bg); color: var(--sidebar-text-active); font-weight: 700;
            box-shadow: inset 3px 0 0 var(--sidebar-active-border);
        }
        .nav-tab .tab-title { display: flex; align-items: center; gap: 8px; }
        .nav-tab .tab-icon { font-size: 15px; width: 18px; text-align: center; }
        .nav-tab .badge {
            font-size: 10px; font-weight: 800; padding: 2px 6px; border-radius: 6px;
            background: #1E293B; color: #94A3B8; font-family: 'JetBrains Mono', monospace;
        }
        .nav-tab.active .badge {
            background: rgba(16, 185, 129, 0.25); color: #6EE7B7;
        }

        .sidebar-footer {
            margin-top: auto; padding-top: 14px; border-top: 1px solid var(--sidebar-border);
            display: flex; align-items: center; justify-content: space-between;
            font-size: 11px; color: #64748B;
        }
        .sidebar-user-pill {
            display: flex; align-items: center; gap: 8px; overflow: hidden;
        }
        .sidebar-user-avatar {
            width: 28px; height: 28px; border-radius: 50%; background: #1E293B;
            color: #34D399; font-weight: 800; font-size: 12px; display: flex; align-items: center; justify-content: center;
        }
        .sidebar-user-meta { display: flex; flex-direction: column; overflow: hidden; }
        .sidebar-user-name { font-size: 11.5px; font-weight: 700; color: #E2E8F0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .sidebar-user-role { font-size: 10px; color: #10B981; font-weight: 600; text-transform: uppercase; }

        /* =====================================================================
           MAIN CONTENT AREA
           ===================================================================== */
        .main-content { flex: 1; display: flex; flex-direction: column; gap: 20px; min-width: 0; }

        /* =====================================================================
           KPI STATS GRID (MODERN CARDS WITH COLORED ACCENTS)
           ===================================================================== */
        .stats-grid {
            display: grid; grid-template-columns: repeat(6, 1fr); gap: 14px;
        }
        .stat-card {
            background: white; border: 1px solid var(--border); border-radius: var(--radius-lg);
            padding: 16px; display: flex; flex-direction: column; justify-content: space-between; gap: 8px;
            box-shadow: var(--shadow-sm); transition: all 0.2s ease; position: relative; overflow: hidden;
        }
        .stat-card:hover { transform: translateY(-2px); box-shadow: var(--shadow-md); border-color: var(--border-hover); }
        
        .stat-card-top { display: flex; align-items: center; justify-content: space-between; }
        .stat-icon-bubble {
            width: 38px; height: 38px; border-radius: var(--radius-md); display: flex;
            align-items: center; justify-content: center; font-size: 18px;
        }
        .stat-label { font-size: 11px; font-weight: 700; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; }
        .stat-value { font-size: 24px; font-weight: 800; color: var(--text-main); font-family: 'JetBrains Mono', monospace; line-height: 1.1; margin-top: 4px; }
        .stat-desc { font-size: 11px; color: #94A3B8; font-weight: 500; }

        /* Card accent variations */
        .stat-blue .stat-icon-bubble { background: #EFF6FF; color: #2563EB; }
        .stat-emerald .stat-icon-bubble { background: #ECFDF5; color: #059669; }
        .stat-orange .stat-icon-bubble { background: #FFF7ED; color: #EA580C; }
        .stat-purple .stat-icon-bubble { background: #F5F3FF; color: #7C3AED; }
        .stat-teal .stat-icon-bubble { background: #F0FDFA; color: #0D9488; }
        .stat-indigo .stat-icon-bubble { background: #EEF2FF; color: #4F46E5; }

        /* =====================================================================
           CONTENT CONTAINER CARDS
           ===================================================================== */
        .content-card {
            background: white; border: 1px solid var(--border); border-radius: var(--radius-lg);
            box-shadow: var(--shadow-sm); overflow: hidden; display: flex; flex-direction: column;
        }
        .card-header {
            padding: 16px 20px; border-bottom: 1px solid var(--border);
            display: flex; align-items: center; justify-content: space-between;
            background: #FAFAFA; flex-wrap: wrap; gap: 12px;
        }
        .card-title { font-size: 15px; font-weight: 800; color: var(--text-main); display: flex; align-items: center; gap: 8px; }
        .toolbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
        .search-input {
            padding: 8px 14px; border: 1.5px solid var(--border); border-radius: var(--radius-sm); font-size: 12.5px;
            background: white; outline: none; transition: all 0.2s; min-width: 220px;
        }
        .search-input:focus { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(16, 185, 129, 0.15); }

        /* =====================================================================
           DATA TABLES (MODERN, CLEAN, STICKY HEADERS)
           ===================================================================== */
        .table-responsive { width: 100%; overflow-x: auto; max-height: 600px; -webkit-overflow-scrolling: touch; }
        table.data-table { width: 100%; border-collapse: separate; border-spacing: 0; text-align: left; font-size: 12.5px; }
        table.data-table th {
            background: #F8FAFC; color: #475569; font-weight: 700; font-size: 11px;
            text-transform: uppercase; letter-spacing: 0.5px; padding: 12px 14px;
            border-bottom: 1.5px solid var(--border); position: sticky; top: 0; z-index: 10;
            white-space: nowrap;
        }
        table.data-table td { padding: 12px 14px; border-bottom: 1px solid #F1F5F9; color: var(--text-secondary); vertical-align: middle; }
        table.data-table tbody tr { transition: background-color 0.15s ease; }
        table.data-table tbody tr:hover { background-color: #F8FAFC; }
        table.data-table tbody tr:last-child td { border-bottom: none; }

        /* STATUS PILLS */
        .pill {
            display: inline-flex; align-items: center; gap: 4px; padding: 3px 8px;
            border-radius: 999px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.3px;
        }
        .pill-green { background: #ECFDF5; color: #047857; border: 1px solid #A7F3D0; }
        .pill-blue { background: #EFF6FF; color: #1D4ED8; border: 1px solid #BFDBFE; }
        .pill-amber { background: #FFFBEB; color: #B45309; border: 1px solid #FDE68A; }
        .pill-red { background: #FEF2F2; color: #B91C1C; border: 1px solid #FECACA; }
        .pill-purple { background: #F5F3FF; color: #6D28D9; border: 1px solid #DDD6FE; }

        /* =====================================================================
           MODAL OVERLAY & DIALOGS
           ===================================================================== */
        .modal-overlay {
            position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(15, 23, 42, 0.7);
            display: none; align-items: center; justify-content: center; z-index: 100; padding: 20px;
            backdrop-filter: blur(4px);
        }
        .modal {
            background: white; border-radius: var(--radius-xl); max-width: 580px; width: 100%; padding: 26px;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.35); display: flex; flex-direction: column; gap: 16px;
            max-height: 90vh; overflow-y: auto; border: 1px solid rgba(255, 255, 255, 0.2);
            animation: modalIn 0.2s ease-out;
        }
        @keyframes modalIn {
            from { opacity: 0; transform: scale(0.96) translateY(8px); }
            to { opacity: 1; transform: scale(1) translateY(0); }
        }
        .modal-header { display: flex; justify-content: space-between; align-items: center; padding-bottom: 12px; border-bottom: 1px solid var(--border); }
        .form-group { display: flex; flex-direction: column; gap: 6px; }
        .form-group label { font-size: 12px; font-weight: 700; color: #334155; }
        .form-control {
            padding: 10px 14px; border: 1.5px solid var(--border); border-radius: var(--radius-sm); font-size: 13px; outline: none;
            transition: all 0.2s ease;
        }
        .form-control:focus { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(16, 185, 129, 0.15); }

        /* =====================================================================
           AUTHENTICATION GATE SCREEN (SLEEK DARK)
           ===================================================================== */
        .login-wrap {
            position: fixed; inset: 0;
            background: radial-gradient(circle at 50% 30%, #0F3820 0%, #0B132B 60%, #070B18 100%);
            display: flex; align-items: center; justify-content: center; z-index: 200; padding: 20px;
        }
        .login-card {
            background: rgba(255, 255, 255, 0.96); border-radius: var(--radius-xl); padding: 40px; max-width: 440px; width: 100%;
            box-shadow: 0 25px 60px -15px rgba(0,0,0,0.5), 0 0 0 1px rgba(255, 255, 255, 0.2);
            text-align: center; display: flex; flex-direction: column; gap: 18px;
            backdrop-filter: blur(16px);
        }

        /* =====================================================================
           CAMPUS FEED CARDS
           ===================================================================== */
        .feed-grid { display: flex; flex-direction: column; gap: 14px; padding: 18px; }
        .feed-card {
            border: 1px solid var(--border); border-radius: var(--radius-md); padding: 18px;
            display: flex; flex-direction: column; gap: 12px; background: white;
            box-shadow: var(--shadow-sm); transition: all 0.2s ease;
        }
        .feed-card:hover { border-color: var(--border-hover); box-shadow: var(--shadow-md); }
        .feed-header { display: flex; justify-content: space-between; align-items: flex-start; }
        .feed-author { display: flex; align-items: center; gap: 12px; }
        .feed-avatar {
            width: 40px; height: 40px; border-radius: 50%; background: linear-gradient(135deg, #ECFDF5 0%, #D1FAE5 100%);
            color: var(--primary); display: flex; align-items: center; justify-content: center; font-weight: 800; font-size: 16px;
            border: 1px solid #A7F3D0;
        }
        .feed-img-thumb {
            max-width: 240px; max-height: 150px; border-radius: var(--radius-md); object-fit: cover;
            border: 1px solid var(--border); cursor: pointer; transition: transform 0.2s;
        }
        .feed-img-thumb:hover { transform: scale(1.02); }

        #lightboxImg { max-width: 90vw; max-height: 80vh; object-fit: contain; border-radius: var(--radius-md); }

        /* =====================================================================
           RESPONSIVE BREAKPOINTS
           ===================================================================== */
        @media (max-width: 1200px) {
            .stats-grid { grid-template-columns: repeat(3, 1fr); }
        }

        @media (max-width: 860px) {
            .navbar { padding: 0 16px; }
            .brand-text p { display: none; }
            .nav-actions { display: none; }
            .menu-toggle { display: flex; }

            .layout { flex-direction: column; padding: 14px; gap: 16px; }
            .mobile-section-picker { display: block; }
            .sidebar { display: none; }

            .stats-grid { grid-template-columns: repeat(2, 1fr); gap: 10px; }
            .stat-value { font-size: 20px; }
        }

        @media (max-width: 540px) {
            .stats-grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>

    <!-- AUTHENTICATION GATE SCREEN -->
    <div id="loginGate" class="login-wrap">
        <div class="login-card">
            <div style="width: 64px; height: 64px; background: linear-gradient(135deg, #10B981 0%, #059669 100%); color: white; border-radius: var(--radius-lg); display: flex; align-items: center; justify-content: center; font-size: 30px; margin: 0 auto; box-shadow: 0 8px 20px rgba(16, 185, 129, 0.35);">
                🛡️
            </div>
            <div>
                <h2 style="font-size: 22px; font-weight: 800; color: #0F172A; letter-spacing: -0.3px;">Varsity Authority Login</h2>
                <p style="font-size: 13px; color: var(--text-muted); margin-top: 4px;">Daffodil International University • Transport Control Desk</p>
            </div>
            <div style="background: #F8FAFC; border: 1px solid #E2E8F0; border-radius: var(--radius-md); padding: 12px 14px; font-size: 12px; color: #475569; text-align: left; line-height: 1.5;">
                👤 <strong>Super Admin:</strong> <code>252-15-234@diu.edu.bd</code><br>
                🔑 <strong>Default Password:</strong> <code>Admin@diu2026</code>
            </div>
            <div class="form-group" style="text-align: left;">
                <label>Administrator Email</label>
                <input id="loginEmail" type="email" class="form-control" value="252-15-234@diu.edu.bd" placeholder="admin@diu.edu.bd">
            </div>
            <div class="form-group" style="text-align: left;">
                <label>Password</label>
                <input id="loginPass" type="password" class="form-control" value="Admin@diu2026" placeholder="Enter password">
            </div>
            <div id="loginErr" style="color: var(--danger); font-size: 12.5px; font-weight: 700; display: none;"></div>
            <button class="btn btn-primary" style="justify-content: center; padding: 13px; font-size: 14px; border-radius: var(--radius-md); font-weight: 700;" onclick="doAdminLogin()">
                Access Authority Portal ➔
            </button>
        </div>
    </div>

    <!-- MAIN APP NAVBAR (SLIM & DARK) -->
    <header class="navbar">
        <div class="brand-box">
            <div class="brand-icon">🏍️</div>
            <div class="brand-text">
                <h1>
                    <span>DIU RIDE AUTHORITY</span>
                    <span class="brand-badge">PROCTORIAL DESK</span>
                </h1>
                <p>Campus Commute Realtime Database & Administration • Daffodil Smart City</p>
            </div>
        </div>
        <div class="nav-actions">
            <div class="live-status-pill">
                <span class="live-pulse"></span> <span id="clockDisplay">Syncing...</span>
            </div>
            <select class="select-export" onchange="handleQuickExport(this.value); this.selectedIndex=0;">
                <option value="">📥 Quick Export Data ▾</option>
                <option value="users">👥 All Students CSV</option>
                <option value="riders">🏍️ Verified Bikers CSV</option>
                <option value="rides">🛣️ Active Rides CSV</option>
                <option value="requests">🙋‍♂️ Student Requests CSV</option>
                <option value="completed">🏁 Completed Trips CSV</option>
                <option value="feed">📰 Campus Feed CSV</option>
                <option value="pdf">🖨️ Official Audit PDF</option>
            </select>
            <a href="/ride/download-apk" class="btn btn-outline" download="diu_ride.apk">📥 Download APK (v1.0.1)</a>
            <button class="btn btn-accent" onclick="openNoticeModal()">📢 Broadcast Notice</button>
            <button class="btn btn-outline" onclick="openPassModal()">🔑 Password</button>
            <button class="btn btn-outline" onclick="openAddAdminModal()">➕ Admin</button>
            <button class="btn btn-outline" onclick="doLogout()">🚪 Exit</button>
        </div>
        <button class="menu-toggle" id="menuToggleBtn" onclick="toggleMobileMenu()" aria-label="Toggle Navigation Actions">
            ☰
        </button>
    </header>

    <!-- MOBILE ACTIONS COLLAPSIBLE DRAWER -->
    <div id="mobileDrawer" class="mobile-drawer">
        <button class="btn btn-accent" onclick="openNoticeModal(); toggleMobileMenu();">📢 Broadcast Varsity Notice</button>
        <button class="btn btn-outline" onclick="openPassModal(); toggleMobileMenu();">🔑 Change Password</button>
        <button class="btn btn-outline" onclick="openAddAdminModal(); toggleMobileMenu();">➕ Add Administrator</button>
        <a href="/ride/download-apk" class="btn btn-outline" download="diu_ride.apk" onclick="toggleMobileMenu();">📥 Download APK (v1.0.1)</a>
        <button class="btn btn-danger" onclick="doLogout()">🚪 Exit / Logout</button>
    </div>

    <!-- CONTENT LAYOUT -->
    <div class="layout">
        <!-- MOBILE SECTION DROPDOWN PICKER (STRUCTURED WITH OPTGROUPS) -->
        <select class="mobile-section-picker" id="mobileSectionPicker" onchange="switchTab(this.value)">
            <optgroup label="🚀 Core Operations">
                <option value="dashboard">📊 Executive Dashboard</option>
                <option value="fleet_map">🗺️ Live Commute & Fleet Radar</option>
                <option value="rides">🛣️ Live Rides & Corridors</option>
                <option value="requests">🙋‍♂️ Student Ride Requests Board</option>
            </optgroup>
            <optgroup label="👥 Community & Moderation">
                <option value="users">👥 Students & Commuters</option>
                <option value="riders">🏍️ Motorbike Riders</option>
                <option value="passengers">🎒 Passenger Directory</option>
                <option value="feed">📰 Campus News Feed Moderation</option>
            </optgroup>
            <optgroup label="📑 Transactions & Audit">
                <option value="bookings">📑 Booking Orders</option>
                <option value="completed">🏁 Completed Trips Audit</option>
            </optgroup>
            <optgroup label="🛡️ Authority & Security">
                <option value="sos">🚨 Emergency SOS Logs</option>
                <option value="notices">📢 University Notices</option>
                <option value="admins">🛡️ Authority Admins</option>
                <option value="ai_assistant">🤖 DIU AI Agent Settings</option>
            </optgroup>
        </select>

        <!-- STRUCTURED CATEGORIZED DARK SIDEBAR -->
        <nav class="sidebar">
            <div class="sidebar-header-box">
                <span class="sidebar-header-label">Operations Console</span>
                <span class="sidebar-header-badge">v2.4 Pro</span>
            </div>

            <div class="nav-category">🚀 Core Operations</div>
            <div class="nav-tab active" onclick="switchTab('dashboard')">
                <span class="tab-title"><span class="tab-icon">📊</span> <span>Dashboard</span></span>
            </div>
            <div class="nav-tab" onclick="switchTab('fleet_map')">
                <span class="tab-title"><span class="tab-icon">🗺️</span> <span>Fleet Radar & Map</span></span>
            </div>
            <div class="nav-tab" onclick="switchTab('rides')">
                <span class="tab-title"><span class="tab-icon">🛣️</span> <span>Live Rides</span></span>
                <span class="badge" id="sideBadgeRides">0</span>
            </div>
            <div class="nav-tab" onclick="switchTab('requests')">
                <span class="tab-title"><span class="tab-icon">🙋‍♂️</span> <span>Student Requests</span></span>
                <span class="badge" id="sideBadgeRequests">0</span>
            </div>

            <div class="nav-category">👥 Community & Moderation</div>
            <div class="nav-tab" onclick="switchTab('verifications')">
          <span class="nav-tab-icon">🎓</span>
          <span>Student Verifications DB</span>
        </div>
        <div class="nav-tab" onclick="switchTab('users')">
                <span class="tab-title"><span class="tab-icon">👥</span> <span>All Students</span></span>
            </div>
            <div class="nav-tab" onclick="switchTab('riders')">
                <span class="tab-title"><span class="tab-icon">🏍️</span> <span>Verified Bikers</span></span>
            </div>
            <div class="nav-tab" onclick="switchTab('passengers')">
                <span class="tab-title"><span class="tab-icon">🎒</span> <span>Passengers</span></span>
            </div>
            <div class="nav-tab" onclick="switchTab('feed')">
                <span class="tab-title"><span class="tab-icon">📰</span> <span>Campus Feed</span></span>
                <span class="badge" id="sideBadgeFeed">0</span>
            </div>

            <div class="nav-category">📑 Transactions & Audit</div>
            <div class="nav-tab" onclick="switchTab('bookings')">
                <span class="tab-title"><span class="tab-icon">📑</span> <span>Booking Orders</span></span>
            </div>
            <div class="nav-tab" onclick="switchTab('completed')">
                <span class="tab-title"><span class="tab-icon">🏁</span> <span>Completed Trips</span></span>
            </div>

            <div class="nav-category">🛡️ Authority & Safety</div>
            <div class="nav-tab" onclick="switchTab('sos')">
                <span class="tab-title"><span class="tab-icon">🚨</span> <span>Emergency SOS</span></span>
                <span class="badge" style="background: rgba(239, 68, 68, 0.2); color: #F87171;" id="sideBadgeSos">0</span>
            </div>
            <div class="nav-tab" onclick="switchTab('notices')">
                <span class="tab-title"><span class="tab-icon">📢</span> <span>Varsity Notices</span></span>
            </div>
            <div class="nav-tab" onclick="switchTab('admins')">
                <span class="tab-title"><span class="tab-icon">🛡️</span> <span>Administrators</span></span>
            </div>
            <div class="nav-tab" onclick="switchTab('ai_assistant')">
                <span class="tab-title"><span class="tab-icon">🤖</span> <span>AI Agent Settings</span></span>
            </div>

            <div class="sidebar-footer">
                <div class="sidebar-user-pill">
                    <div class="sidebar-user-avatar">VA</div>
                    <div class="sidebar-user-meta">
                        <span class="sidebar-user-name">Varsity Authority</span>
                        <span class="sidebar-user-role">Super Admin</span>
                    </div>
                </div>
                <button class="btn btn-outline btn-sm" onclick="doLogout()" title="Sign Out">🚪</button>
            </div>
        </nav>

        <!-- MAIN AREA -->
        <main class="main-content">
            <!-- KPIS (MODERN CARDS WITH COLORED BUBBLES) -->
            <div class="stats-grid">
                <div class="stat-card stat-blue">
                    <div class="stat-card-top">
                        <span class="stat-label">Total Students</span>
                        <div class="stat-icon-bubble">👥</div>
                    </div>
                    <div>
                        <div class="stat-value" id="kpiUsers">0</div>
                        <div class="stat-desc">Registered Accounts</div>
                    </div>
                </div>

                <div class="stat-card stat-emerald">
                    <div class="stat-card-top">
                        <span class="stat-label">Verified Bikers</span>
                        <div class="stat-icon-bubble">🏍️</div>
                    </div>
                    <div>
                        <div class="stat-value" id="kpiDrivers" style="color: #059669;">0</div>
                        <div class="stat-desc">Offering Commute Seats</div>
                    </div>
                </div>

                <div class="stat-card stat-orange">
                    <div class="stat-card-top">
                        <span class="stat-label">Active Rides Now</span>
                        <div class="stat-icon-bubble">🛣️</div>
                    </div>
                    <div>
                        <div class="stat-value" id="kpiActiveRides" style="color: #EA580C;">0</div>
                        <div class="stat-desc">Live on Road</div>
                    </div>
                </div>

                <div class="stat-card stat-purple">
                    <div class="stat-card-top">
                        <span class="stat-label">Student Requests</span>
                        <div class="stat-icon-bubble">🙋‍♂️</div>
                    </div>
                    <div>
                        <div class="stat-value" id="kpiRequests" style="color: #7C3AED;">0</div>
                        <div class="stat-desc">Open Commute Needs</div>
                    </div>
                </div>

                <div class="stat-card stat-teal">
                    <div class="stat-card-top">
                        <span class="stat-label">Completed Trips</span>
                        <div class="stat-icon-bubble">🏁</div>
                    </div>
                    <div>
                        <div class="stat-value" id="kpiCompleted">0</div>
                        <div class="stat-desc">Audited & Verified</div>
                    </div>
                </div>

                <div class="stat-card stat-indigo">
                    <div class="stat-card-top">
                        <span class="stat-label">Fuel Shared</span>
                        <div class="stat-icon-bubble">৳</div>
                    </div>
                    <div>
                        <div class="stat-value" id="kpiFare">৳0</div>
                        <div class="stat-desc">Commuter Total (BDT)</div>
                    </div>
                </div>
            </div>

            <!-- DYNAMIC TAB PANELS -->
            <div id="panelContent">
                <!-- Loaded via JS -->
            </div>
        </main>
    </div>

    <!-- BROADCAST NOTICE MODAL -->
    <div id="noticeModal" class="modal-overlay">
        <div class="modal">
            <div class="modal-header">
                <h3 style="font-size: 16px; font-weight: 800; color: var(--primary);">📢 Broadcast University Notice</h3>
                <button onclick="closeModal('noticeModal')" style="background: none; border: none; font-size: 18px; cursor: pointer; color: #64748B;">✕</button>
            </div>
            <p style="font-size: 12px; color: var(--text-muted);">
                Transmitted in real-time to all connected student phones and mobile app terminals with alert chime.
            </p>
            <div class="form-group">
                <label>Notice Headline / Title</label>
                <input id="notcTitle" type="text" class="form-control" placeholder="e.g. Birulia Highway Alert / Exam Rush Commute">
            </div>
            <div class="form-group">
                <label>Notice Content & Instructions</label>
                <textarea id="notcContent" class="form-control" rows="4" placeholder="Enter clear instructions for campus commuters..."></textarea>
            </div>
            <div class="form-group">
                <label>Target Audience</label>
                <select id="notcAudience" class="form-control">
                    <option value="all">Everyone (All Riders & Passengers)</option>
                    <option value="riders">Bikers Only (Motorbike Riders)</option>
                    <option value="passengers">Passengers Only</option>
                </select>
            </div>
            <div class="form-group">
                <label>Priority Severity</label>
                <select id="notcPriority" class="form-control">
                    <option value="normal">Normal Bulletin</option>
                    <option value="urgent">Urgent Commute Alert</option>
                    <option value="emergency">Emergency Security Bulletin</option>
                </select>
            </div>
            <button class="btn btn-accent" style="justify-content: center; padding: 12px; font-weight: 700;" onclick="submitNotice()">
                🚀 Broadcast Notice to Phones Now
            </button>
        </div>
    </div>

    <!-- CHANGE PASSWORD MODAL -->
    <div id="passModal" class="modal-overlay">
        <div class="modal">
            <div class="modal-header">
                <h3 style="font-size: 16px; font-weight: 800; color: var(--primary);">🔑 Update Admin Password</h3>
                <button onclick="closeModal('passModal')" style="background: none; border: none; font-size: 18px; cursor: pointer; color: #64748B;">✕</button>
            </div>
            <div class="form-group">
                <label>Admin Email</label>
                <input id="chgEmail" type="email" class="form-control" readonly>
            </div>
            <div class="form-group">
                <label>Current Password</label>
                <input id="chgOldPass" type="password" class="form-control" placeholder="Current password">
            </div>
            <div class="form-group">
                <label>New Password (min 6 characters)</label>
                <input id="chgNewPass" type="password" class="form-control" placeholder="Enter new strong password">
            </div>
            <button class="btn btn-primary" style="justify-content: center; padding: 12px; font-weight: 700;" onclick="submitPasswordChange()">
                Update Password
            </button>
        </div>
    </div>

    <!-- ADD ADMIN MODAL -->
    <div id="addAdminModal" class="modal-overlay">
        <div class="modal">
            <div class="modal-header">
                <h3 style="font-size: 16px; font-weight: 800; color: var(--primary);">➕ Add New Authority Administrator</h3>
                <button onclick="closeModal('addAdminModal')" style="background: none; border: none; font-size: 18px; cursor: pointer; color: #64748B;">✕</button>
            </div>
            <div class="form-group">
                <label>Full Official Name</label>
                <input id="newAdmName" type="text" class="form-control" placeholder="e.g. Prof. Transport Proctor">
            </div>
            <div class="form-group">
                <label>Official Email (@diu.edu.bd)</label>
                <input id="newAdmEmail" type="email" class="form-control" placeholder="e.g. proctor.transport@diu.edu.bd">
            </div>
            <div class="form-group">
                <label>Initial Temporary Password</label>
                <input id="newAdmPass" type="password" class="form-control" placeholder="Enter initial password">
            </div>
            <div class="form-group">
                <label>Privilege Role</label>
                <select id="newAdmRole" class="form-control">
                    <option value="admin">Transport Operations Admin</option>
                    <option value="proctor">Proctorial Security Officer</option>
                    <option value="superadmin">Super Administrator</option>
                </select>
            </div>
            <button class="btn btn-accent" style="justify-content: center; padding: 12px; font-weight: 700;" onclick="submitAddAdmin()">
                Create Administrator Account
            </button>
        </div>
    </div>

    <!-- TRIP DOSSIER INSPECTION MODAL -->
    <div id="tripModal" class="modal-overlay">
        <div class="modal" style="max-width: 640px;">
            <div class="modal-header">
                <h3 style="font-size: 16px; font-weight: 800; color: var(--primary);" id="tripModalTitle">🔍 Commute Ride Inspection</h3>
                <button onclick="closeModal('tripModal')" style="background: none; border: none; font-size: 18px; cursor: pointer; color: #64748B;">✕</button>
            </div>
            <div id="tripModalContent" style="display: flex; flex-direction: column; gap: 12px; font-size: 13px;">
                <!-- Filled dynamically -->
            </div>
        </div>
    </div>

    <!-- IMAGE LIGHTBOX MODAL -->
    <div id="imgModal" class="modal-overlay" onclick="closeModal('imgModal')">
        <div style="position: relative; text-align: center;">
            <img id="lightboxImg" src="" alt="Post image" onclick="event.stopPropagation()">
            <div style="color: white; margin-top: 10px; font-size: 12px;">Click anywhere outside to close</div>
        </div>
    </div>

    <script>
        let currentTab = 'dashboard';
        let loggedInAdmin = null;

        window.addEventListener('load', () => {
            const saved = localStorage.getItem('diu_admin_auth');
            if (saved) {
                try {
                    loggedInAdmin = JSON.parse(saved);
                    document.getElementById('loginGate').style.display = 'none';
                    initDashboard();
                } catch(e) {
                    localStorage.removeItem('diu_admin_auth');
                }
            }

            // Realtime clock
            setInterval(() => {
                const now = new Date();
                const clock = document.getElementById('clockDisplay');
                if (clock) clock.innerText = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
            }, 1000);

            // Auto-refresh stats every 15s
            setInterval(() => {
                if (loggedInAdmin) fetchStats();
            }, 15000);
        });

        async function doAdminLogin() {
            const email = document.getElementById('loginEmail').value.trim();
            const password = document.getElementById('loginPass').value;
            const err = document.getElementById('loginErr');
            err.style.display = 'none';

            if (!email || !password) {
                err.innerText = 'Please enter both email and password.';
                err.style.display = 'block';
                return;
            }

            try {
                const res = await fetch('/ride/api/admin/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email, password })
                });
                const data = await res.json();
                if (!res.ok) throw new Error(data.detail || 'Login failed');

                loggedInAdmin = data.admin;
                localStorage.setItem('diu_admin_auth', JSON.stringify(loggedInAdmin));
                document.getElementById('loginGate').style.display = 'none';
                initDashboard();
            } catch(e) {
                err.innerText = e.message;
                err.style.display = 'block';
            }
        }

        function doLogout() {
            localStorage.removeItem('diu_admin_auth');
            location.reload();
        }

        async function initDashboard() {
            await fetchStats();
            switchTab('dashboard');
        }

        async function fetchStats() {
            try {
                const res = await fetch('/ride/api/admin/stats');
                const d = await res.json();
                document.getElementById('kpiUsers').innerText = d.totalUsers || 0;
                document.getElementById('kpiDrivers').innerText = d.totalDrivers || 0;
                document.getElementById('kpiActiveRides').innerText = d.activeRides || 0;
                document.getElementById('kpiRequests').innerText = d.openRequests !== undefined ? d.openRequests : (d.totalRequests || 0);
                document.getElementById('kpiCompleted').innerText = d.completedRides || 0;
                document.getElementById('kpiFare').innerText = '৳' + Math.round(d.totalFareSum || 0);

                if (document.getElementById('sideBadgeRides')) document.getElementById('sideBadgeRides').innerText = d.activeRides || 0;
                if (document.getElementById('sideBadgeRequests')) document.getElementById('sideBadgeRequests').innerText = d.openRequests || d.totalRequests || 0;
                if (document.getElementById('sideBadgeFeed')) document.getElementById('sideBadgeFeed').innerText = d.totalFeedPosts || 0;
                if (document.getElementById('sideBadgeSos')) document.getElementById('sideBadgeSos').innerText = d.sosAlerts || 0;
            } catch(e) {}
        }

        function toggleMobileMenu() {
            const drawer = document.getElementById('mobileDrawer');
            if (drawer) drawer.classList.toggle('open');
        }

        function handleQuickExport(val) {
            if (!val) return;
            if (val === 'pdf') {
                window.open('/ride/api/admin/export/pdf', '_blank');
            } else {
                window.open(`/ride/api/admin/export/csv?type=${val}`, '_blank');
            }
        }

        function switchTab(tab) {
            currentTab = tab;
            document.querySelectorAll('.nav-tab').forEach(el => el.classList.remove('active'));
            const matchingTab = Array.from(document.querySelectorAll('.nav-tab')).find(el => el.getAttribute('onclick')?.includes(tab));
            if (matchingTab) {
                matchingTab.classList.add('active');
            }

            const picker = document.getElementById('mobileSectionPicker');
            if (picker && picker.value !== tab) picker.value = tab;

            const drawer = document.getElementById('mobileDrawer');
            if (drawer && drawer.classList.contains('open')) drawer.classList.remove('open');

            const container = document.getElementById('panelContent');
            container.innerHTML = '<div style="padding: 40px; text-align: center; color: var(--text-muted); font-weight: bold;">Loading realtime database records...</div>';

            if (tab === 'dashboard') renderDashboardTab(container);
  else if (tab === 'verifications') renderVerificationsTab(container);
            else if (tab === 'fleet_map') renderFleetMapTab(container);
            else if (tab === 'users') renderUsersTab(container, 'all');
            else if (tab === 'riders') renderUsersTab(container, 'driver');
            else if (tab === 'passengers') renderUsersTab(container, 'passenger');
            else if (tab === 'rides') renderRidesTab(container);
            else if (tab === 'requests') renderPassengerRequestsTab(container);
            else if (tab === 'feed') renderFeedTab(container);
            else if (tab === 'bookings') renderBookingsTab(container);
            else if (tab === 'completed') renderCompletedTab(container);
            else if (tab === 'sos') renderSosTab(container);
            else if (tab === 'notices') renderNoticesTab(container);
            else if (tab === 'admins') renderAdminsTab(container);
            else if (tab === 'ai_assistant') renderAiAssistantTab(container);
        }

        // =================================================================
        // Tab Renderers
        // =================================================================

        let leafletMapInstance = null;
        let fleetAutoRefreshInterval = null;
        let fleetMarkersLayer = null;

        
async function renderVerificationsTab(container) {
  container.innerHTML = `
    <div class="content-card">
      <div class="card-header" style="flex-wrap: wrap; gap: 10px;">
        <div>
          <h2 class="card-title">🎓 Student Verification & Credentials Database</h2>
          <p class="card-subtitle">Complete records of DIU students with verified IDs, credentials, emails, and phone numbers</p>
        </div>
        <div style="display: flex; gap: 8px; flex-wrap: wrap;">
          <input type="text" id="verifSearchInput" class="form-input" placeholder="Search by ID, name, email, phone..." style="width: 260px;" oninput="debounceVerifSearch()">
          <select id="verifStatusFilter" class="form-select" onchange="loadVerifications()" style="width: 140px;">
            <option value="all">All Status</option>
            <option value="verified">Verified Only</option>
            <option value="pending">Pending Only</option>
          </select>
          <button class="btn btn-primary" onclick="loadVerifications()">🔄 Refresh</button>
        </div>
      </div>
      <div id="verifTableContainer" style="overflow-x: auto; padding: 12px 16px;">
        <div style="text-align: center; padding: 30px; color: var(--text-muted);">Loading student records...</div>
      </div>
    </div>
  `;
  await loadVerifications();
}

let _verifSearchTimer = null;
function debounceVerifSearch() {
  clearTimeout(_verifSearchTimer);
  _verifSearchTimer = setTimeout(() => {
    loadVerifications();
  }, 300);
}

async function loadVerifications() {
  const tableCont = document.getElementById('verifTableContainer');
  if (!tableCont) return;
  const search = document.getElementById('verifSearchInput')?.value || '';
  const status = document.getElementById('verifStatusFilter')?.value || 'all';

  try {
    const res = await fetch(`/ride/api/admin/verifications?status=${encodeURIComponent(status)}&search=${encodeURIComponent(search)}`);
    const data = await res.json();
    const list = data.verifications || [];

    if (!list.length) {
      tableCont.innerHTML = `
        <div style="text-align: center; padding: 40px; color: var(--text-muted);">
          <div style="font-size: 32px; margin-bottom: 8px;">🎓</div>
          <div style="font-size: 15px; font-weight: 700; color: #E2E8F0;">No Student Records Found</div>
          <div style="font-size: 13px; margin-top: 4px;">App database is currently fresh at 0 registrations. New student signups will automatically appear here with full credentials.</div>
        </div>
      `;
      return;
    }

    let rowsHtml = '';
    list.forEach(v => {
      const isVerif = v.isVerified;
      const statusBadge = isVerif
        ? '<span class="badge badge-success" style="font-size: 11px;">✓ Verified</span>'
        : '<span class="badge badge-warning" style="font-size: 11px;">⏳ Pending</span>';

      const verifyBtn = !isVerif
        ? `<button class="btn btn-sm btn-primary" onclick="verifyStudent('${v.studentId}')" title="Approve Verification">✓ Verify</button>`
        : '<span style="color: #10B981; font-size: 12px; font-weight: bold;">Active</span>';

      rowsHtml += `
        <tr>
          <td style="font-weight: 700; color: #F8FAFC;">${v.studentId}</td>
          <td style="font-weight: 600; color: #E2E8F0;">${v.fullName}</td>
          <td>
            <div style="font-size: 12.5px; color: #94A3B8;">${v.email}</div>
            <div style="font-size: 11.5px; color: #64748B;">${v.phone || 'No phone'}</div>
          </td>
          <td><span class="badge" style="background: rgba(59, 130, 246, 0.15); color: #60A5FA;">${v.department}</span> ${v.batch ? `<span style="font-size: 11px; color: #94A3B8;">(${v.batch})</span>` : ''}</td>
          <td>
            <div style="display: flex; align-items: center; gap: 6px;">
              <code style="background: #1E293B; color: #38BDF8; padding: 2px 6px; border-radius: 4px; font-size: 11.5px; font-family: monospace;">${v.password || '••••••••'}</code>
            </div>
          </td>
          <td>${statusBadge}</td>
          <td style="font-size: 11px; color: #64748B;">${v.verificationMethod}</td>
          <td style="font-size: 11px; color: #94A3B8;">${v.createdAt ? v.createdAt.substring(0, 16).replace('T', ' ') : '-'}</td>
          <td>
            <div style="display: flex; gap: 6px;">
              ${verifyBtn}
              <button class="btn btn-sm btn-danger" onclick="deleteStudentVerif('${v.id}')" title="Delete Account">🗑️</button>
            </div>
          </td>
        </tr>
      `;
    });

    tableCont.innerHTML = `
      <table class="data-table" style="width: 100%; border-collapse: collapse;">
        <thead>
          <tr style="border-bottom: 1px solid var(--sidebar-border); text-align: left; color: #94A3B8; font-size: 12px;">
            <th style="padding: 10px 8px;">Student ID</th>
            <th style="padding: 10px 8px;">Name</th>
            <th style="padding: 10px 8px;">Email & Phone</th>
            <th style="padding: 10px 8px;">Dept / Batch</th>
            <th style="padding: 10px 8px;">Password</th>
            <th style="padding: 10px 8px;">Status</th>
            <th style="padding: 10px 8px;">Method</th>
            <th style="padding: 10px 8px;">Registered At</th>
            <th style="padding: 10px 8px;">Action</th>
          </tr>
        </thead>
        <tbody style="font-size: 13px;">
          ${rowsHtml}
        </tbody>
      </table>
    `;
  } catch (err) {
    tableCont.innerHTML = `<div style="text-align: center; color: #EF4444; padding: 30px;">Error loading verifications: ${err.message}</div>`;
  }
}

async function verifyStudent(studentId) {
  if (!confirm(`Are you sure you want to verify student "${studentId}"?`)) return;
  try {
    const res = await fetch(`/ride/api/admin/verifications/${encodeURIComponent(studentId)}/verify`, { method: 'POST' });
    const data = await res.json();
    if (res.ok) {
      alert(data.message || 'Student verified successfully!');
      loadVerifications();
    } else {
      alert('Failed to verify: ' + (data.detail || data.message));
    }
  } catch (e) {
    alert('Error: ' + e.message);
  }
}

async function deleteStudentVerif(id) {
  if (!confirm('Are you sure you want to completely remove this student account and credentials from the system?')) return;
  try {
    const res = await fetch(`/ride/api/admin/verifications/${encodeURIComponent(id)}`, { method: 'DELETE' });
    const data = await res.json();
    if (res.ok) {
      alert('Student account removed.');
      loadVerifications();
    } else {
      alert('Failed: ' + (data.detail || data.message));
    }
  } catch (e) {
    alert('Error: ' + e.message);
  }
}

async function renderFleetMapTab(container) {
            if (fleetAutoRefreshInterval) {
                clearInterval(fleetAutoRefreshInterval);
                fleetAutoRefreshInterval = null;
            }

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header" style="flex-wrap: wrap; gap: 10px;">
                        <div style="display: flex; align-items: center; gap: 10px;">
                            <div class="card-title">🗺️ Live Commute Fleet Radar & Route Map</div>
                            <span class="pill pill-green">● REALTIME ACTIVE</span>
                        </div>
                        <div class="toolbar">
                            <select id="mapCorridorFilter" class="search-input" onchange="loadFleetMapData()">
                                <option value="all">🌐 All Commute Corridors</option>
                                <option value="ashulia">Ashulia Highway Corridor</option>
                                <option value="uttara">Uttara Corridor</option>
                                <option value="mirpur">Mirpur-10 Corridor</option>
                                <option value="dhanmondi">Dhanmondi Corridor</option>
                                <option value="savar">Savar / Nabinagar</option>
                            </select>
                            <button class="btn btn-secondary" onclick="loadFleetMapData()">🔄 Refresh Map</button>
                            <button class="btn btn-accent" onclick="recenterFleetMap()">🎯 Center Campus</button>
                        </div>
                    </div>
                    <div style="position: relative;">
                        <div id="fleetMap" style="height: 540px; width: 100%; background: #E2E8F0;"></div>
                    </div>
                </div>
            `;

            setTimeout(() => { initFleetLeafletMap(); }, 100);
        }

        function initFleetLeafletMap() {
            const mapEl = document.getElementById('fleetMap');
            if (!mapEl) return;

            if (leafletMapInstance) {
                try { leafletMapInstance.remove(); } catch(e) {}
                leafletMapInstance = null;
            }

            const diuCampus = [23.8769, 90.3203];
            leafletMapInstance = L.map('fleetMap').setView(diuCampus, 13);

            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                maxZoom: 19,
                attribution: '© OpenStreetMap | DIU Transport Cell'
            }).addTo(leafletMapInstance);

            const campusMarker = L.circleMarker(diuCampus, {
                radius: 12, fillColor: '#10B981', color: '#FFFFFF', weight: 3, opacity: 1, fillOpacity: 0.95
            }).addTo(leafletMapInstance);
            campusMarker.bindPopup('<b>🏛️ Daffodil Smart City (Main Campus)</b><br>Ashulia, Dhaka');

            fleetMarkersLayer = L.layerGroup().addTo(leafletMapInstance);
            loadFleetMapData();
        }

        function recenterFleetMap() {
            if (leafletMapInstance) leafletMapInstance.setView([23.8769, 90.3203], 13);
        }

        async function loadFleetMapData() {
            if (!leafletMapInstance || !fleetMarkersLayer) return;
            fleetMarkersLayer.clearLayers();

            try {
                const res = await fetch('/ride/api/admin/rides?status=active');
                const rides = await res.json();

                rides.forEach(r => {
                    const lat = r.destinationLat || 23.8769;
                    const lng = r.destinationLng || 90.3203;
                    const marker = L.marker([lat, lng]).addTo(fleetMarkersLayer);
                    marker.bindPopup(`
                        <div style="font-size: 12px; line-height: 1.5;">
                            <b>🏍️ ${r.driverName}</b> (${r.driverDept})<br>
                            <b>Route:</b> ${r.originName} ➔ ${r.destinationName}<br>
                            <b>Fare:</b> ৳${r.farePerSeat} | <b>Seats:</b> ${r.availableSeats}/${r.totalSeats}<br>
                            <button class="btn btn-primary btn-sm" style="margin-top:6px;" onclick="inspectTripDetails('${r.id}', false)">Inspect Dossier</button>
                        </div>
                    `);
                });
            } catch(e) {}
        }

        async function renderDashboardTab(container) {
            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">🛡️ University Transport Operations Overview</div>
                        <div class="toolbar">
                            <button class="btn btn-accent" onclick="window.open('/ride/api/admin/export/pdf', '_blank')">🖨️ Official PDF Report</button>
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=all', '_blank')">📥 Download All CSV</button>
                        </div>
                    </div>
                    <div style="padding: 24px; display: flex; flex-direction: column; gap: 20px;">
                        <div style="background: linear-gradient(135deg, #ECFDF5 0%, #D1FAE5 100%); border: 1.5px solid #86EFAC; border-radius: var(--radius-md); padding: 20px; color: #065F46; font-size: 13.5px; line-height: 1.6; display: flex; align-items: flex-start; gap: 14px;">
                            <div style="font-size: 28px; line-height: 1;">🏛️</div>
                            <div>
                                <div style="font-weight: 800; font-size: 15px; margin-bottom: 4px; color: #047857;">Transport Operations Console Active</div>
                                <div>Welcome back, <strong>${loggedInAdmin?.name || 'Varsity Authority'}</strong> (${loggedInAdmin?.email || '252-15-234@diu.edu.bd'}). From this centralized portal, varsity proctorial desk officers and transport administrators audit live peer carpools, monitor student driver verification, audit GPS transit dossiers, moderate campus announcements, and supervise the AI assistant.</div>
                            </div>
                        </div>

                        <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px;">
                            <div style="border: 1px solid var(--border); border-radius: var(--radius-md); padding: 18px; background: white; display: flex; flex-direction: column; justify-content: space-between; box-shadow: var(--shadow-sm);">
                                <div>
                                    <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
                                        <h4 style="font-size: 14px; font-weight: 800; color: #059669;">🗺️ Fleet Radar & Spatial Map</h4>
                                        <span class="pill pill-green">Live GPS</span>
                                    </div>
                                    <p style="font-size: 12.5px; color: var(--text-muted); line-height: 1.5;">Interactive campus spatial map displaying active motorbike routes, passenger pickups, and Ashulia/Mirpur corridors.</p>
                                </div>
                                <button class="btn btn-primary" style="margin-top: 14px; width: 100%; justify-content: center;" onclick="switchTab('fleet_map')">Open Fleet Radar ➔</button>
                            </div>
                            <div style="border: 1px solid var(--border); border-radius: var(--radius-md); padding: 18px; background: white; display: flex; flex-direction: column; justify-content: space-between; box-shadow: var(--shadow-sm);">
                                <div>
                                    <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
                                        <h4 style="font-size: 14px; font-weight: 800; color: #7C3AED;">🙋‍♂️ Student Requests Board</h4>
                                        <span class="pill pill-purple">Open Needs</span>
                                    </div>
                                    <p style="font-size: 12.5px; color: var(--text-muted); line-height: 1.5;">Inspect students seeking ride seats from campus, offered fuel shares, and pending driver matches.</p>
                                </div>
                                <button class="btn btn-secondary" style="margin-top: 14px; width: 100%; justify-content: center;" onclick="switchTab('requests')">View Requests Board ➔</button>
                            </div>
                            <div style="border: 1px solid var(--border); border-radius: var(--radius-md); padding: 18px; background: white; display: flex; flex-direction: column; justify-content: space-between; box-shadow: var(--shadow-sm);">
                                <div>
                                    <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
                                        <h4 style="font-size: 14px; font-weight: 800; color: #EA580C;">📰 Campus Feed Moderation</h4>
                                        <span class="pill pill-amber">Bulletin</span>
                                    </div>
                                    <p style="font-size: 12.5px; color: var(--text-muted); line-height: 1.5;">Audit public student commute and campus news posts, inspect uploaded images, and keep community respectful.</p>
                                </div>
                                <button class="btn btn-secondary" style="margin-top: 14px; width: 100%; justify-content: center;" onclick="switchTab('feed')">Moderate Feed ➔</button>
                            </div>
                        </div>
                    </div>
                </div>
            `;
        }

        async function renderUsersTab(container, roleFilter) {
            const res = await fetch(`/ride/api/admin/users${roleFilter !== 'all' ? '?role=' + roleFilter : ''}`);
            const users = await res.json();

            const title = roleFilter === 'driver' ? '🏍️ Verified Motorbike Riders (Bikers)' : (roleFilter === 'passenger' ? '🎒 Registered Passengers' : '👥 All Registered Students');
            const csvType = roleFilter === 'driver' ? 'riders' : (roleFilter === 'passenger' ? 'passengers' : 'users');

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">${title} <span class="pill pill-blue">${users.length} Commuters</span></div>
                        <div class="toolbar">
                            <input type="text" class="search-input" placeholder="Search by name, ID, or dept..." oninput="filterTableRows(this.value)">
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=${csvType}', '_blank')">📥 Export CSV</button>
                            <button class="btn btn-accent" onclick="window.open('/ride/api/admin/export/pdf', '_blank')">🖨️ Print PDF</button>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Student ID</th>
                                    <th>Student Name</th>
                                    <th>Dept</th>
                                    <th>Email</th>
                                    <th>Phone</th>
                                    <th>Role</th>
                                    <th>Rating</th>
                                    <th>Biker Rides</th>
                                    <th>Passenger Rides</th>
                                    <th>Vehicle Info</th>
                                    <th>Verification</th>
                                    <th>Action</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${users.map(u => `
                                    <tr id="userRow_${u.id}">
                                        <td style="font-weight: 700; font-family: 'JetBrains Mono', monospace; font-size: 11.5px; color: #1E293B;">${u.studentId}</td>
                                        <td>
                                            <div style="font-weight: 700; color: #0F172A;">${u.name}</div>
                                            <div style="font-size: 11px; color: #64748B;">${u.batch ? 'Batch ' + u.batch : 'DIU Student'}</div>
                                        </td>
                                        <td><span class="pill pill-blue">${u.department}</span></td>
                                        <td style="font-size: 11.5px; color: #475569;">${u.email}</td>
                                        <td style="font-family: 'JetBrains Mono', monospace; font-size: 11.5px;">${u.phone || '—'}</td>
                                        <td>${u.isDriverRegistered ? '<span class="pill pill-green">Biker</span>' : '<span class="pill pill-amber">Passenger</span>'}</td>
                                        <td style="font-weight: 700; color: #D97706;">⭐ ${u.rating.toFixed(2)}</td>
                                        <td style="text-align: center; font-weight: bold;">${u.totalRidesAsDriver}</td>
                                        <td style="text-align: center; font-weight: bold;">${u.totalRidesAsPassenger}</td>
                                        <td style="font-size: 11.5px;">${u.vehicleInfo || '—'}</td>
                                        <td>
                                            <button class="btn btn-sm ${u.isVerified ? 'btn-primary' : 'btn-secondary'}" onclick="toggleUserVerify('${u.id}')">
                                                ${u.isVerified ? '✓ Verified' : '⚪ Verify'}
                                            </button>
                                        </td>
                                        <td>
                                            <button class="btn btn-danger btn-sm" onclick="deleteUserAccount('${u.id}', '${u.name}')" title="Delete Account">🗑️</button>
                                        </td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        async function toggleUserVerify(userId) {
            try {
                const res = await fetch(`/ride/api/admin/users/${userId}/toggle-verify`, { method: 'POST' });
                const d = await res.json();
                if (!res.ok) throw new Error(d.detail || 'Failed to toggle verification');
                switchTab(currentTab);
            } catch(e) {
                alert('Error: ' + e.message);
            }
        }

        async function deleteUserAccount(userId, name) {
            if (!confirm(`Are you sure you want to permanently delete user account: ${name}? All associated rides and requests will also be removed.`)) return;
            try {
                const res = await fetch(`/ride/api/admin/users/${userId}`, { method: 'DELETE' });
                const d = await res.json();
                if (!res.ok) throw new Error(d.detail || 'Failed to delete');
                alert(d.message);
                switchTab(currentTab);
            } catch(e) {
                alert('Error: ' + e.message);
            }
        }

        async function renderRidesTab(container) {
            const res = await fetch('/ride/api/admin/rides');
            const rides = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">🛣️ Motorbike Rides & Corridors <span class="pill pill-blue">${rides.length} Listed</span></div>
                        <div class="toolbar">
                            <button class="btn btn-primary" onclick="switchTab('fleet_map')">🗺️ Radar Map</button>
                            <input type="text" class="search-input" placeholder="Search driver, corridor, origin..." oninput="filterTableRows(this.value)">
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=rides', '_blank')">📥 Export CSV</button>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Ride ID</th>
                                    <th>Driver / Biker</th>
                                    <th>Route</th>
                                    <th>Departure</th>
                                    <th>Fare</th>
                                    <th>Seats</th>
                                    <th>Status</th>
                                    <th>Vehicle</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${rides.map(r => `
                                    <tr>
                                        <td style="font-family: 'JetBrains Mono', monospace; font-size: 11px; color: #475569;">${r.id.slice(0, 10)}...</td>
                                        <td>
                                            <div style="font-weight: 700; color: #0F172A;">${r.driverName}</div>
                                            <div style="font-size: 11px; color: #64748B;">${r.driverDept} • ${r.driverPhone || ''}</div>
                                        </td>
                                        <td>
                                            <div style="font-weight: 700; color: #1E293B;">${r.originName} ➔ ${r.destinationName}</div>
                                            ${r.waypointName ? `<div style="font-size: 11px; color: #64748B;">Via: ${r.waypointName}</div>` : ''}
                                        </td>
                                        <td style="font-family: 'JetBrains Mono', monospace; font-size: 11.5px;">${r.departureTime ? r.departureTime.slice(11, 16) : '—'}</td>
                                        <td style="font-weight: 800; color: #059669; font-size: 13.5px;">৳${r.farePerSeat.toFixed(0)}</td>
                                        <td style="text-align: center; font-weight: bold;">${r.availableSeats}/${r.totalSeats}</td>
                                        <td>
                                            <span class="pill ${r.status === 'active' ? 'pill-green' : (r.status === 'completed' ? 'pill-blue' : (r.status === 'cancelled' ? 'pill-red' : 'pill-amber'))}">
                                                ${r.status.toUpperCase()}
                                            </span>
                                        </td>
                                        <td style="font-size: 11.5px;">${r.vehicleModel} <span style="color: #64748B;">(${r.vehiclePlate || '—'})</span></td>
                                        <td>
                                            <div style="display: flex; gap: 4px;">
                                                <button class="btn btn-secondary btn-sm" onclick="inspectTripDetails('${r.id}', false)">🔍 View</button>
                                                <a href="/ride/api/rides/${r.id}/route-passport-pdf" target="_blank" class="btn btn-accent btn-sm" style="text-decoration: none;">📄 PDF</a>
                                                ${r.status === 'active' ? `<button class="btn btn-danger btn-sm" onclick="cancelRideByAdmin('${r.id}')">Cancel</button>` : ''}
                                            </div>
                                        </td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        async function cancelRideByAdmin(rideId) {
            if (!confirm(`Cancel active ride ${rideId}? Bookings will be notified.`)) return;
            try {
                const res = await fetch(`/ride/api/admin/rides/${rideId}/cancel`, { method: 'POST' });
                const d = await res.json();
                if (!res.ok) throw new Error(d.detail || 'Failed');
                alert(d.message);
                switchTab('rides');
            } catch(e) {
                alert('Error: ' + e.message);
            }
        }

        // =================================================================
        // Student Ride Requests Board
        // =================================================================
        async function renderPassengerRequestsTab(container) {
            const res = await fetch('/ride/api/admin/passenger-requests');
            const reqs = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">🙋‍♂️ Student Ride Requests Board <span class="pill pill-purple">${reqs.length} Open</span></div>
                        <div class="toolbar">
                            <input type="text" class="search-input" placeholder="Search student, pickup, destination..." oninput="filterTableRows(this.value)">
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=requests', '_blank')">📥 Export CSV</button>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Request ID</th>
                                    <th>Student</th>
                                    <th>Dept</th>
                                    <th>Phone</th>
                                    <th>Commute Route</th>
                                    <th>Requested Time</th>
                                    <th>Offered Fare</th>
                                    <th>Notes</th>
                                    <th>Status</th>
                                    <th>Action</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${reqs.map(q => `
                                    <tr>
                                        <td style="font-family: 'JetBrains Mono', monospace; font-size: 11px; color: #475569;">${q.id.slice(0, 10)}...</td>
                                        <td style="font-weight: 700; color: #0F172A;">${q.passengerName}</td>
                                        <td><span class="pill pill-blue">${q.passengerDept}</span></td>
                                        <td style="font-family: 'JetBrains Mono', monospace; font-size: 11.5px;">${q.passengerPhone || '—'}</td>
                                        <td style="font-weight: 700; color: #1E293B;">${q.pickup} ➔ ${q.dropoff}</td>
                                        <td style="font-size: 11.5px;">${q.requestedTime || '—'}</td>
                                        <td style="font-weight: 800; color: #7C3AED; font-size: 13.5px;">৳${q.proposedFare.toFixed(0)}</td>
                                        <td style="font-size: 11.5px; color: var(--text-muted); max-width: 200px;">${q.notes || '—'}</td>
                                        <td>
                                            <span class="pill ${q.status === 'open' ? 'pill-green' : (q.status === 'accepted' ? 'pill-blue' : 'pill-amber')}">
                                                ${q.status.toUpperCase()}
                                            </span>
                                        </td>
                                        <td>
                                            <button class="btn btn-danger btn-sm" onclick="deletePassengerRequest('${q.id}')">🗑️ Remove</button>
                                        </td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        async function deletePassengerRequest(reqId) {
            if (!confirm(`Delete student commute request ${reqId}?`)) return;
            try {
                const res = await fetch(`/ride/api/admin/passenger-requests/${reqId}`, { method: 'DELETE' });
                const d = await res.json();
                if (!res.ok) throw new Error(d.detail || 'Failed');
                switchTab('requests');
            } catch(e) {
                alert('Error: ' + e.message);
            }
        }

        // =================================================================
        // Campus News Feed Moderation
        // =================================================================
        async function renderFeedTab(container) {
            const res = await fetch('/ride/api/admin/feed');
            const posts = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">📰 Campus News Feed Moderation <span class="pill pill-amber">${posts.length} Posts</span></div>
                        <div class="toolbar">
                            <input type="text" class="search-input" placeholder="Search author or post text..." oninput="filterFeedPosts(this.value)">
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=feed', '_blank')">📥 Export CSV</button>
                        </div>
                    </div>
                    <div class="feed-grid" id="feedPostsContainer">
                        ${posts.map(p => `
                            <div class="feed-card" data-search="${(p.authorName + ' ' + p.content + ' ' + p.category).toLowerCase()}">
                                <div class="feed-header">
                                    <div class="feed-author">
                                        <div class="feed-avatar">${p.authorName.charAt(0)}</div>
                                        <div>
                                            <div style="font-weight: 800; font-size: 13.5px; color: #0F172A;">${p.authorName} <span class="pill pill-blue">${p.authorDept}</span></div>
                                            <div style="font-size: 11px; color: var(--text-muted);">${p.authorStudentId || 'DIU Student'} • ${p.createdAt ? p.createdAt.slice(0, 16).replace('T', ' ') : ''}</div>
                                        </div>
                                    </div>
                                    <div style="display: flex; align-items: center; gap: 8px;">
                                        <span class="pill pill-purple">${p.category}</span>
                                        <button class="btn btn-danger btn-sm" onclick="deleteFeedPost('${p.id}')">🗑️ Delete Post</button>
                                    </div>
                                </div>
                                <div style="font-size: 13.5px; color: #1E293B; line-height: 1.5; white-space: pre-wrap;">${p.content}</div>
                                ${p.imageUrl ? `
                                    <div>
                                        <img src="${p.imageUrl}" class="feed-img-thumb" alt="Post attached image" onclick="openLightbox('${p.imageUrl}')">
                                        <div style="font-size: 10.5px; color: var(--text-muted); margin-top: 3px;">(Click image to expand)</div>
                                    </div>
                                ` : ''}
                                <div style="font-size: 12px; color: var(--text-muted); display: flex; gap: 16px; padding-top: 8px; border-top: 1px solid #F1F5F9;">
                                    <span>❤️ <strong>${p.likesCount}</strong> Likes</span>
                                    <span>💬 <strong>${p.commentsCount}</strong> Comments</span>
                                    <span style="font-family: 'JetBrains Mono', monospace; font-size: 11px;">ID: ${p.id.slice(0, 12)}</span>
                                </div>
                            </div>
                        `).join('')}
                    </div>
                </div>
            `;
        }

        function filterFeedPosts(query) {
            const q = query.toLowerCase().trim();
            document.querySelectorAll('.feed-card').forEach(el => {
                const text = el.getAttribute('data-search') || '';
                el.style.display = text.includes(q) ? '' : 'none';
            });
        }

        async function deleteFeedPost(postId) {
            if (!confirm(`Are you sure you want to remove this post from the campus feed?`)) return;
            try {
                const res = await fetch(`/ride/api/admin/feed/${postId}`, { method: 'DELETE' });
                const d = await res.json();
                if (!res.ok) throw new Error(d.detail || 'Failed');
                alert(d.message);
                switchTab('feed');
            } catch(e) {
                alert('Error: ' + e.message);
            }
        }

        function openLightbox(url) {
            document.getElementById('lightboxImg').src = url;
            document.getElementById('imgModal').style.display = 'flex';
        }

        async function renderBookingsTab(container) {
            const res = await fetch('/ride/api/admin/bookings');
            const bookings = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">📑 Passenger Booking Orders <span class="pill pill-blue">${bookings.length} Orders</span></div>
                        <div class="toolbar">
                            <input type="text" class="search-input" placeholder="Search passenger or pickup..." oninput="filterTableRows(this.value)">
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=bookings', '_blank')">📥 Export CSV</button>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Booking ID</th>
                                    <th>Passenger</th>
                                    <th>Phone</th>
                                    <th>Pickup Point</th>
                                    <th>Drop-off Point</th>
                                    <th>Seats</th>
                                    <th>Total Fare</th>
                                    <th>Status</th>
                                    <th>Requested At</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${bookings.map(b => `
                                    <tr>
                                        <td style="font-family: 'JetBrains Mono', monospace; font-size: 11px; color: #475569;">${b.id.slice(0, 12)}</td>
                                        <td style="font-weight: 700; color: #0F172A;">${b.passengerName}</td>
                                        <td style="font-family: 'JetBrains Mono', monospace; font-size: 11.5px;">${b.passengerPhone || '—'}</td>
                                        <td style="font-weight: 600;">${b.pickupPoint}</td>
                                        <td style="font-weight: 600;">${b.dropoffPoint}</td>
                                        <td style="text-align: center; font-weight: bold;">${b.seatsBooked}</td>
                                        <td style="font-weight: 800; color: #059669; font-size: 13.5px;">৳${b.totalFare.toFixed(0)}</td>
                                        <td>
                                            <span class="pill ${b.status === 'accepted' ? 'pill-green' : (b.status === 'completed' ? 'pill-blue' : (b.status === 'cancelled' ? 'pill-red' : 'pill-amber'))}">
                                                ${b.status.toUpperCase()}
                                            </span>
                                        </td>
                                        <td style="font-size: 11px; color: #64748B;">${b.requestedAt ? b.requestedAt.slice(0, 16).replace('T', ' ') : '—'}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        let allCompletedTrips = [];

        async function renderCompletedTab(container) {
            const res = await fetch('/ride/api/admin/completed-rides');
            allCompletedTrips = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header" style="flex-wrap: wrap; gap: 12px;">
                        <div>
                            <div class="card-title" style="display: flex; align-items: center; gap: 8px;">
                                <span>🎓 Daffodil Varsity Community Completed Rides</span>
                                <span class="pill pill-green" id="tripCountBadge">${allCompletedTrips.length} Rides Logged</span>
                            </div>
                            <p style="font-size: 12px; color: var(--text-muted); margin-top: 2px;">
                                Comprehensive safety records: Student IDs, Departments, Contact numbers, Google Maps Route links & campus verification notes.
                            </p>
                        </div>
                        <div class="toolbar" style="gap: 8px;">
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=completed', '_blank')">📥 Official CSV Audit</button>
                            <button class="btn btn-accent" onclick="window.open('/ride/api/admin/export/pdf?type=completed', '_blank')">🖨️ Printable PDF Audit</button>
                        </div>
                    </div>

                    <!-- Varsity Filter & Real-Time Search Bar -->
                    <div style="background: #F8FAFC; border: 1px solid var(--border); border-radius: var(--radius-md); padding: 12px 16px; margin: 12px 16px 16px 16px; display: flex; flex-wrap: wrap; gap: 12px; align-items: center;">
                        <div style="flex: 2; min-width: 260px;">
                            <input type="text" id="completedSearchInput" placeholder="🔍 Search by Student ID, Commuter Name, Phone, or Corridor..." 
                                   oninput="filterCompletedTripsTable()"
                                   style="width: 100%; padding: 8px 12px; border-radius: 8px; border: 1.5px solid var(--border); font-size: 12px; outline: none; background: #fff;" />
                        </div>
                        <div style="flex: 1; min-width: 160px;">
                            <select id="completedDeptFilter" onchange="filterCompletedTripsTable()" style="width: 100%; padding: 8px 10px; border-radius: 8px; border: 1.5px solid var(--border); font-size: 12px; background: #fff; cursor: pointer;">
                                <option value="">🏛️ All Departments</option>
                                <option value="CSE">CSE (Computer Science)</option>
                                <option value="SWE">SWE (Software Eng)</option>
                                <option value="EEE">EEE (Electrical)</option>
                                <option value="CIS">CIS (Computing)</option>
                                <option value="BBA">BBA (Business)</option>
                                <option value="English">English</option>
                                <option value="Pharmacy">Pharmacy</option>
                                <option value="Textile">Textile</option>
                            </select>
                        </div>
                        <div style="flex: 1; min-width: 160px;">
                            <select id="completedCorridorFilter" onchange="filterCompletedTripsTable()" style="width: 100%; padding: 8px 10px; border-radius: 8px; border: 1.5px solid var(--border); font-size: 12px; background: #fff; cursor: pointer;">
                                <option value="">🛣️ All Campus Corridors</option>
                                <option value="Ashulia">DIU Ashulia Campus</option>
                                <option value="Mirpur">Mirpur 10 / 1</option>
                                <option value="Uttara">Uttara North / House Building</option>
                                <option value="Dhanmondi">Dhanmondi 27 / Sobhanbag</option>
                            </select>
                        </div>
                    </div>

                    <div class="table-responsive">
                        <table class="data-table" id="completedTripsTable">
                            <thead>
                                <tr>
                                    <th>Trip & Time</th>
                                    <th>Biker (Varsity)</th>
                                    <th>Passenger (Varsity)</th>
                                    <th>Campus Corridor</th>
                                    <th>Route Directions</th>
                                    <th>Fare & Dur.</th>
                                    <th>Varsity Status</th>
                                    <th>Dossier</th>
                                </tr>
                            </thead>
                            <tbody id="completedTripsTbody">
                                ${generateCompletedRows(allCompletedTrips)}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        function generateCompletedRows(trips) {
            if (!trips || trips.length === 0) {
                return `<tr><td colspan="8" style="text-align: center; padding: 28px; color: var(--text-muted);">No completed rides match your varsity search filters.</td></tr>`;
            }
            return trips.map(t => {
                const routeLink = t.routeMapsLink || `https://www.google.com/maps/dir/?api=1&origin=${encodeURIComponent(t.originName)}&destination=${encodeURIComponent(t.destinationName)}`;
                const timeStr = t.completedTime ? t.completedTime.slice(0, 16).replace('T', ' ') : '—';
                return `
                    <tr>
                        <td>
                            <div style="font-family: 'JetBrains Mono', monospace; font-size: 11px; font-weight: 700; color: #1E293B;">#${t.id.slice(0, 8)}</div>
                            <div style="font-size: 10.5px; color: var(--text-muted);">${timeStr}</div>
                        </td>
                        <td>
                            <div style="font-weight: 800; font-size: 12.5px; color: #0F172A;">${t.driverName}</div>
                            <div style="display: flex; gap: 4px; align-items: center; margin-top: 2px;">
                                <span class="pill pill-blue" style="font-size: 9.5px; padding: 2px 6px;">🆔 ${t.driverStudentId || 'Verified'}</span>
                                <span style="font-size: 10.5px; font-weight: 600; color: #475569;">${t.driverDept}</span>
                            </div>
                            <div style="font-size: 10.5px; color: #64748B; margin-top: 1px; font-family: 'JetBrains Mono', monospace;">📞 ${t.driverPhone}</div>
                        </td>
                        <td>
                            <div style="font-weight: 800; font-size: 12.5px; color: #0F172A;">${t.passengerName || 'Student Commuter'}</div>
                            <div style="display: flex; gap: 4px; align-items: center; margin-top: 2px;">
                                <span class="pill pill-green" style="font-size: 9.5px; padding: 2px 6px;">🆔 ${t.passengerStudentId || 'Verified'}</span>
                                <span style="font-size: 10.5px; font-weight: 600; color: #475569;">${t.passengerDept}</span>
                            </div>
                            <div style="font-size: 10.5px; color: #64748B; margin-top: 1px; font-family: 'JetBrains Mono', monospace;">📞 ${t.passengerPhone}</div>
                        </td>
                        <td>
                            <div style="font-weight: 700; font-size: 12px; color: #0F172A;">${t.originName} ➔ ${t.destinationName}</div>
                            <div style="font-size: 10.5px; color: var(--text-muted); margin-top: 2px;">⏱️ ${t.durationMinutes.toFixed(0)} mins transit</div>
                        </td>
                        <td>
                            <div style="display: flex; gap: 4px; align-items: center;">
                                <a href="${routeLink}" target="_blank" 
                                   style="display: inline-flex; align-items: center; gap: 3px; background: #EFF6FF; border: 1px solid #BFDBFE; color: #1D4ED8; font-size: 11px; font-weight: 700; padding: 4px 8px; border-radius: 6px; text-decoration: none; transition: all 0.2s;"
                                   onmouseover="this.style.background='#DBEAFE'" onmouseout="this.style.background='#EFF6FF'">
                                    🗺️ Map
                                </a>
                                <a href="/ride/api/rides/${t.id}/route-passport-pdf" target="_blank" 
                                   style="display: inline-flex; align-items: center; gap: 3px; background: #FEF3C7; border: 1px solid #FDE68A; color: #B45309; font-size: 11px; font-weight: 700; padding: 4px 8px; border-radius: 6px; text-decoration: none; transition: all 0.2s;"
                                   onmouseover="this.style.background='#FDE68A'" onmouseout="this.style.background='#FEF3C7'">
                                    📄 PDF
                                </a>
                            </div>
                        </td>
                        <td>
                            <div style="font-weight: 800; color: #059669; font-size: 13.5px;">৳${t.fare.toFixed(0)}</div>
                            <div style="font-size: 10.5px; color: #D97706;">⭐ ${t.rating || '5.0'}</div>
                        </td>
                        <td>
                            <span class="pill pill-green" style="font-size: 10px; font-weight: 700;">✓ DIU Safe Peer</span>
                        </td>
                        <td>
                            <button class="btn btn-secondary btn-sm" onclick="inspectTripDetails('${t.id}', true)" style="font-size: 11px; padding: 4px 8px;">🔍 Dossier</button>
                        </td>
                    </tr>
                `;
            }).join('');
        }

        function filterCompletedTripsTable() {
            const query = (document.getElementById('completedSearchInput')?.value || '').toLowerCase().trim();
            const dept = (document.getElementById('completedDeptFilter')?.value || '').toLowerCase().trim();
            const corridor = (document.getElementById('completedCorridorFilter')?.value || '').toLowerCase().trim();

            const filtered = allCompletedTrips.filter(t => {
                const searchMatch = !query || 
                    (t.driverName && t.driverName.toLowerCase().includes(query)) ||
                    (t.driverStudentId && t.driverStudentId.toLowerCase().includes(query)) ||
                    (t.driverPhone && t.driverPhone.toLowerCase().includes(query)) ||
                    (t.passengerName && t.passengerName.toLowerCase().includes(query)) ||
                    (t.passengerStudentId && t.passengerStudentId.toLowerCase().includes(query)) ||
                    (t.passengerPhone && t.passengerPhone.toLowerCase().includes(query)) ||
                    (t.originName && t.originName.toLowerCase().includes(query)) ||
                    (t.destinationName && t.destinationName.toLowerCase().includes(query)) ||
                    (t.id && t.id.toLowerCase().includes(query));

                const deptMatch = !dept ||
                    (t.driverDept && t.driverDept.toLowerCase().includes(dept)) ||
                    (t.passengerDept && t.passengerDept.toLowerCase().includes(dept));

                const corridorMatch = !corridor ||
                    (t.originName && t.originName.toLowerCase().includes(corridor)) ||
                    (t.destinationName && t.destinationName.toLowerCase().includes(corridor));

                return searchMatch && deptMatch && corridorMatch;
            });

            const tbody = document.getElementById('completedTripsTbody');
            if (tbody) {
                tbody.innerHTML = generateCompletedRows(filtered);
            }
            const countBadge = document.getElementById('tripCountBadge');
            if (countBadge) {
                countBadge.innerText = `${filtered.length} of ${allCompletedTrips.length} Rides`;
            }
        }

        async function inspectTripDetails(tripOrRideId, isCompleted) {
            const modal = document.getElementById('tripModal');
            const content = document.getElementById('tripModalContent');
            modal.style.display = 'flex';
            content.innerHTML = '<div style="text-align: center; padding: 24px; color: var(--text-muted);">Loading verified varsity dossier...</div>';

            try {
                const endpoint = isCompleted ? '/ride/api/admin/completed-rides' : '/ride/api/admin/rides';
                const res = await fetch(endpoint);
                const list = await res.json();
                const item = list.find(x => x.id === tripOrRideId);

                if (!item) throw new Error('Record not found');

                const routeLink = item.routeMapsLink || `https://www.google.com/maps/dir/?api=1&origin=${encodeURIComponent(item.originName)}&destination=${encodeURIComponent(item.destinationName)}`;

                let trajectory = { landmarks: [], points: [] };
                try {
                    const tRes = await fetch(`/ride/api/rides/${item.id}/route-trajectory`);
                    if (tRes.ok) trajectory = await tRes.json();
                } catch (_) {}

                const landmarksList = (trajectory.landmarks && trajectory.landmarks.length > 0)
                    ? trajectory.landmarks
                    : [item.originName || 'Khagan (DIU)', 'Akran', 'Birulia Bridge', 'Panchabati / Diabari', item.destinationName || 'Uttara / Mirpur'];
                const landmarksHtml = landmarksList.map(l => `<span class="pill pill-green" style="font-size: 11px; font-weight: bold;">📍 ${l}</span>`).join('<span style="color: #94A3B8; font-weight: 800;"> ➔ </span>');

                content.innerHTML = `
                    <div style="background: linear-gradient(135deg, #065F46 0%, #059669 100%); color: white; border-radius: var(--radius-md); padding: 18px; display: flex; flex-direction: column; gap: 6px; box-shadow: 0 4px 12px rgba(5, 150, 105, 0.25);">
                        <div style="display: flex; justify-content: space-between; align-items: center;">
                            <span style="font-size: 11px; text-transform: uppercase; letter-spacing: 0.6px; opacity: 0.9; font-weight: 700;">Daffodil International University • Safety Dossier</span>
                            <span class="pill" style="background: rgba(255,255,255,0.22); color: white; font-weight: 800; font-size: 10px;">ID: ${item.id}</span>
                        </div>
                        <div style="font-size: 16px; font-weight: 800; margin-top: 2px;">
                            📍 ${item.originName} ➔ ${item.destinationName}
                        </div>
                        <div style="font-size: 12px; opacity: 0.95;">
                            Completed: ${item.completedTime ? item.completedTime.replace('T', ' ') : 'Safely'} | Duration: ${item.durationMinutes ? item.durationMinutes.toFixed(0) : 15} mins | Fare: ৳${item.fare || 50}
                        </div>
                    </div>

                    <!-- Varsity Commuters Identity Matrix -->
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-top: 6px;">
                        <div style="border: 1px solid var(--border); border-radius: var(--radius-md); padding: 14px; background: #FAF5FF;">
                            <div style="font-size: 10px; text-transform: uppercase; color: #7C3AED; font-weight: 800; letter-spacing: 0.5px;">🏍️ DIU Biker / Driver</div>
                            <div style="font-size: 14px; font-weight: 800; margin-top: 4px; color: #0F172A;">${item.driverName}</div>
                            <div style="font-size: 11.5px; color: #475569; margin-top: 4px;">🆔 Student ID: <strong>${item.driverStudentId || item.driverId || 'Verified'}</strong></div>
                            <div style="font-size: 11.5px; color: #475569;">🏛️ Department: <strong>${item.driverDept || 'CSE'}</strong></div>
                            <div style="font-size: 11.5px; color: #475569;">📞 Contact: <strong>${item.driverPhone || 'On File'}</strong></div>
                            <div style="font-size: 11px; color: #059669; font-weight: 700; margin-top: 6px;">✓ University Verified Motorbike</div>
                        </div>

                        <div style="border: 1px solid var(--border); border-radius: var(--radius-md); padding: 14px; background: #ECFDF5;">
                            <div style="font-size: 10px; text-transform: uppercase; color: #059669; font-weight: 800; letter-spacing: 0.5px;">🎒 DIU Passenger / Peer</div>
                            <div style="font-size: 14px; font-weight: 800; margin-top: 4px; color: #0F172A;">${item.passengerName || 'Student Commuter'}</div>
                            <div style="font-size: 11.5px; color: #475569; margin-top: 4px;">🆔 Student ID: <strong>${item.passengerStudentId || item.passengerId || 'Verified'}</strong></div>
                            <div style="font-size: 11.5px; color: #475569;">🏛️ Department: <strong>${item.passengerDept || 'DIU Student'}</strong></div>
                            <div style="font-size: 11.5px; color: #475569;">📞 Contact: <strong>${item.passengerPhone || 'On File'}</strong></div>
                            <div style="font-size: 11px; color: #059669; font-weight: 700; margin-top: 6px;">✓ Seat Verified & Settled</div>
                        </div>
                    </div>

                    <!-- Direct Google Maps Route & Live Navigation Link -->
                    <div style="border: 1px solid #BFDBFE; background: #EFF6FF; border-radius: var(--radius-md); padding: 14px; margin-top: 6px; display: flex; flex-direction: column; gap: 8px;">
                        <div style="font-size: 11px; text-transform: uppercase; color: #1E40AF; font-weight: 800; display: flex; align-items: center; gap: 6px;">
                            <span>🗺️ Google Maps Complete Route & Transit Directions</span>
                        </div>
                        <div style="font-size: 12px; color: #334155;">
                            Exact turn-by-turn driving directions corridor recorded between pickup spot and dropoff destination.
                        </div>
                        <!-- Traversed Landmarks Corridor -->
                        <div style="background: white; border: 1.5px solid #FDE68A; border-radius: 8px; padding: 10px 12px; margin-top: 4px;">
                            <div style="font-size: 10px; text-transform: uppercase; color: #B45309; font-weight: 800; letter-spacing: 0.5px; margin-bottom: 6px;">
                                🛣️ Verified Corridor Path & Landmark Milestones
                            </div>
                            <div style="display: flex; flex-wrap: wrap; align-items: center; gap: 6px;">
                                ${landmarksHtml}
                            </div>
                        </div>

                        <div style="display: flex; flex-wrap: wrap; gap: 8px; margin-top: 4px;">
                            <a href="${routeLink}" target="_blank" 
                               style="display: inline-flex; align-items: center; gap: 6px; background: #2563EB; color: white; padding: 8px 14px; border-radius: 8px; font-size: 12px; font-weight: 700; text-decoration: none; box-shadow: 0 2px 6px rgba(37,99,235,0.3);">
                                🚗 Open Google Maps Directions ➔
                            </a>
                            <a href="/ride/api/rides/${item.id}/route-passport-pdf" target="_blank" 
                               style="display: inline-flex; align-items: center; gap: 6px; background: #E65100; color: white; padding: 8px 14px; border-radius: 8px; font-size: 12px; font-weight: 700; text-decoration: none; box-shadow: 0 2px 6px rgba(230,81,0,0.3);">
                                📄 Download Official Route PDF ↗
                            </a>
                        </div>
                    </div>

                    <!-- Official Campus Safety & Tracking Notes -->
                    <div style="border: 1px solid var(--border); border-radius: var(--radius-md); padding: 14px; margin-top: 6px; background: #F8FAFC;">
                        <div style="font-size: 10px; text-transform: uppercase; color: var(--text-muted); font-weight: 800;">📝 University Safety & Tracking Notes</div>
                        <div style="font-size: 12px; color: #334155; margin-top: 4px; line-height: 1.5;">
                            ${item.trackingNotes || 'Trip completed under DIU Student Carpool network rules. Both commuter identities and emergency contacts logged for campus safety.'}
                        </div>
                    </div>
                `;
            } catch(e) {
                content.innerHTML = `<div style="color: var(--danger); padding: 16px;">Failed to load dossier: ${e.message}</div>`;
            }
        }

        async function renderSosTab(container) {
            const res = await fetch('/ride/api/admin/sos-alerts');
            const alerts = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title" style="color: var(--danger);">🚨 Emergency SOS Alerts Log <span class="pill pill-red">${alerts.length} Logged</span></div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Alert ID</th>
                                    <th>Student Name</th>
                                    <th>Student ID</th>
                                    <th>Phone</th>
                                    <th>Location</th>
                                    <th>Coordinates</th>
                                    <th>Status</th>
                                    <th>Timestamp</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${alerts.map(a => `
                                    <tr style="background: #FEF2F2;">
                                        <td style="font-family: 'JetBrains Mono', monospace; font-size: 11px;">${a.id}</td>
                                        <td style="font-weight: 800; color: #991B1B;">${a.studentName}</td>
                                        <td style="font-family: 'JetBrains Mono', monospace;">${a.studentId}</td>
                                        <td style="font-weight: 700;">${a.studentPhone}</td>
                                        <td>${a.locationName}</td>
                                        <td style="font-family: 'JetBrains Mono', monospace;">${a.latitude.toFixed(4)}, ${a.longitude.toFixed(4)}</td>
                                        <td><span class="pill pill-red">${a.status.toUpperCase()}</span></td>
                                        <td style="font-size: 11px; color: #64748B;">${a.createdAt}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        async function renderNoticesTab(container) {
            const res = await fetch('/ride/api/admin/notices');
            const notices = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">📢 University Transport Bulletins & Broadcasts <span class="pill pill-green">${notices.length} Active</span></div>
                        <div class="toolbar">
                            <button class="btn btn-accent" onclick="openNoticeModal()">➕ Broadcast New Notice</button>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Headline</th>
                                    <th>Message Content</th>
                                    <th>Audience</th>
                                    <th>Priority</th>
                                    <th>Sender</th>
                                    <th>Published</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${notices.map(n => `
                                    <tr>
                                        <td style="font-weight: 800; color: var(--text-main);">${n.title}</td>
                                        <td style="max-width: 380px; line-height: 1.5;">${n.content}</td>
                                        <td><span class="pill pill-blue">${n.targetAudience.toUpperCase()}</span></td>
                                        <td><span class="pill ${n.priority === 'emergency' ? 'pill-red' : (n.priority === 'urgent' ? 'pill-amber' : 'pill-green')}">${n.priority.toUpperCase()}</span></td>
                                        <td style="font-size: 11.5px; font-family: 'JetBrains Mono', monospace;">${n.adminEmail}</td>
                                        <td style="font-size: 11.5px; color: var(--text-muted);">${n.createdAt.slice(0, 16).replace('T', ' ')}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        async function renderAdminsTab(container) {
            const res = await fetch('/ride/api/admin/admins');
            const admins = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">🛡️ Authority Administrators <span class="pill pill-blue">${admins.length} Officers</span></div>
                        <div class="toolbar">
                            <button class="btn btn-outline" style="color: var(--primary); border-color: var(--primary);" onclick="openPassModal()">🔑 Change Password</button>
                            <button class="btn btn-accent" onclick="openAddAdminModal()">➕ Add Administrator</button>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Admin Email</th>
                                    <th>Full Name</th>
                                    <th>Role Privilege</th>
                                    <th>Status</th>
                                    <th>Account Created</th>
                                    <th>Last Login</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${admins.map(a => `
                                    <tr>
                                        <td style="font-weight: 800; font-family: 'JetBrains Mono', monospace; font-size: 11.5px;">${a.email}</td>
                                        <td style="font-weight: 700;">${a.name}</td>
                                        <td><span class="pill pill-green">${a.role.toUpperCase()}</span></td>
                                        <td><span class="pill pill-blue">ACTIVE</span></td>
                                        <td style="font-size: 11px; color: #64748B;">${a.createdAt ? a.createdAt.slice(0, 10) : '—'}</td>
                                        <td style="font-size: 11px; color: #64748B;">${a.lastLogin || 'Never'}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        // =================================================================
        // Action Handlers (Notices, Password, Admins)
        // =================================================================

        function openNoticeModal() { document.getElementById('noticeModal').style.display = 'flex'; }
        function openPassModal() {
            if (loggedInAdmin) document.getElementById('chgEmail').value = loggedInAdmin.email;
            document.getElementById('passModal').style.display = 'flex';
        }
        function openAddAdminModal() { document.getElementById('addAdminModal').style.display = 'flex'; }
        function closeModal(id) { document.getElementById(id).style.display = 'none'; }

        async function submitNotice() {
            const title = document.getElementById('notcTitle').value.trim();
            const content = document.getElementById('notcContent').value.trim();
            const targetAudience = document.getElementById('notcAudience').value;
            const priority = document.getElementById('notcPriority').value;

            if (!title || !content) {
                alert('Please enter both title and content.');
                return;
            }

            try {
                const res = await fetch('/ride/api/admin/notices', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        title, content, targetAudience, priority,
                        adminEmail: loggedInAdmin?.email || '252-15-234@diu.edu.bd'
                    })
                });
                const d = await res.json();
                if (!res.ok) throw new Error(d.detail || 'Failed to send notice');
                alert('✓ ' + d.message);
                closeModal('noticeModal');
                document.getElementById('notcTitle').value = '';
                document.getElementById('notcContent').value = '';
                if (currentTab === 'notices') switchTab('notices');
            } catch(e) {
                alert('Error: ' + e.message);
            }
        }

        async function submitPasswordChange() {
            const email = document.getElementById('chgEmail').value.trim();
            const oldPassword = document.getElementById('chgOldPass').value;
            const newPassword = document.getElementById('chgNewPass').value;

            if (!email || !newPassword) {
                alert('Please fill email and new password.');
                return;
            }

            if (newPassword.length < 6) {
                alert('New password must be at least 6 characters.');
                return;
            }

            try {
                const res = await fetch('/ride/api/admin/change-password', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email, oldPassword, newPassword })
                });
                const d = await res.json();
                if (!res.ok) throw new Error(d.detail || 'Failed to change password');
                alert('✓ ' + d.message);
                closeModal('passModal');
                document.getElementById('chgOldPass').value = '';
                document.getElementById('chgNewPass').value = '';
            } catch(e) {
                alert('Error: ' + e.message);
            }
        }

        async function submitAddAdmin() {
            const name = document.getElementById('newAdmName').value.trim();
            const email = document.getElementById('newAdmEmail').value.trim();
            const password = document.getElementById('newAdmPass').value;
            const role = document.getElementById('newAdmRole').value;

            if (!name || !email || !password) {
                alert('All fields are required.');
                return;
            }

            try {
                const res = await fetch('/ride/api/admin/create-admin', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name, email, password, role })
                });
                const d = await res.json();
                if (!res.ok) throw new Error(d.detail || 'Failed to add admin');
                alert('✓ ' + d.message);
                closeModal('addAdminModal');
                document.getElementById('newAdmName').value = '';
                document.getElementById('newAdmEmail').value = '';
                document.getElementById('newAdmPass').value = '';
                if (currentTab === 'admins') switchTab('admins');
            } catch(e) {
                alert('Error: ' + e.message);
            }
        }

        function filterTableRows(query) {
            const q = query.toLowerCase().trim();
            const rows = document.querySelectorAll('.data-table tbody tr');
            rows.forEach(r => {
                const text = r.innerText.toLowerCase();
                r.style.display = text.includes(q) ? '' : 'none';
            });
        }

        // =================================================================
        // AI Assistant Settings Management
        // =================================================================

        async function renderAiAssistantTab(container) {
            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div>
                            <div class="card-title">🤖 DIU Ride AI Companion & Prompt Control Center</div>
                            <div style="font-size: 12px; color: var(--text-muted); margin-top: 4px;">
                                Manage Groq Cloud LLM engine, customize cordial student prompt, edit app knowledge base, and monitor active rides file.
                            </div>
                        </div>
                        <div class="toolbar">
                            <button class="btn btn-outline" style="color: var(--primary); border-color: var(--primary);" onclick="resetAiPromptToDefault()">↺ Reset Prompt</button>
                            <button class="btn btn-accent" onclick="saveAiSettingsFromAdmin()">💾 Save AI Settings</button>
                        </div>
                    </div>
                    <div style="padding: 24px; display: flex; flex-direction: column; gap: 20px;">
                        <div style="background: #EFF6FF; border: 1.5px solid #93C5FD; border-radius: var(--radius-md); padding: 16px 20px; color: #1E40AF; font-size: 13px; line-height: 1.6;">
                            💡 <strong>Realtime AI Control:</strong> Any edits made to the System Prompt, Model, or Knowledge Base are saved to the SQLite database and immediately update all student mobile chatboxes and web terminals in real time without server restart.
                        </div>

                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px;">
                            <div class="form-group">
                                <label>Groq Cloud API Key</label>
                                <input id="aiGroqKey" type="password" class="form-control" placeholder="gsk_...">
                            </div>
                            <div class="form-group">
                                <label>LLM Model Name</label>
                                <input id="aiModelName" type="text" class="form-control" placeholder="llama-3.3-70b-versatile">
                            </div>
                        </div>

                        <div class="form-group">
                            <div style="display: flex; justify-content: space-between;">
                                <label>AI Persona System Prompt</label>
                                <span id="promptCharCount" style="font-size: 11px; color: var(--text-muted);">0 chars</span>
                            </div>
                            <textarea id="aiSystemPrompt" class="form-control" rows="8" oninput="updatePromptCount()"></textarea>
                        </div>

                        <div class="form-group">
                            <label>DIU Campus Transport Knowledge Base</label>
                            <textarea id="aiKnowledgeBase" class="form-control" rows="6"></textarea>
                        </div>
                    </div>
                </div>
            `;

            loadAiSettingsIntoForm();
        }

        async function loadAiSettingsIntoForm() {
            try {
                const res = await fetch('/ride/api/admin/ai-settings');
                const data = await res.json();
                if (data.status === 'success' && data.settings) {
                    const s = data.settings;
                    if (document.getElementById('aiGroqKey')) document.getElementById('aiGroqKey').value = s.groq_api_key || '';
                    if (document.getElementById('aiModelName')) document.getElementById('aiModelName').value = s.model_name || '';
                    if (document.getElementById('aiSystemPrompt')) {
                        document.getElementById('aiSystemPrompt').value = s.system_prompt || '';
                        updatePromptCount();
                    }
                    if (document.getElementById('aiKnowledgeBase')) document.getElementById('aiKnowledgeBase').value = s.app_knowledge_base || '';
                }
            } catch (e) {
                console.error('Failed to load AI settings:', e);
            }
        }

        function updatePromptCount() {
            const promptEl = document.getElementById('aiSystemPrompt');
            const countEl = document.getElementById('promptCharCount');
            if (promptEl && countEl) {
                countEl.innerText = `${promptEl.value.length} chars`;
            }
        }

        async function saveAiSettingsFromAdmin() {
            const groq_api_key = (document.getElementById('aiGroqKey')?.value || '').trim();
            const model_name = (document.getElementById('aiModelName')?.value || '').trim();
            const system_prompt = document.getElementById('aiSystemPrompt')?.value || '';
            const app_knowledge_base = document.getElementById('aiKnowledgeBase')?.value || '';

            if (!groq_api_key) {
                alert('Groq API Key is required.');
                return;
            }

            try {
                const res = await fetch('/ride/api/admin/ai-settings', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ groq_api_key, model_name, system_prompt, app_knowledge_base })
                });
                const data = await res.json();
                if (!res.ok) throw new Error(data.detail || 'Failed to save');
                alert('✓ ' + (data.message || 'AI Settings saved successfully!'));
            } catch (e) {
                alert('Error saving AI settings: ' + e.message);
            }
        }

        async function resetAiPromptToDefault() {
            if (!confirm('Are you sure you want to reset the system prompt to the default polite DIU Ride prompt?')) return;
            try {
                const res = await fetch('/ride/api/admin/ai-reset-prompt', { method: 'POST' });
                const data = await res.json();
                if (!res.ok) throw new Error(data.detail || 'Reset failed');
                alert('✓ ' + (data.message || 'Prompt reset successfully!'));
                await loadAiSettingsIntoForm();
            } catch (e) {
                alert('Error resetting prompt: ' + e.message);
            }
        }
    </script>
</body>
</html>
"""

@admin_router.api_route("/ride/admin", methods=["GET", "HEAD"], response_class=HTMLResponse)
@admin_router.api_route("/ride/admin/", methods=["GET", "HEAD"], response_class=HTMLResponse)
@admin_router.api_route("/admin", methods=["GET", "HEAD"], response_class=HTMLResponse)
@admin_router.api_route("/admin/", methods=["GET", "HEAD"], response_class=HTMLResponse)
def serve_admin_portal():
    return HTMLResponse(content=ADMIN_HTML)

