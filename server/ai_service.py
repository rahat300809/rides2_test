import os
import json
import base64
import sqlite3
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional

from active_rides_manager import (
    get_active_rides_from_file,
    get_active_rides_for_ai,
    ACTIVE_RIDES_JSON_PATH,
    ACTIVE_RIDES_MD_PATH,
)
from hex_spatial_engine import (
    DROPPING_ZONES,
    find_nearest_dropping_zone,
    rank_bikers_by_hex_spatial_proximity,
    haversine_distance_m,
    lat_lng_to_hex8,
    resolve_target_from_text,
    format_hex_spatial_brief_for_ai,
)

def get_default_groq_key() -> str:
    env_k = os.getenv("GROQ_API_KEY")
    if env_k and env_k.strip():
        return env_k.strip()
    cfg = os.path.join(os.path.dirname(__file__), "ai_config.json")
    if os.path.exists(cfg):
        try:
            with open(cfg, "r", encoding="utf-8") as f:
                d = json.load(f)
                if d.get("groq_api_key"):
                    return d["groq_api_key"].strip()
        except Exception:
            pass
    return ""

DEFAULT_GROQ_API_KEY = get_default_groq_key()
DEFAULT_MODEL_NAME = "openai/gpt-oss-120b"
FALLBACK_MODELS = ["qwen/qwen3.8-27b", "openai/gpt-oss-20b"]

DEFAULT_SYSTEM_PROMPT = """You are "DIU Ride AI Assistant" (ডিআইইউ রাইড সহকারী) — an exceptionally courteous, warm, respectful, caring, and intelligent campus assistant built exclusively for students, teachers, and commuters of Daffodil International University (DIU).

### Core Demeanor & Personality:
1. **Unmatched Politeness & Cordiality**: Always speak with the utmost respect, brotherly/sisterly affection, and warmth. Use polite respectful Bengali phrases (e.g. "আসসালামু আলাইকুম [নাম] ভাইয়া/আপু! 🌸", "আপনার দিনটি অনেক সুন্দর ও বরকতময় কাটুক", "আপনার যাত্রা নিরাপদ হোক", "আমি আপনাকে কীভাবে সাহায্য করতে পারি?").
2. **Loving & Caring Campus Companion**: Treat students affectionately like dear university peers. Never be robotic, brief, or cold. Be cheerful, helpful, patient, and polite.
3. **Language**: Naturally answer in polite Bengali (বাংলা), English, or Banglish depending on how the student writes, but ALWAYS keep the tone heartfelt, respectful, and cordial.

### CRITICAL GREETING & CONVERSATION RULE (NO REPETITIVE SALAM):
- Do NOT say "আসসালামু আলাইকুম" or "হ্যালো" at the start of every message.
- The student was ALREADY greeted with Salam once when they opened the Support Center.
- Only say "ওয়ালাইকুম আসসালাম" or greet if the student explicitly greets you first in that message.
- In all other ongoing conversation, jump straight into answering their question or helping them directly, politely, and helpfully with a respectful, brotherly/sisterly tone.

### Core Capabilities & Spatial Brain:
1. **Personalized Greetings**:
   - Always address the student by their name respectfully (e.g. "রাহাত ভাইয়া" / "তনিমা আপু") when their name is known.
2. **Google / H3 Hexagonal Spatial Brain & Nearest Dropping Zones**:
   - You possess an advanced Hexagonal Spatial Indexing Brain (Resolution 8 / ~460m grid cell resolution).
   - Designated Campus & Highway Dropping Zones include:
     • DIU Main Gate 1 (Ashulia HQ & Central Bike Stand)
     • DIU Gate 2 (Engineering Complex & East Wing)
     • Academic Building 4 (AB-4 Daffodil Tower — CSE/SWE Hub)
     • Campus Lake Bridge & Cafeteria (Central Food Court)
     • Transport Terminal & Bus Bay
     • Birulia Bridge Crossing (Highway Junction)
     • Uttara North Metro Station (Diabari Exit 2)
     • Uttara House Building (Sector 7/9)
     • Mirpur-10 Roundabout (Metro Pillar 240)
     • ECB Chattar (Matikata Road / Cantonment Flyover)
     • Dhanmondi Campus (Sobhanbag / Mirpur Road 27)
     • Savar Bazar Bus Stand (Overbridge)
   - When a student asks about travel, bikers, or rides:
     • Identify the **nearest biker driver** whose drop-off hexagon cell is closest to the student's target.
     • Suggest the **nearest official Dropping Zone** with walking distance (e.g. "মাত্র ৩২০ মিটার দূরে") and walking ETA in minutes.
     • Explain why this dropping zone is convenient (e.g. "আপনি গেট ১ এ নেমে হেঁটে ২ মিনিটে ক্লাসে পৌঁছাতে পারবেন").
3. **Live Active Posted Rides & Strict Freshness Guarantee**:
   - You have direct, real-time read access to the LIVE POSTED RIDES file (`active_rides_data.json`).
   - Every ride in this file represents a fresh, verified, currently active commute with available seats.
   - **CRITICAL FRESHNESS RULE**: You MUST ONLY suggest recent, active, unexpired rides. NEVER suggest rides whose scheduled departure time has already passed, completed rides, cancelled rides, or stale posts from yesterday.
   - When suggesting rides, quote the exact fresh details: Biker's Name, Department, Bike Model, Departure Time, Available Seats, and Fuel Share Fare in ৳ BDT.
   - If no active biker is currently scheduled for the student's requested corridor/time, politely say:
     "বর্তমানে এই রুটে কোনো লাইভ রাইড খালি নেই ভাইয়া/আপু। আপনি চাইলে অ্যাপের 'Post Custom Ride Request' অপশন ব্যবহার করে আপনার সময় ও রুট পোস্ট করতে পারেন, তাহলে কোনো বাইকার ভাইয়া দেখে আপনাকে পিক করে নিবেন।"
4. **App Guidance & Tutorial**:
   - Guide students on how to search and book rides, publish rides to split fuel, use private messaging, and access the Emergency SOS button.
"""

def get_default_knowledge_base() -> str:
    kb_path = os.path.join(os.path.dirname(__file__), "APP_AI_KNOWLEDGE_BASE.md")
    if os.path.exists(kb_path):
        try:
            with open(kb_path, "r", encoding="utf-8") as f:
                return f.read()
        except Exception:
            pass
    return """# DIU Ride Guidelines
DIU Ride is an exclusive peer-to-peer campus ride sharing network for Daffodil International University (DIU) students and staff.
- Passenger Mode: Search and book departing bikes, or schedule custom ride requests.
- Rider Mode: Offer seats to split fuel (30-80 BDT), view student requests, and track confirmations.
- Safety: SOS emergency button, live GPS tracking, and verified varsity community.
"""

def init_ai_settings_table(conn: sqlite3.Connection):
    cursor = conn.cursor()
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS ai_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    """)

    now = datetime.now(timezone.utc).isoformat()
    defaults = {
        "groq_api_key": DEFAULT_GROQ_API_KEY,
        "model_name": DEFAULT_MODEL_NAME,
        "system_prompt": DEFAULT_SYSTEM_PROMPT,
        "app_knowledge_base": get_default_knowledge_base(),
    }

    for k, v in defaults.items():
        cursor.execute("SELECT key FROM ai_settings WHERE key = ?", (k,))
        if not cursor.fetchone():
            cursor.execute("INSERT INTO ai_settings (key, value, updated_at) VALUES (?, ?, ?)", (k, v, now))
        elif k == "system_prompt":
            cursor.execute("UPDATE ai_settings SET value = ?, updated_at = ? WHERE key = ?", (v, now, k))

    conn.commit()

def get_all_ai_settings(conn: sqlite3.Connection) -> Dict[str, str]:
    cursor = conn.cursor()
    cursor.execute("SELECT key, value FROM ai_settings")
    rows = cursor.fetchall()
    settings = {r[0]: r[1] for r in rows}
    if "groq_api_key" not in settings:
        settings["groq_api_key"] = DEFAULT_GROQ_API_KEY
    if "model_name" not in settings:
        settings["model_name"] = DEFAULT_MODEL_NAME
    if "system_prompt" not in settings:
        settings["system_prompt"] = DEFAULT_SYSTEM_PROMPT
    if "app_knowledge_base" not in settings:
        settings["app_knowledge_base"] = get_default_knowledge_base()
    return settings

def save_ai_settings(conn: sqlite3.Connection, settings: Dict[str, str]) -> Dict[str, str]:
    cursor = conn.cursor()
    now = datetime.now(timezone.utc).isoformat()
    for k, v in settings.items():
        cursor.execute("""
        INSERT INTO ai_settings (key, value, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
        """, (k, str(v), now))
    conn.commit()
    return get_all_ai_settings(conn)

def call_groq_chat(api_key: str, model: str, messages: List[Dict[str, str]], max_tokens: int = 800) -> str:
    url = "https://api.groq.com/openai/v1/chat/completions"
    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 0.4,
    }
    data_bytes = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data_bytes,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "DIU-Ride-AI/1.0",
        }
    )

    # 8-second snappy timeout to prevent client app freezes
    with urllib.request.urlopen(req, timeout=8) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        choices = res.get("choices", [])
        if choices:
            msg = choices[0].get("message", {})
            content = msg.get("content") or ""
            if not content.strip() and "reasoning" in msg:
                content = msg.get("reasoning") or ""
            return content.strip()
    return ""

def normalize_bangla_query(text: str) -> str:
    """Translates common Bengali location words and commute keywords to English tokens for matching."""
    t = text.lower()
    replacements = {
        "মিরপুর": " mirpur ",
        "আশুলিয়া": " ashulia ",
        "আশুলিয়া": " ashulia ",
        "উত্তরা": " uttara ",
        "ধানমন্ডি": " dhanmondi ",
        "বিরুলিয়া": " birulia ",
        "বিরুলিয়া": " birulia ",
        "ফার্মগেট": " farmgate ",
        "ক্যাম্পাস": " campus dsc ",
        "ডিএসসি": " dsc ",
        "স্মার্ট সিটি": " smart city ",
        "বাইক": " bike biker ",
        "বাইকার": " biker ",
        "রাইড": " ride ",
        "যাত্রী": " passenger ",
        "সব": " all ",
        "দেখাও": " show all ",
        "আসে": " ride ",
        "যাব": " ride ",
    }
    for bn, en in replacements.items():
        t = t.replace(bn, en)
    return t

def process_ai_chat_request(conn: sqlite3.Connection, payload: Dict[str, Any]) -> Dict[str, Any]:
    user_id = payload.get("user_id") or ""
    user_name = (payload.get("user_name") or "Student").strip()
    user_role = (payload.get("user_role") or "passenger").strip().lower()
    message = (payload.get("message") or "").strip()
    history = payload.get("history") or []

    settings = get_all_ai_settings(conn)
    api_key = settings.get("groq_api_key", DEFAULT_GROQ_API_KEY).strip()
    primary_model = settings.get("model_name", DEFAULT_MODEL_NAME).strip()
    system_prompt = settings.get("system_prompt", DEFAULT_SYSTEM_PROMPT)
    knowledge_base = settings.get("app_knowledge_base", "")

    # DIRECT READ: Sync from database first to ensure fresh continuous rides data
    try:
        sync_active_rides_file(conn)
    except Exception:
        pass
    active_rides = get_active_rides_from_file()
    rides_summary = get_active_rides_for_ai()

    # Query latest campus community feed posts from database
    cursor = conn.cursor()
    try:
        cursor.execute("""
        SELECT id, user_name, user_dept, user_role, content, category, created_at
        FROM campus_feed_posts
        ORDER BY created_at DESC
        LIMIT 5
        """)
        feed_rows = [dict(r) for r in cursor.fetchall()]
    except Exception:
        feed_rows = []

    feed_summary = ""
    if feed_rows:
        feed_lines = []
        for fp in feed_rows:
            feed_lines.append(
                f"- [{fp.get('category', 'GENERAL')}] {fp['user_name']} ({fp.get('user_dept', 'Student')}): \"{fp['content']}\" (Posted: {fp.get('created_at', '')})"
            )
        feed_summary = "\n".join(feed_lines)
    else:
        feed_summary = "No recent campus updates posted."

    # Query fresh open passenger requests from database (strictly active & non-expired < 18h)
    cursor.execute("""
    SELECT id, passenger_name, passenger_dept, passenger_phone, pickup, dropoff,
           requested_time, proposed_fare, notes, created_at
    FROM passenger_requests
    WHERE status IN ('open', 'pending')
    ORDER BY created_at DESC
    LIMIT 20
    """)
    raw_requests = [dict(r) for r in cursor.fetchall()]
    active_requests = []
    now_utc = datetime.now(timezone.utc)
    for q in raw_requests:
        c_at = q.get("created_at")
        if c_at:
            try:
                dt_c = datetime.fromisoformat(str(c_at).replace("Z", "+00:00"))
                if (now_utc - dt_c).total_seconds() > 18 * 3600:
                    continue  # Purge stale passenger requests older than 18 hours
            except Exception:
                pass
        active_requests.append(q)

    requests_summary = ""
    if active_requests:
        req_lines = []
        for q in active_requests:
            req_lines.append(
                f"- [Req ID: {q['id']}] Passenger: {q['passenger_name']} ({q.get('passenger_dept') or 'Student'}) | "
                f"Pickup: {q['pickup']} -> Dropoff: {q['dropoff']} | "
                f"Requested Time: {q['requested_time']} | Proposed Fare: {q['proposed_fare']} BDT"
            )
        requests_summary = "\n".join(req_lines)
    else:
        requests_summary = "No open student passenger requests currently listed."

    # Resolve target location from payload or user message text
    target_lat = payload.get("target_lat")
    target_lng = payload.get("target_lng")
    target_name = (payload.get("target_name") or "").strip()

    if target_lat is None or target_lng is None or (float(target_lat) == 0.0 and float(target_lng) == 0.0):
        t_lat, t_lng, t_name = resolve_target_from_text(message)
        target_lat = t_lat
        target_lng = t_lng
        if not target_name:
            target_name = t_name
    else:
        target_lat = float(target_lat)
        target_lng = float(target_lng)
        if not target_name:
            _, _, t_name = resolve_target_from_text(message)
            target_name = t_name

    # Hexagonal Proximity Ranking & Nearest Dropping Zone
    nearest_drop_zone = find_nearest_dropping_zone(target_lat, target_lng)
    ranked_hex_bikers = rank_bikers_by_hex_spatial_proximity(
        active_rides=active_rides,
        target_lat=target_lat,
        target_lng=target_lng,
        target_name=target_name,
        is_destination_search=True,
    )
    hex_brief = format_hex_spatial_brief_for_ai(
        ranked_bikers=ranked_hex_bikers,
        target_name=target_name,
        target_lat=target_lat,
        target_lng=target_lng,
        nearest_drop_zone=nearest_drop_zone,
    )

    # BD Current time calculation (UTC+6)
    bd_now = datetime.now(timezone(timedelta(hours=6))).strftime("%Y-%m-%d %I:%M %p")

    composed_system_prompt = f"""{system_prompt}

### CURRENT OPERATIONAL CONTEXT:
- Current Local Time (Bangladesh): {bd_now}
- Interacting Student Name: {user_name}
- Student Current App Mode: {"Biker / Rider (Motorbike Owner)" if user_role == "rider" else "Passenger (Commuter)"}
- Realtime Storage Source: {os.path.basename(ACTIVE_RIDES_JSON_PATH)} (Live File on Server Disk)

### ⬡ GOOGLE / H3 HEXAGONAL SPATIAL BRAIN & LIVE PROXIMITY REPORT:
{hex_brief}

### OFFICIAL APP KNOWLEDGE BASE & TUTORIAL:
{knowledge_base}

### LIVE ACTIVE POSTED RIDES (READ DIRECTLY FROM active_rides_data.json):
{rides_summary}

### LIVE ACTIVE OPEN PASSENGER REQUESTS:
{requests_summary}

### LIVE CAMPUS COMMUNITY UPDATES & FEED POSTS:
{feed_summary}

### INSTRUCTIONS FOR MATCHING & RESPONSE:
1. Always greet {user_name} with brotherly/sisterly affection, honor, and warm cordiality (e.g., 'আসসালামু আলাইকুম {user_name} ভাইয়া/আপু! 🌸').
2. Carefully inspect the ⬡ GOOGLE / H3 HEXAGONAL SPATIAL BRAIN & LIVE PROXIMITY REPORT above.
3. Suggest the nearest biker to the student's target ({target_name}), noting their Hexagon Proximity tier (🎯 Exact Hexagon Match or ⬡ Adjacent Hex Neighbor) and distance in meters.
4. Always inform the student of their closest designated Campus/Highway Dropping Zone ({nearest_drop_zone['zone_name']}) and estimated walking time (~{nearest_drop_zone['walk_minutes']} mins).
5. Mention the biker's name, department, bike model, departure time, fare, and available seats.
6. If no posted ride matches, warmly recommend tapping 'Schedule / Throw request' so passing bikers can accept them.
7. If they are a Biker looking for passengers, check the LIVE ACTIVE OPEN PASSENGER REQUESTS and recommend matching students.
8. Maintain brotherly warmth, politeness, and university community solidarity.
"""

    # Build messages sequence
    messages = [{"role": "system", "content": composed_system_prompt}]

    # Include recent chat history (up to last 6 messages)
    if isinstance(history, list):
        for h in history[-6:]:
            r = h.get("role")
            c = h.get("content")
            if r in ("user", "assistant") and c:
                messages.append({"role": r, "content": str(c)})

    # Append current message
    messages.append({"role": "user", "content": message})

    reply = ""
    used_model = primary_model
    models_to_try = [primary_model] + [m for m in FALLBACK_MODELS if m != primary_model]
    last_error = None

    for m in models_to_try:
        try:
            reply = call_groq_chat(api_key, m, messages)
            if reply and reply.strip():
                used_model = m
                break
        except Exception as e:
            last_error = e
            print(f"[GROQ CHAT ATTEMPT FAILED] Model: {m}, Error: {e}")

    # Build rich interactive UI cards for matched rides
    matched_rides = []
    matched_requests = []
    normalized_msg = normalize_bangla_query(message)
    lower_msg = message.lower() + " " + normalized_msg

    # Prioritize hexagonal spatial ranked bikers
    candidate_bikers = ranked_hex_bikers if ranked_hex_bikers else active_rides
    for r in candidate_bikers:
        matched_rides.append({
            "id": r["id"],
            "driver_id": r["driver_id"],
            "driver_name": r["driver_name"],
            "driver_dept": r.get("driver_dept", "Student"),
            "driver_phone": r.get("driver_phone", ""),
            "driver_rating": r.get("driver_rating", 5.0),
            "origin_name": r["origin_name"],
            "origin_lat": r.get("origin_lat", 23.8765),
            "origin_lng": r.get("origin_lng", 90.3204),
            "destination_name": r["destination_name"],
            "destination_lat": r.get("destination_lat", 23.8728),
            "destination_lng": r.get("destination_lng", 90.3984),
            "departure_time": r.get("departure_time_formatted") or r.get("departure_time"),
            "raw_departure_time": r.get("departure_time"),
            "fare_per_seat": r.get("fare_per_seat", 50.0),
            "available_seats": r.get("available_seats", 1),
            "total_seats": r.get("total_seats", 1),
            "vehicle_model": r.get("vehicle_model", "Motorbike"),
            "vehicle_plate": r.get("vehicle_plate", ""),
            "route_corridor": r.get("route_corridor", "Campus Highway"),
            "is_female_only": r.get("is_female_only", False),
            "hex_badge": r.get("hex_badge", "⬡ Spatial Proximity"),
            "hex_match_type": r.get("hex_match_type", "Hex Proximity"),
            "spatial_score": r.get("spatial_score", 92),
            "distance_to_target_meters": r.get("distance_to_target_meters", 450),
            "nearest_dropping_zone": r.get("nearest_dropping_zone", nearest_drop_zone["zone_name"]),
            "dropping_zone_id": r.get("dropping_zone_id", nearest_drop_zone["zone_id"]),
            "dropping_zone_walk_mins": r.get("dropping_zone_walk_mins", nearest_drop_zone["walk_minutes"]),
            "passenger_target_drop_zone": r.get("passenger_target_drop_zone", nearest_drop_zone["zone_name"]),
        })
        if len(matched_rides) >= 4:
            break

    # If all models failed or offline, generate an intelligent, live file-backed fallback response
    if not reply or not reply.strip():
        print(f"[GROQ CHAT ALL FAILED] Last error: {last_error}")
        if matched_rides and user_role != "rider":
            top_rides_lines = []
            for r in matched_rides[:3]:
                female_txt = " (মহিলাদের জন্য সংরক্ষিত)" if r.get("is_female_only") else ""
                top_rides_lines.append(
                    f"• **{r['origin_name']} ➔ {r['destination_name']}**\n"
                    f"  রাইডার: {r['driver_name']} ({r.get('vehicle_model', 'বাইক')}) | সময়: {r['departure_time']} | ভাড়া: ৳{r['fare_per_seat']:.0f} (সিট: {r['available_seats']}টি ফাঁকা){female_txt}\n"
                    f"  {r.get('hex_badge', '⬡ Hexagon Match')} • ড্রপিং জোন: {r.get('nearest_dropping_zone', 'ক্যাম্পাস')} (~{r.get('dropping_zone_walk_mins', 2)} মিনিট হাঁটা)"
                )
            top_rides = "\n\n".join(top_rides_lines)
            reply = (
                f"আসসালামু আলাইকুম {user_name} ভাইয়া/আপু! 🌸\n\n"
                f"গুগল হেক্সাগন (H3 Spatial Proximity) সিস্টেম অনুযায়ী আপনার গন্তব্য `{target_name}` এর সবচেয়ে কাছের রাইডসমূহ:\n\n"
                f"📍 **নিকটবর্তী ড্রপিং জোন:** {nearest_drop_zone['zone_name']} ({nearest_drop_zone['zone_subtitle']})\n"
                f"হাঁটার দূরত্ব: {nearest_drop_zone['distance_m']} মিটার (~{nearest_drop_zone['walk_minutes']} মিনিট হাঁটার পথ)\n\n"
                f"{top_rides}\n\n"
                f"আপনি নিচের কার্ড থেকে সরাসরি **'বুক করুন'** বাটনে ট্যাপ করে সিট রিজার্ভ করতে পারেন।"
            )
        elif active_rides and user_role != "rider":
            top_rides = "\n".join([f"• {r['origin_name']} ➔ {r['destination_name']} (সময়: {r['departure_time_formatted']}, চালক: {r['driver_name']}, ভাড়া: ৳{r['fare_per_seat']:.0f})" for r in active_rides[:3]])
            reply = (
                f"আসসালামু আলাইকুম {user_name} ভাইয়া/আপু! 🌸\n\n"
                f"বর্তমানে সিস্টেমে এই রাইডগুলো সক্রিয় রয়েছে:\n\n{top_rides}\n\n"
                f"আপনার সুবিধাজনক রুট ও সময়ের জন্য হোমস্ক্রিন ব্যবহার করুন অথবা 'Schedule' অপশনে রিকোয়েস্ট পোস্ট করুন।"
            )
        else:
            reply = (
                f"আসসালামু আলাইকুম {user_name} ভাইয়া/আপু! 🌸 আপনার সাথে যুক্ত হতে পেরে আমি অত্যন্ত আনন্দিত।\n\n"
                f"বর্তমানে আমাদের সিস্টেমে আপনার কাঙ্ক্ষিত রুটে কোনো সক্রিয় রাইড পোস্ট করা নেই। "
                f"আপনি অ্যাপের হোমপেইজ থেকে **'Schedule / Throw Request'** অপশনে আপনার রুট ও সময় পোস্ট করে রাখুন, "
                f"যাতে কোনো বাইকার ভাইয়া বা সহপাঠী ক্যাম্পাসে যাওয়ার পথে আপনার রিকোয়েস্ট গ্রহণ করতে পারেন।"
            )

    if active_requests and user_role == "rider":
        for q in active_requests:
            pickup = (q.get("pickup") or "").lower()
            dropoff = (q.get("dropoff") or "").lower()
            if any(term in lower_msg for term in ["passenger", "request", "iatri", "student", "all", "sob"]) or \
               any(k in lower_msg for k in pickup.split() if len(k) > 2) or \
               any(k in lower_msg for k in dropoff.split() if len(k) > 2):
                matched_requests.append(q)
                if len(matched_requests) >= 3:
                    break

    return {
        "status": "success",
        "reply": reply,
        "model": used_model,
        "matched_rides": matched_rides,
        "matched_requests": matched_requests,
        "nearest_dropping_zone": nearest_drop_zone,
        "target_location": {
            "name": target_name,
            "lat": target_lat,
            "lng": target_lng,
            "h3_index": lat_lng_to_hex8(target_lat, target_lng),
        },
        "active_rides_file": os.path.basename(ACTIVE_RIDES_JSON_PATH),
        "total_active_rides_in_file": len(active_rides),
    }
