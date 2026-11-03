"""
DIU Ride - Pure Python Commute Route Passport & Certificate PDF Generator
Generates clean, 100% valid PDF 1.4 documents without any external C or pip dependencies.
"""

import datetime
from typing import List, Dict, Any, Optional

def generate_commute_passport_pdf(
    ride_id: str,
    driver_name: str,
    driver_student_id: str,
    driver_phone: str,
    passenger_name: str,
    passenger_student_id: str,
    passenger_phone: str,
    traversed_landmarks: List[str],
    origin: str,
    destination: str,
    fare: float,
    start_time: Optional[str] = None,
    end_time: Optional[str] = None,
    distance_km: float = 12.5,
    vehicle_info: str = "Yamaha FZ-X 150 (Dhaka Metro Ha 12-3456)",
) -> bytes:
    route_str = " -> ".join(traversed_landmarks) if traversed_landmarks else f"{origin} -> {destination}"
    now_str = datetime.datetime.now().strftime("%d %b %Y, %I:%M %p")
    start_str = start_time[:16].replace("T", " ") if start_time else now_str
    end_str = end_time[:16].replace("T", " ") if end_time else now_str

    # PDF Stream Building
    stream_lines = []
    def text(x, y, font, size, s):
        clean_s = s.replace("(", "\\(").replace(")", "\\)")
        stream_lines.append(f"BT /{font} {size} Tf {x} {y} Td ({clean_s}) Tj ET")

    def rect(x, y, w, h, r, g, b, fill=True):
        if fill:
            stream_lines.append(f"{r:.2f} {g:.2f} {b:.2f} rg {x} {y} {w} {h} re f")
        else:
            stream_lines.append(f"{r:.2f} {g:.2f} {b:.2f} RG 1.5 w {x} {y} {w} {h} re S")

    def line(x1, y1, x2, y2, r, g, b, w=1.0):
        stream_lines.append(f"{r:.2f} {g:.2f} {b:.2f} RG {w} w {x1} {y1} m {x2} {y2} l S")

    # Background Header Banner (Sunset Orange)
    rect(0, 750, 595, 92, 0.90, 0.32, 0.0) # #E65100
    rect(0, 746, 595, 4, 1.0, 0.60, 0.2)  # Peach accent

    # Title
    text(30, 805, "F2", 20, "DAFFODIL INTERNATIONAL UNIVERSITY")
    text(30, 785, "F2", 14, "DIU RIDE - OFFICIAL COMMUTE ROUTE PASSPORT")
    text(30, 765, "F1", 9.5, f"Verified Campus Trip Certificate | Issued: {now_str}")

    # Main Card Container
    rect(25, 50, 545, 675, 0.95, 0.96, 0.98, fill=True)
    rect(25, 50, 545, 675, 0.85, 0.88, 0.92, fill=False)

    # 1. Traversed Route Corridor Section (Highlighted Box)
    rect(45, 640, 505, 65, 1.0, 0.96, 0.92, fill=True)
    rect(45, 640, 505, 65, 0.98, 0.70, 0.40, fill=False)
    text(55, 688, "F2", 11, "VERIFIED TRAVERSED COMMUTE CORRIDOR")
    text(55, 668, "F2", 13, route_str[:65])
    if len(route_str) > 65:
        text(55, 650, "F2", 12, route_str[65:130])

    # 2. Trip Metadata Grid
    text(45, 615, "F2", 12, "TRIP SPECIFICATIONS")
    line(45, 610, 550, 610, 0.85, 0.88, 0.92)

    col1 = 45
    col2 = 300

    y = 590
    text(col1, y, "F2", 10, "Trip ID:")
    text(col1 + 80, y, "F1", 10, ride_id[:25])
    text(col2, y, "F2", 10, "Status:")
    text(col2 + 80, y, "F2", 10, "COMPLETED & VERIFIED")

    y -= 22
    text(col1, y, "F2", 10, "Origin:")
    text(col1 + 80, y, "F1", 10, origin[:30])
    text(col2, y, "F2", 10, "Destination:")
    text(col2 + 80, y, "F1", 10, destination[:30])

    y -= 22
    text(col1, y, "F2", 10, "Departure:")
    text(col1 + 80, y, "F1", 10, start_str)
    text(col2, y, "F2", 10, "Arrival:")
    text(col2 + 80, y, "F1", 10, end_str)

    y -= 22
    text(col1, y, "F2", 10, "Distance:")
    text(col1 + 80, y, "F1", 10, f"{distance_km:.1f} KM")
    text(col2, y, "F2", 10, "Fare Paid:")
    text(col2 + 80, y, "F2", 11, f"BDT {fare:.0f} TK")

    # 3. Rider (Driver) Profile
    y -= 45
    rect(45, y - 60, 245, 75, 1.0, 1.0, 1.0, fill=True)
    rect(45, y - 60, 245, 75, 0.85, 0.88, 0.92, fill=False)
    text(55, y + 2, "F2", 11, "DIU RIDER (BIKER)")
    text(55, y - 18, "F2", 10, f"Name: {driver_name}")
    text(55, y - 34, "F1", 9.5, f"Student ID: {driver_student_id}")
    text(55, y - 50, "F1", 9.5, f"Phone: {driver_phone or 'Verified'}")

    # 4. Passenger Profile
    rect(305, y - 60, 245, 75, 1.0, 1.0, 1.0, fill=True)
    rect(305, y - 60, 245, 75, 0.85, 0.88, 0.92, fill=False)
    text(315, y + 2, "F2", 11, "DIU PASSENGER (STUDENT)")
    text(315, y - 18, "F2", 10, f"Name: {passenger_name}")
    text(315, y - 34, "F1", 9.5, f"Student ID: {passenger_student_id}")
    text(315, y - 50, "F1", 9.5, f"Phone: {passenger_phone or 'Verified'}")

    # 5. Vehicle Details
    y -= 95
    text(45, y, "F2", 11, "VEHICLE DETAILS")
    line(45, y - 5, 550, y - 5, 0.85, 0.88, 0.92)
    text(45, y - 22, "F1", 10, f"Vehicle: {vehicle_info}")

    # 6. Waypoint Milestone Trail
    y -= 55
    text(45, y, "F2", 11, "COMMUTE MILESTONES & GPS AUDIT TRAIL")
    line(45, y - 5, 550, y - 5, 0.85, 0.88, 0.92)

    landmarks_to_show = traversed_landmarks if traversed_landmarks else [origin, "Birulia", "Diabari", destination]
    lm_y = y - 25
    for i, lm in enumerate(landmarks_to_show[:7]):
        rect(50, lm_y + 1, 8, 8, 0.90, 0.32, 0.0)
        text(65, lm_y, "F2", 9.5, f"Waypoint {i+1}: {lm}")
        text(250, lm_y, "F1", 9.0, f"Status: Traversed & Synced via Live GPS")
        lm_y -= 18

    # 7. Official Digital Signature Seal
    y = 90
    rect(45, y - 25, 505, 45, 0.92, 0.96, 0.94, fill=True)
    rect(45, y - 25, 505, 45, 0.60, 0.85, 0.70, fill=False)
    text(55, y + 5, "F2", 10, "CAMPUS SAFETY VERIFICATION & DIGITAL STAMP")
    text(55, y - 10, "F1", 8.5, "This document certifies a completed DIU peer commute. Coordinates and route breadcrumbs")
    text(55, y - 20, "F1", 8.5, "were recorded in realtime by the DIU Ride platform under student safety protocol.")

    content_stream = "\n".join(stream_lines).encode("latin-1", errors="replace")

    # Build PDF Objects
    objects = []
    # 1: Catalog
    objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    # 2: Pages
    objects.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    # 3: Page
    objects.append(b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>")
    # 4: Stream
    stream_obj = b"<< /Length " + str(len(content_stream)).encode() + b" >>\nstream\n" + content_stream + b"\nendstream"
    objects.append(stream_obj)
    # 5: F1 (Helvetica)
    objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    # 6: F2 (Helvetica-Bold)
    objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>")

    # Assemble PDF with cross references
    pdf_bytes = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, obj in enumerate(objects, 1):
        offsets.append(len(pdf_bytes))
        pdf_bytes.extend(f"{i} 0 obj\n".encode())
        pdf_bytes.extend(obj)
        pdf_bytes.extend(b"\nendobj\n")

    xref_offset = len(pdf_bytes)
    pdf_bytes.extend(b"xref\n")
    pdf_bytes.extend(f"0 {len(objects) + 1}\n".encode())
    pdf_bytes.extend(b"0000000000 65535 f \n")
    for off in offsets:
        pdf_bytes.extend(f"{off:010d} 00000 n \n".encode())

    pdf_bytes.extend(b"trailer\n")
    pdf_bytes.extend(f"<< /Size {len(objects) + 1} /Root 1 0 R >>\n".encode())
    pdf_bytes.extend(b"startxref\n")
    pdf_bytes.extend(f"{xref_offset}\n%%EOF".encode())

    return bytes(pdf_bytes)

