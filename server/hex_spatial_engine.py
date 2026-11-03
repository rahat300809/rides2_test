import math
from typing import Dict, Any, List, Optional, Tuple

# Official DIU Campus & Key Dhaka Commute Dropping Zones with Hexagonal Resolution 8 Indices
DROPPING_ZONES = [
    {
        "id": "diu_gate_1",
        "name": "DIU Main Gate 1",
        "subtitle": "Daffodil Smart City, Ashulia",
        "lat": 23.8775,
        "lng": 90.3201,
        "h3_index": "88654c6001fffff",
        "category": "campus",
        "description": "Main entrance, central bike parking and bus bay",
    },
    {
        "id": "diu_gate_2",
        "name": "DIU Gate 2 (Engineering Complex)",
        "subtitle": "DSC East Wing",
        "lat": 23.8790,
        "lng": 90.3215,
        "h3_index": "88654c6001fffff",
        "category": "campus",
        "description": "Drop point for Engineering & Science faculties",
    },
    {
        "id": "diu_ab_4",
        "name": "Academic Building 4 (Daffodil Tower)",
        "subtitle": "DSC Central Circle",
        "lat": 23.8781,
        "lng": 90.3215,
        "h3_index": "88654c6001fffff",
        "category": "campus",
        "description": "CSE, Software Engineering & Tech Depts zone",
    },
    {
        "id": "diu_lake_bridge",
        "name": "Campus Lake Bridge & Cafeteria",
        "subtitle": "Lakeside Student Hangout",
        "lat": 23.8755,
        "lng": 90.3220,
        "h3_index": "88654c6001fffff",
        "category": "campus",
        "description": "Food court, cafe and hostel connector",
    },
    {
        "id": "diu_bus_bay",
        "name": "Transport Terminal & Bus Bay",
        "subtitle": "Behind Academic Bldg 1, DSC",
        "lat": 23.8762,
        "lng": 90.3195,
        "h3_index": "88654c6001fffff",
        "category": "campus",
        "description": "Campus shuttle stop and biker pickup stand",
    },
    {
        "id": "birulia_bridge",
        "name": "Birulia Bridge Crossing",
        "subtitle": "Birulia - Ashulia Highway Link",
        "lat": 23.8685,
        "lng": 90.3340,
        "h3_index": "88654c6009fffff",
        "category": "corridor",
        "description": "Major highway junction to Mirpur and Savar",
    },
    {
        "id": "dest_uttara_metro",
        "name": "Uttara North Metro Station (Diabari)",
        "subtitle": "Exit Gate 2, Metro Rail Line 6",
        "lat": 23.8710,
        "lng": 90.3800,
        "h3_index": "88654c6225fffff",
        "category": "metro",
        "description": "Direct connectivity to Motijheel & Agargaon via Metro",
    },
    {
        "id": "dest_uttara_house_building",
        "name": "Uttara House Building (Sector 7/9)",
        "subtitle": "Dhaka - Mymensingh Highway Overbridge",
        "lat": 23.8735,
        "lng": 90.3985,
        "h3_index": "88654c622dfffff",
        "category": "city",
        "description": "Key hub for Uttara East/West commuters",
    },
    {
        "id": "dest_mirpur_10",
        "name": "Mirpur 10 Roundabout (Metro Hub)",
        "subtitle": "Metro Pillar 240, Mirpur Central",
        "lat": 23.8069,
        "lng": 90.3687,
        "h3_index": "88654c628bfffff",
        "category": "metro",
        "description": "Primary bike drop-off point for Mirpur students",
    },
    {
        "id": "dest_ecb",
        "name": "ECB Chattar (Matikata Road)",
        "subtitle": "Mirpur DOHS & Cantonment Flyover",
        "lat": 23.8225,
        "lng": 90.3934,
        "h3_index": "88654c6211fffff",
        "category": "city",
        "description": "Gateway to Airport Road, Kuril and DOHS",
    },
    {
        "id": "dest_dhanmondi",
        "name": "Dhanmondi Campus (Sobhanbag)",
        "subtitle": "Mirpur Road, Dhanmondi 27",
        "lat": 23.7538,
        "lng": 90.3768,
        "h3_index": "88654c6533fffff",
        "category": "campus",
        "description": "DIU Old Campus & Dhanmondi commuter zone",
    },
    {
        "id": "dest_savar",
        "name": "Savar Bazar Bus Stand",
        "subtitle": "Aricha Highway Overbridge",
        "lat": 23.8488,
        "lng": 90.2575,
        "h3_index": "88654c60b7fffff",
        "category": "city",
        "description": "West Dhaka & Jahangirnagar University corridor",
    },
]

def haversine_distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculates great-circle distance between two GPS coordinates in kilometers."""
    p = 0.017453292519943295  # pi / 180
    a = (
        0.5
        - math.cos((lat2 - lat1) * p) / 2
        + math.cos(lat1 * p)
        * math.cos(lat2 * p)
        * (1 - math.cos((lon2 - lon1) * p))
        / 2
    )
    return 12742 * math.asin(math.sqrt(max(0.0, min(1.0, a))))

def haversine_distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> int:
    return int(round(haversine_distance_km(lat1, lon1, lat2, lon2) * 1000))

def lat_lng_to_hex8(lat: float, lng: float) -> str:
    """
    Deterministic resolution-8 hexagonal cell representation (~460m grid cell).
    Matches mobile client's H3Utils quantization.
    """
    lat_q = int(round(lat * 1000))
    lng_q = int(round(lng * 1000))
    return f"88654c{abs(lat_q) % 1000:03d}{abs(lng_q) % 1000:03d}fffff"

def find_nearest_dropping_zone(lat: float, lng: float, preferred_category: Optional[str] = None) -> Dict[str, Any]:
    """
    Finds the closest designated dropping zone to any given coordinate
    and estimates walking distance and duration.
    """
    best_zone = None
    min_dist_m = float("inf")

    candidates = DROPPING_ZONES
    if preferred_category:
        filtered = [z for z in DROPPING_ZONES if z.get("category") == preferred_category]
        if filtered:
            candidates = filtered

    for zone in candidates:
        dist_m = haversine_distance_m(lat, lng, zone["lat"], zone["lng"])
        if dist_m < min_dist_m:
            min_dist_m = dist_m
            best_zone = zone

    if not best_zone:
        best_zone = DROPPING_ZONES[0]
        min_dist_m = haversine_distance_m(lat, lng, best_zone["lat"], best_zone["lng"])

    # Average walking speed ~ 4.8 km/h = 80 meters/min
    walk_mins = max(1, int(round(min_dist_m / 80)))

    return {
        "zone_id": best_zone["id"],
        "zone_name": best_zone["name"],
        "zone_subtitle": best_zone["subtitle"],
        "zone_lat": best_zone["lat"],
        "zone_lng": best_zone["lng"],
        "h3_index": best_zone["h3_index"],
        "distance_m": min_dist_m,
        "walk_minutes": walk_mins,
        "description": best_zone["description"],
    }

def rank_bikers_by_hex_spatial_proximity(
    active_rides: List[Dict[str, Any]],
    target_lat: float,
    target_lng: float,
    target_name: str = "",
    is_destination_search: bool = True,
) -> List[Dict[str, Any]]:
    """
    Ranks active biker rides using Hexagonal Spatial Proximity:
    1. Exact Hex Cell Match (Resolution 8: <= 500m): 98-100% Match
    2. Adjacent Hex Cell Neighbor (k-ring 1: <= 1.5km): 85-95% Match
    3. Corridor Chain Match (<= 3.5km): 70-84% Match
    4. General Campus Match (> 3.5km): Distance-weighted Score
    """
    scored_rides = []
    target_hex = lat_lng_to_hex8(target_lat, target_lng)
    nearest_drop_zone = find_nearest_dropping_zone(target_lat, target_lng)

    for ride in active_rides:
        # Determine comparison coordinates
        if is_destination_search:
            ride_lat = float(ride.get("destination_lat") or ride.get("destinationLat") or 23.8765)
            ride_lng = float(ride.get("destination_lng") or ride.get("destinationLng") or 90.3204)
            ride_loc_name = str(ride.get("destination_name") or ride.get("destinationName") or "")
        else:
            ride_lat = float(ride.get("origin_lat") or ride.get("originLat") or 23.8765)
            ride_lng = float(ride.get("origin_lng") or ride.get("originLng") or 90.3204)
            ride_loc_name = str(ride.get("origin_name") or ride.get("originName") or "")

        ride_hex = ride.get("h3_destination_index") or ride.get("h3DestinationIndex") or lat_lng_to_hex8(ride_lat, ride_lng)
        dist_m = haversine_distance_m(target_lat, target_lng, ride_lat, ride_lng)

        # Calculate spatial score & category
        if dist_m <= 500:
            match_tier = "Exact Hex Cell Match"
            score = max(95, int(100 - (dist_m / 500.0) * 5))
            badge = "🎯 Exact Hexagon Match"
        elif dist_m <= 1500:
            match_tier = "Adjacent Hex Neighbor (k-ring 1)"
            score = max(82, int(94 - ((dist_m - 500) / 1000.0) * 12))
            badge = f"⬡ Adjacent Hex ({dist_m}m)"
        elif dist_m <= 3500:
            match_tier = "Corridor Chain Match"
            score = max(68, int(81 - ((dist_m - 1500) / 2000.0) * 13))
            badge = f"🛣️ Corridor Match ({dist_m/1000.0:.1f}km)"
        else:
            match_tier = "Extended Commute Reach"
            score = max(40, int(67 - min(30, (dist_m - 3500) / 500.0)))
            badge = f"📍 Far Route ({dist_m/1000.0:.1f}km)"

        # Boost score if target text name matches ride location
        if target_name and target_name.lower() in ride_loc_name.lower():
            score = min(100, score + 10)

        # Drop-off zone evaluation for this biker
        biker_drop_zone = find_nearest_dropping_zone(ride_lat, ride_lng)

        item = dict(ride)
        item.update({
            "hex_target_cell": target_hex,
            "hex_ride_cell": ride_hex,
            "hex_match_type": match_tier,
            "hex_badge": badge,
            "spatial_score": score,
            "distance_to_target_meters": dist_m,
            "nearest_dropping_zone": biker_drop_zone["zone_name"],
            "dropping_zone_id": biker_drop_zone["zone_id"],
            "dropping_zone_walk_mins": biker_drop_zone["walk_minutes"],
            "passenger_target_drop_zone": nearest_drop_zone["zone_name"],
        })
        scored_rides.append(item)

    # Sort descending by spatial score
    scored_rides.sort(key=lambda x: (x["spatial_score"], -x["distance_to_target_meters"]), reverse=True)
    return scored_rides

# Common Landmark Coordinate Dictionary for DIU Commute Network
LANDMARK_COORDINATES: Dict[str, Tuple[float, float, str]] = {
    # Campus locations
    "gate 1": (23.8775, 90.3201, "DIU Main Gate 1"),
    "গেট ১": (23.8775, 90.3201, "DIU Main Gate 1"),
    "gate 2": (23.8790, 90.3215, "DIU Gate 2 (Engineering Complex)"),
    "গেট ২": (23.8790, 90.3215, "DIU Gate 2 (Engineering Complex)"),
    "ab4": (23.8781, 90.3215, "Academic Building 4 (Daffodil Tower)"),
    "ab-4": (23.8781, 90.3215, "Academic Building 4 (Daffodil Tower)"),
    "এবি ৪": (23.8781, 90.3215, "Academic Building 4 (Daffodil Tower)"),
    "এবি-৪": (23.8781, 90.3215, "Academic Building 4 (Daffodil Tower)"),
    "lake bridge": (23.8755, 90.3220, "Campus Lake Bridge & Cafeteria"),
    "লেক ব্রিজ": (23.8755, 90.3220, "Campus Lake Bridge & Cafeteria"),
    "cafeteria": (23.8755, 90.3220, "Campus Lake Bridge & Cafeteria"),
    "ক্যাফেটেরিয়া": (23.8755, 90.3220, "Campus Lake Bridge & Cafeteria"),
    "bus bay": (23.8762, 90.3195, "Transport Terminal & Bus Bay"),
    "বাস বে": (23.8762, 90.3195, "Transport Terminal & Bus Bay"),
    "dsc": (23.8775, 90.3201, "Daffodil Smart City"),
    "ডিএসসি": (23.8775, 90.3201, "Daffodil Smart City"),
    "campus": (23.8775, 90.3201, "DIU Smart City Campus"),
    "ক্যাম্পাস": (23.8775, 90.3201, "DIU Smart City Campus"),
    "smart city": (23.8775, 90.3201, "Daffodil Smart City"),
    "স্মার্ট সিটি": (23.8775, 90.3201, "Daffodil Smart City"),

    # Commute corridors & Dhaka destinations
    "mirpur 10": (23.8069, 90.3687, "Mirpur 10 Roundabout (Metro Hub)"),
    "মিরপুর ১০": (23.8069, 90.3687, "Mirpur 10 Roundabout (Metro Hub)"),
    "mirpur-10": (23.8069, 90.3687, "Mirpur 10 Roundabout (Metro Hub)"),
    "mirpur": (23.8069, 90.3687, "Mirpur 10 Roundabout (Metro Hub)"),
    "মিরপুর": (23.8069, 90.3687, "Mirpur 10 Roundabout (Metro Hub)"),
    "uttara metro": (23.8710, 90.3800, "Uttara North Metro Station (Diabari)"),
    "উত্তরা মেট্রো": (23.8710, 90.3800, "Uttara North Metro Station (Diabari)"),
    "diabari": (23.8710, 90.3800, "Uttara North Metro Station (Diabari)"),
    "দিয়াবাড়ী": (23.8710, 90.3800, "Uttara North Metro Station (Diabari)"),
    "দিয়াবাড়ি": (23.8710, 90.3800, "Uttara North Metro Station (Diabari)"),
    "house building": (23.8735, 90.3985, "Uttara House Building (Sector 7/9)"),
    "হাউজ বিল্ডিং": (23.8735, 90.3985, "Uttara House Building (Sector 7/9)"),
    "uttara": (23.8735, 90.3985, "Uttara House Building (Sector 7/9)"),
    "উত্তরা": (23.8735, 90.3985, "Uttara House Building (Sector 7/9)"),
    "ecb": (23.8225, 90.3934, "ECB Chattar (Matikata Road)"),
    "ইসিবি": (23.8225, 90.3934, "ECB Chattar (Matikata Road)"),
    "ecb chattar": (23.8225, 90.3934, "ECB Chattar (Matikata Road)"),
    "dhanmondi": (23.7538, 90.3768, "Dhanmondi Campus (Sobhanbag)"),
    "ধানমন্ডি": (23.7538, 90.3768, "Dhanmondi Campus (Sobhanbag)"),
    "sobhanbag": (23.7538, 90.3768, "Dhanmondi Campus (Sobhanbag)"),
    "শোভনবাগ": (23.7538, 90.3768, "Dhanmondi Campus (Sobhanbag)"),
    "savar": (23.8488, 90.2575, "Savar Bazar Bus Stand"),
    "সাভার": (23.8488, 90.2575, "Savar Bazar Bus Stand"),
    "birulia": (23.8685, 90.3340, "Birulia Bridge Crossing"),
    "বিরুলিয়া": (23.8685, 90.3340, "Birulia Bridge Crossing"),
    "বিরুলিয়া": (23.8685, 90.3340, "Birulia Bridge Crossing"),
    "ashulia": (23.8775, 90.3201, "DIU Main Gate 1 (Ashulia)"),
    "আশুলিয়া": (23.8775, 90.3201, "DIU Main Gate 1 (Ashulia)"),
    "আশুলিয়া": (23.8775, 90.3201, "DIU Main Gate 1 (Ashulia)"),
}

def resolve_target_from_text(
    text: str,
    fallback_lat: float = 23.8775,
    fallback_lng: float = 90.3201,
    fallback_name: str = "Daffodil Smart City (Main Gate 1)"
) -> Tuple[float, float, str]:
    """
    Scans a user query or route string to identify coordinates and landmark name.
    Matches longest phrases first to accurately resolve 'mirpur 10' over 'mirpur'.
    """
    clean_text = text.lower()
    # Sort keys by length descending
    sorted_keys = sorted(LANDMARK_COORDINATES.keys(), key=lambda k: len(k), reverse=True)
    for k in sorted_keys:
        if k in clean_text:
            lat, lng, name = LANDMARK_COORDINATES[k]
            return (lat, lng, name)
    return (fallback_lat, fallback_lng, fallback_name)

def format_hex_spatial_brief_for_ai(
    ranked_bikers: List[Dict[str, Any]],
    target_name: str,
    target_lat: float,
    target_lng: float,
    nearest_drop_zone: Dict[str, Any],
) -> str:
    """
    Generates a concise, structured Hexagonal Spatial Intelligence summary
    specifically formatted for Groq AI reasoning.
    """
    target_hex = lat_lng_to_hex8(target_lat, target_lng)
    lines = [
        f"• Passenger Target Destination: {target_name} (Coordinates: {target_lat:.4f}, {target_lng:.4f} | Hex Cell: {target_hex})",
        f"• Nearest Designated Dropping Zone: {nearest_drop_zone['zone_name']} ({nearest_drop_zone['zone_subtitle']})",
        f"  - Walking distance from destination: {nearest_drop_zone['distance_m']}m (~{nearest_drop_zone['walk_minutes']} min walk)",
        f"  - Dropping Zone Perks: {nearest_drop_zone['description']}",
        "",
        "• Live Bikers Ranked by Hexagonal Spatial Proximity (Uber/Google H3 Grid Proximity):",
    ]
    if not ranked_bikers:
        lines.append("  (No active biker rides found matching this corridor at this moment)")
    else:
        for i, b in enumerate(ranked_bikers[:6], 1):
            female_badge = " [মহিলাদের জন্য সংরক্ষিত]" if b.get("is_female_only") else ""
            lines.append(
                f"  {i}. {b['driver_name']} ({b.get('vehicle_model') or 'Bike'}){female_badge} | "
                f"Proximity Match: {b['hex_badge']} (Score: {b['spatial_score']}/100) | "
                f"Distance to Target: {b['distance_to_target_meters']}m | "
                f"Route: {b['origin_name']} ➔ {b['destination_name']} | "
                f"Departure Time: {b.get('departure_time_formatted') or b.get('departure_time')} | "
                f"Fare: ৳{float(b.get('fare_per_seat') or 50):.0f} | Seats: {b.get('available_seats', 1)} | "
                f"Dropping Zone: {b['nearest_dropping_zone']} (~{b['dropping_zone_walk_mins']} min walk)"
            )
    return "\n".join(lines)
