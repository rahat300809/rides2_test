import os
import json
import sqlite3
import threading
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional

LOCK = threading.Lock()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ACTIVE_RIDES_JSON_PATH = os.path.join(BASE_DIR, "active_rides_data.json")
ACTIVE_RIDES_MD_PATH = os.path.join(BASE_DIR, "LIVE_ACTIVE_RIDES.md")
DB_PATH = os.path.join(BASE_DIR, "rides.db")

def get_bd_now() -> datetime:
    """Returns Bangladesh local time (UTC+6)."""
    return datetime.now(timezone(timedelta(hours=6)))

def format_bd_timestamp(dt: Optional[datetime] = None) -> str:
    if dt is None:
        dt = get_bd_now()
    return dt.strftime("%Y-%m-%d %I:%M:%S %p")

def parse_departure_time(dep_str: str) -> Optional[datetime]:
    if not dep_str:
        return None
    cleaned = str(dep_str).replace("Z", "").strip()
    low = cleaned.lower()
    if any(k in low for k in ('now', 'asap', 'immediate')):
        return get_bd_now().replace(tzinfo=None)
    try:
        return datetime.fromisoformat(cleaned)
    except Exception:
        pass
    for fmt in (
        "%Y-%m-%d %I:%M %p",
        "%Y-%m-%d %I:%M%p",
        "%Y-%m-%d %I:%M:%S %p",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d",
        "%d-%m-%Y %I:%M %p",
        "%d/%m/%Y %I:%M %p",
        "%m/%d/%Y %I:%M %p",
    ):
        try:
            return datetime.strptime(cleaned, fmt)
        except Exception:
            pass
    # If format is time-only like 05:30 PM or 17:00, combine with today's date
    for t_fmt in ("%I:%M %p", "%I:%M%p", "%H:%M"):
        try:
            parsed_t = datetime.strptime(cleaned, t_fmt).time()
            bd_today = get_bd_now().date()
            return datetime.combine(bd_today, parsed_t)
        except Exception:
            pass
    return None

def format_human_departure_time(dep_str: str) -> str:
    dt = parse_departure_time(dep_str)
    if not dt:
        return str(dep_str)
    return dt.strftime("%I:%M %p")

def is_ride_expired(dep_str: str, grace_minutes: int = 60, created_at_str: Optional[str] = None) -> bool:
    """
    Checks if departure time is in the past.
    Local Bangladesh time (UTC+6) is used.
    """
    # 1. If created more than 24 hours ago, definitely expired
    if created_at_str:
        try:
            c_dt = datetime.fromisoformat(str(created_at_str).replace("Z", "+00:00"))
            if (datetime.now(timezone.utc) - c_dt).total_seconds() > 24 * 3600:
                return True
        except Exception:
            pass

    dep_dt = parse_departure_time(dep_str)
    if not dep_dt:
        if created_at_str:
            try:
                c_dt = datetime.fromisoformat(str(created_at_str).replace("Z", "+00:00"))
                if (datetime.now(timezone.utc) - c_dt).total_seconds() > 8 * 3600:
                    return True
            except Exception:
                pass
        return True  # If unparseable, don't keep as active to avoid stale suggestions
    
    # Strip timezone for naive comparison against local time
    if dep_dt.tzinfo is not None:
        dep_dt = dep_dt.replace(tzinfo=None)

    now_naive = get_bd_now().replace(tzinfo=None)
    diff_minutes = (now_naive - dep_dt).total_seconds() / 60.0
    return diff_minutes >= grace_minutes

def format_ride_object(r: Dict[str, Any]) -> Dict[str, Any]:
    dep_raw = str(r.get("departure_time") or "")
    dep_formatted = format_human_departure_time(dep_raw)
    
    fare = float(r.get("fare_per_seat") or 0.0)
    avail = int(r.get("available_seats") or 0)
    total = int(r.get("total_seats") or max(avail, 1))

    return {
        "id": str(r.get("id") or ""),
        "driver_id": str(r.get("driver_id") or ""),
        "driver_name": str(r.get("driver_name") or "DIU Biker"),
        "driver_dept": str(r.get("driver_dept") or "Student"),
        "driver_phone": str(r.get("driver_phone") or ""),
        "driver_rating": float(r.get("driver_rating") or 5.0),
        "driver_ride_count": int(r.get("driver_ride_count") or 1),
        "driver_photo_url": r.get("driver_photo_url"),
        "vehicle_model": str(r.get("vehicle_model") or "Motorbike"),
        "vehicle_type": str(r.get("vehicle_type") or "bike"),
        "vehicle_plate": str(r.get("vehicle_plate") or ""),
        "vehicle_color": str(r.get("vehicle_color") or ""),
        "origin_name": str(r.get("origin_name") or ""),
        "origin_subtitle": r.get("origin_subtitle") or "",
        "origin_lat": float(r.get("origin_lat") or 23.8765),
        "origin_lng": float(r.get("origin_lng") or 90.3204),
        "destination_name": str(r.get("destination_name") or ""),
        "destination_subtitle": r.get("destination_subtitle") or "",
        "destination_lat": float(r.get("destination_lat") or 23.8728),
        "destination_lng": float(r.get("destination_lng") or 90.3984),
        "waypoint_name": r.get("waypoint_name") or "",
        "route_corridor": str(r.get("route_corridor") or "Campus Corridor"),
        "departure_time": dep_raw,
        "departure_time_formatted": dep_formatted,
        "fare_per_seat": fare,
        "total_seats": total,
        "available_seats": avail,
        "is_female_only": bool(r.get("is_female_only")),
        "status": str(r.get("status") or "published"),
        "created_at": str(r.get("created_at") or ""),
        "last_updated_at": format_bd_timestamp(),
    }

def generate_markdown_content(rides: List[Dict[str, Any]]) -> str:
    bd_now_str = format_bd_timestamp()
    lines = [
        "# DIU Ride - Live Active Posted Rides (Realtime Knowledge Base)",
        f"- **Last Synchronized:** {bd_now_str} (Bangladesh Standard Time)",
        f"- **Total Active Rides Listed:** {len(rides)}",
        "- **Status:** Active peer-to-peer campus carpools currently open for booking.",
        "",
        "---",
        ""
    ]

    if not rides:
        lines.append("### ℹ️ Currently No Active Rides Listed")
        lines.append("There are currently no active published motorbike rides available. All previous rides have either completed, reached capacity (booked), or their scheduled departure time has expired.")
        lines.append("")
        lines.append("💡 *Students can use the 'Schedule / Throw Request' feature in the app to post their route so passing bikers can accept.*")
        return "\n".join(lines)

    for idx, r in enumerate(rides, 1):
        female_tag = " [👧 Female Only]" if r.get("is_female_only") else ""
        plate_str = f"({r['vehicle_plate']})" if r.get("vehicle_plate") else ""
        waypoint_str = f" via {r['waypoint_name']}" if r.get("waypoint_name") else ""
        bike_str = f"{r['vehicle_model']} {plate_str}".strip()
        lines.extend([
            f"### Ride #{idx}: {r['origin_name']} ➔ {r['destination_name']}{female_tag}",
            f"- **Ride ID:** `{r['id']}`",
            f"- **Biker / Rider:** {r['driver_name']} (Dept: {r['driver_dept']} | Phone: {r['driver_phone'] or 'Provided in app'})",
            f"- **Vehicle / Bike:** {bike_str}",
            f"- **Route Corridor:** {r['route_corridor']}{waypoint_str}",
            f"- **Departure Time:** {r['departure_time_formatted']} (Raw: {r['departure_time']})",
            f"- **Fuel Share Fare:** ৳{r['fare_per_seat']:.0f} BDT",
            f"- **Available Seats:** {r['available_seats']} of {r['total_seats']} seats remaining",
            f"- **Current Ride Status:** {r['status'].upper()}",
            ""
        ])

    lines.append("---")
    lines.append("*(Note: When a ride reaches 0 available seats, completes, is cancelled, or its departure time passes, it is automatically purged from this live file.)*")
    return "\n".join(lines)

def write_active_rides_files(rides: List[Dict[str, Any]]) -> None:
    """Safely writes both active_rides_data.json and LIVE_ACTIVE_RIDES.md atomically."""
    with LOCK:
        payload = {
            "meta": {
                "title": "DIU Ride - Live Active Posted Rides",
                "description": "Real-time persistent repository of currently active, non-expired campus rides with available seats. Read by DIU Ride AI Companion.",
                "last_synced_at": format_bd_timestamp(),
                "total_active_rides": len(rides),
                "auto_removal_rules": {
                    "on_completed": "Automatically removed when trip is finished.",
                    "on_fully_booked": "Automatically removed when available_seats reaches 0.",
                    "on_expired": "Automatically removed when departure time passes by 10 minutes without extension.",
                    "on_cancelled": "Automatically removed when driver or admin cancels/deletes the ride."
                }
            },
            "rides": rides
        }

        # 1. Write active_rides_data.json
        tmp_json = ACTIVE_RIDES_JSON_PATH + ".tmp"
        try:
            with open(tmp_json, "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False, indent=2)
            if os.path.exists(ACTIVE_RIDES_JSON_PATH):
                os.remove(ACTIVE_RIDES_JSON_PATH)
            os.rename(tmp_json, ACTIVE_RIDES_JSON_PATH)
        except Exception as e:
            if os.path.exists(tmp_json):
                try:
                    os.remove(tmp_json)
                except Exception:
                    pass
            print(f"[ActiveRidesManager Error Writing JSON] {e}")

        # 2. Write LIVE_ACTIVE_RIDES.md
        tmp_md = ACTIVE_RIDES_MD_PATH + ".tmp"
        try:
            md_text = generate_markdown_content(rides)
            with open(tmp_md, "w", encoding="utf-8") as f:
                f.write(md_text)
            if os.path.exists(ACTIVE_RIDES_MD_PATH):
                os.remove(ACTIVE_RIDES_MD_PATH)
            os.rename(tmp_md, ACTIVE_RIDES_MD_PATH)
        except Exception as e:
            if os.path.exists(tmp_md):
                try:
                    os.remove(tmp_md)
                except Exception:
                    pass
            print(f"[ActiveRidesManager Error Writing Markdown] {e}")

def get_active_rides_from_file() -> List[Dict[str, Any]]:
    """
    Reads the active rides from active_rides_data.json.
    Auto-initializes or cleans up expired rides if necessary.
    """
    if not os.path.exists(ACTIVE_RIDES_JSON_PATH):
        return sync_active_rides_file()

    try:
        with open(ACTIVE_RIDES_JSON_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            rides = data.get("rides", [])
    except Exception as e:
        print(f"[ActiveRidesManager Error Reading File] {e}, re-syncing...")
        return sync_active_rides_file()

    # Filter out any ride that has expired or has 0 available seats
    valid_rides = []
    has_expired = False
    for r in rides:
        if r.get("status") not in ("published", "active"):
            has_expired = True
            continue
        if int(r.get("available_seats") or 0) <= 0:
            has_expired = True
            continue
        if is_ride_expired(r.get("departure_time") or "", grace_minutes=15, created_at_str=r.get("created_at")):
            has_expired = True
            continue
        valid_rides.append(r)

    if has_expired:
        # Re-save cleaned rides list
        write_active_rides_files(valid_rides)

    return valid_rides

def sync_active_rides_file(conn: Optional[sqlite3.Connection] = None) -> List[Dict[str, Any]]:
    """
    Full database synchronization: queries all published/active rides with available seats > 0
    from SQLite, excludes expired ones, and writes them to the files.
    """
    close_conn = False
    if conn is None:
        if not os.path.exists(DB_PATH):
            write_active_rides_files([])
            return []
        conn = sqlite3.connect(DB_PATH, timeout=15.0)
        conn.row_factory = sqlite3.Row
        close_conn = True

    try:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT * FROM rides
            WHERE status IN ('published', 'active') AND available_seats > 0
            ORDER BY created_at DESC
        """)
        rows = [dict(r) for r in cursor.fetchall()]

        valid_rides = []
        for r in rows:
            dep_time = r.get("departure_time") or ""
            c_time = r.get("created_at") or ""
            if not is_ride_expired(dep_time, grace_minutes=15, created_at_str=c_time):
                valid_rides.append(format_ride_object(r))

        write_active_rides_files(valid_rides)
        return valid_rides
    except Exception as e:
        print(f"[ActiveRidesManager Sync DB Error] {e}")
        return []
    finally:
        if close_conn:
            conn.close()

def add_or_update_ride_in_file(ride_data: Dict[str, Any]) -> None:
    """Adds or updates a ride in the active rides file."""
    ride_id = str(ride_data.get("id") or "")
    if not ride_id:
        return

    status = str(ride_data.get("status") or "published").lower()
    avail = int(ride_data.get("available_seats") if "available_seats" in ride_data else ride_data.get("availableSeats", 1))

    # If completed, cancelled, or 0 seats, remove it!
    if status not in ("published", "active") or avail <= 0:
        remove_ride_from_file(ride_id)
        return

    dep_time = str(ride_data.get("departure_time") if "departure_time" in ride_data else ride_data.get("departureTime", ""))
    if is_ride_expired(dep_time):
        remove_ride_from_file(ride_id)
        return

    current_rides = get_active_rides_from_file()
    formatted = format_ride_object(ride_data)

    updated_list = []
    found = False
    for r in current_rides:
        if r["id"] == ride_id:
            updated_list.append(formatted)
            found = True
        else:
            updated_list.append(r)

    if not found:
        updated_list.append(formatted)

    # Sort by departure time
    updated_list.sort(key=lambda x: str(x.get("departure_time") or ""))
    write_active_rides_files(updated_list)

def remove_ride_from_file(ride_id: str) -> None:
    """Removes a ride from the active rides file when completed, booked, cancelled, or expired."""
    if not ride_id:
        return
    current_rides = get_active_rides_from_file()
    filtered = [r for r in current_rides if r["id"] != str(ride_id)]
    if len(filtered) != len(current_rides):
        write_active_rides_files(filtered)
        print(f"[ActiveRidesManager] Successfully removed ride {ride_id} from active rides file.")

def get_active_rides_for_ai() -> str:
    """
    Returns a richly formatted string containing all active rides
    read directly from the active rides file for injection into AI prompt.
    """
    rides = get_active_rides_from_file()
    if not rides:
        return "NO PUBLISHED RIDES CURRENTLY IN ACTIVE RIDES FILE. All seats are booked or no bikers have posted rides yet."

    lines = [f"TOTAL ACTIVE POSTED RIDES AVAILABLE: {len(rides)}"]
    for idx, r in enumerate(rides, 1):
        female_str = " (FEMALE ONLY)" if r.get("is_female_only") else ""
        waypoint_str = f" (via {r['waypoint_name']})" if r.get("waypoint_name") else ""
        lines.append(
            f"{idx}. [ID: {r['id']}] Driver: {r['driver_name']} (Dept: {r.get('driver_dept') or 'Student'} | Phone: {r.get('driver_phone') or 'In App'}) | "
            f"Route: {r['origin_name']} ➔ {r['destination_name']}{waypoint_str} | "
            f"Corridor: {r.get('route_corridor') or 'Campus Highway'} | "
            f"Time: {r['departure_time_formatted']} ({r['departure_time']}) | "
            f"Fare: {r['fare_per_seat']} ৳ | Seats Left: {r['available_seats']}/{r['total_seats']} | "
            f"Bike: {r['vehicle_model']}{female_str}"
        )
    return "\n".join(lines)
