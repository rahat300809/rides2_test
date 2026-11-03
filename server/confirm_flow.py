"""
Multi-interest confirm orchestration:
- Many students/bikers can chat about the same post
- Mutual confirm locks the post and notifies losers
- One-sided confirm gets 3 reminders every 2 minutes, then auto-suspend
"""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Callable, Awaitable

CONFIRM_REMINDER_INTERVAL_SEC = 120  # 2 minutes
CONFIRM_REMINDER_MAX = 3

# Injected from main.py after manager / helpers exist
_get_db = None
_manager = None
_save_and_broadcast_message = None
_get_current_bd_time = None
_remove_ride_from_file = None
_map_ride = None


def bind_confirm_flow(
    *,
    get_db,
    manager,
    save_and_broadcast_message,
    get_current_bd_time,
    remove_ride_from_file=None,
    map_ride=None,
):
    global _get_db, _manager, _save_and_broadcast_message
    global _get_current_bd_time, _remove_ride_from_file, _map_ride
    _get_db = get_db
    _manager = manager
    _save_and_broadcast_message = save_and_broadcast_message
    _get_current_bd_time = get_current_bd_time
    _remove_ride_from_file = remove_ride_from_file
    _map_ride = map_ride


def ensure_confirm_columns(cursor):
    for col, c_type in [
        ("confirm_wait_started_at", "TEXT"),
        ("confirm_reminder_count", "INTEGER DEFAULT 0"),
        ("confirm_last_reminded_at", "TEXT"),
        ("pending_confirm_role", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE conversations ADD COLUMN {col} {c_type}")
        except Exception:
            pass
    for col, c_type in [
        ("suspended_at", "TEXT"),
        ("suspend_reason", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE rides ADD COLUMN {col} {c_type}")
        except Exception:
            pass
        try:
            cursor.execute(f"ALTER TABLE passenger_requests ADD COLUMN {col} {c_type}")
        except Exception:
            pass


def mark_one_sided_confirm_wait(cursor, conv_id: str, waiting_for_role: str):
    """waiting_for_role = who still needs to confirm ('rider' or 'passenger')."""
    now = _get_current_bd_time().isoformat()
    cursor.execute(
        """
        UPDATE conversations SET
            confirm_wait_started_at = COALESCE(confirm_wait_started_at, ?),
            confirm_reminder_count = COALESCE(confirm_reminder_count, 0),
            pending_confirm_role = ?,
            session_state = 'awaitingConfirm'
        WHERE id = ?
        """,
        (now, waiting_for_role, conv_id),
    )


def clear_confirm_wait(cursor, conv_id: str):
    cursor.execute(
        """
        UPDATE conversations SET
            confirm_wait_started_at = NULL,
            confirm_reminder_count = 0,
            confirm_last_reminded_at = NULL,
            pending_confirm_role = NULL
        WHERE id = ?
        """,
        (conv_id,),
    )


async def notify_other_parties_after_mutual_confirm(
    *,
    winning_conv_id: str,
    source_post_id: str,
    winner_a: str,
    winner_b: str,
    winner_name: str = "a companion",
):
    """
    After both sides confirm on one chat:
    - hide the public post
    - cancel other chats on same post
    - inbox system SMS to other interested students/bikers
    - reject other bookings on the ride
    """
    if not source_post_id or not _get_db:
        return

    conn = _get_db()
    cursor = conn.cursor()
    now = _get_current_bd_time().isoformat()

    # Lock public post
    cursor.execute(
        """
        UPDATE rides
        SET status = 'occupied', available_seats = 0,
            suspended_at = NULL, suspend_reason = NULL
        WHERE id = ?
        """,
        (source_post_id,),
    )
    cursor.execute(
        """
        UPDATE passenger_requests
        SET status = 'accepted', suspended_at = NULL, suspend_reason = NULL
        WHERE id = ?
        """,
        (source_post_id,),
    )

    # Keep winning booking accepted; reject others on this ride
    cursor.execute(
        """
        UPDATE bookings SET status = 'accepted'
        WHERE ride_id = ? AND status IN ('requested', 'accepted')
          AND (
            LOWER(passenger_id) = LOWER(?) OR LOWER(passenger_id) = LOWER(?)
          )
        """,
        (source_post_id, winner_a, winner_b),
    )
    cursor.execute(
        """
        UPDATE bookings SET status = 'rejected'
        WHERE ride_id = ? AND status IN ('requested', 'accepted')
          AND LOWER(passenger_id) NOT IN (LOWER(?), LOWER(?))
        """,
        (source_post_id, winner_a, winner_b),
    )

    cursor.execute(
        """
        SELECT * FROM conversations
        WHERE source_post_id = ?
          AND id != ?
          AND session_state IN ('awaitingConfirm', 'idle', 'bothConfirmed')
        """,
        (source_post_id, winning_conv_id),
    )
    others = cursor.fetchall()

    loser_ids: List[str] = []
    for row in others:
        oid = row["id"]
        clear_confirm_wait(cursor, oid)
        cursor.execute(
            """
            UPDATE conversations SET
                session_state = 'cancelled',
                canceller_id = 'system',
                cancel_reason = 'Post taken by another companion after mutual confirm',
                rider_confirmed = 0,
                passenger_confirmed = 0
            WHERE id = ?
            """,
            (oid,),
        )
        for uid in (row["user_a_id"], row["user_b_id"]):
            if uid and uid.lower() not in (winner_a.lower(), winner_b.lower()):
                loser_ids.append(uid)

    clear_confirm_wait(cursor, winning_conv_id)
    conn.commit()

    # Notify losers in their chat inboxes
    msg = (
        "⚠️ The rider has accepted another student's offer. "
        "Please try to find a new rider. This chat is now closed for this ride post."
    )
    # For passenger-request posts, wording flips for other bikers
    cursor.execute("SELECT id FROM passenger_requests WHERE id = ?", (source_post_id,))
    if cursor.fetchone():
        msg = (
            "⚠️ This student request was confirmed with another biker. "
            "Please try another student request. This chat is now closed for this post."
        )

    for row in others:
        try:
            await _save_and_broadcast_message(
                row["id"],
                {
                    "rideId": row["id"],
                    "senderId": "system",
                    "senderName": "DIU Ride System",
                    "text": msg,
                    "isLocationShare": False,
                    "timestamp": now,
                },
            )
            await _manager.send_to_pair(
                row["user_a_id"],
                row["user_b_id"],
                "ride_taken_by_other",
                {
                    "conversationId": row["id"],
                    "sourcePostId": source_post_id,
                    "message": msg,
                    "winningConversationId": winning_conv_id,
                },
            )
        except Exception as e:
            print(f"[CONFIRM FLOW] notify other chat error: {e}")

    # Push-style inbox ping to losers
    for uid in set(loser_ids):
        try:
            await _manager.send_to_user(
                uid,
                "push_notification",
                {
                    "title": "Ride taken by another companion",
                    "message": msg,
                    "sourcePostId": source_post_id,
                    "type": "ride_taken_by_other",
                },
            )
        except Exception:
            pass

    try:
        if _remove_ride_from_file:
            _remove_ride_from_file(source_post_id)
    except Exception:
        pass

    await _manager.broadcast(
        "ride_updated",
        {"id": source_post_id, "status": "occupied", "availableSeats": 0},
    )
    conn.close()


async def suspend_post_for_no_confirm(conv_row: Dict[str, Any]):
    """Auto-cancel/suspend public post after 3 unanswered confirm reminders."""
    conn = _get_db()
    cursor = conn.cursor()
    now = _get_current_bd_time().isoformat()
    conv_id = conv_row["id"]
    post_id = conv_row["source_post_id"] or ""
    reason = "Suspended: companion did not confirm after 3 reminders (2 min each)."

    clear_confirm_wait(cursor, conv_id)
    cursor.execute(
        """
        UPDATE conversations SET
            session_state = 'cancelled',
            canceller_id = 'system',
            cancel_reason = ?
        WHERE id = ?
        """,
        (reason, conv_id),
    )

    if post_id:
        cursor.execute(
            """
            UPDATE rides SET
                status = 'suspended',
                available_seats = 0,
                suspended_at = ?,
                suspend_reason = ?
            WHERE id = ?
            """,
            (now, reason, post_id),
        )
        cursor.execute(
            """
            UPDATE passenger_requests SET
                status = 'cancelled',
                suspended_at = ?,
                suspend_reason = ?
            WHERE id = ?
            """,
            (now, reason, post_id),
        )
        cursor.execute(
            """
            UPDATE bookings SET status = 'cancelled'
            WHERE ride_id = ? AND status IN ('requested', 'accepted')
            """,
            (post_id,),
        )

    conn.commit()

    sys_txt = (
        "⛔ Ride auto-cancelled. Confirmation was not completed after 3 reminders. "
        "The post is suspended and no longer visible to other students."
    )
    await _save_and_broadcast_message(
        conv_id,
        {
            "rideId": conv_id,
            "senderId": "system",
            "senderName": "DIU Ride System",
            "text": sys_txt,
            "isLocationShare": False,
            "timestamp": now,
        },
    )

    event = {
        "conversationId": conv_id,
        "sourcePostId": post_id,
        "status": "suspended",
        "reason": reason,
        "message": sys_txt,
    }
    await _manager.send_to_pair(
        conv_row["user_a_id"], conv_row["user_b_id"], "ride_suspended", event
    )
    await _manager.broadcast("ride_updated", {"id": post_id, "status": "suspended"})
    if post_id and _remove_ride_from_file:
        try:
            _remove_ride_from_file(post_id)
        except Exception:
            pass
    conn.close()


async def process_confirm_reminders():
    if not _get_db:
        return
    conn = _get_db()
    cursor = conn.cursor()
    ensure_confirm_columns(cursor)
    conn.commit()

    now = _get_current_bd_time().replace(tzinfo=None)
    cursor.execute(
        """
        SELECT * FROM conversations
        WHERE session_state = 'awaitingConfirm'
          AND (
            (rider_confirmed = 1 AND passenger_confirmed = 0)
            OR (rider_confirmed = 0 AND passenger_confirmed = 1)
          )
          AND confirm_wait_started_at IS NOT NULL
          AND source_post_id IS NOT NULL
          AND TRIM(source_post_id) != ''
        """
    )
    rows = cursor.fetchall()
    to_remind = []
    to_suspend = []

    for row in rows:
        r = dict(row)
        count = int(r.get("confirm_reminder_count") or 0)
        last = r.get("confirm_last_reminded_at") or r.get("confirm_wait_started_at")
        try:
            last_dt = datetime.fromisoformat(str(last).replace("Z", ""))
        except Exception:
            last_dt = now - timedelta(seconds=CONFIRM_REMINDER_INTERVAL_SEC + 1)
        if last_dt.tzinfo is not None:
            last_dt = last_dt.replace(tzinfo=None)

        elapsed = (now - last_dt).total_seconds()
        if elapsed < CONFIRM_REMINDER_INTERVAL_SEC:
            continue

        if count >= CONFIRM_REMINDER_MAX:
            to_suspend.append(r)
        else:
            to_remind.append(r)

    conn.close()

    for r in to_remind:
        await _send_confirm_reminder(r)

    for r in to_suspend:
        await suspend_post_for_no_confirm(r)


async def _send_confirm_reminder(conv_row: Dict[str, Any]):
    conn = _get_db()
    cursor = conn.cursor()
    now = _get_current_bd_time()
    now_iso = now.isoformat()
    count = int(conv_row.get("confirm_reminder_count") or 0) + 1
    pending = (conv_row.get("pending_confirm_role") or "rider").lower()
    conv_id = conv_row["id"]

    cursor.execute(
        """
        UPDATE conversations SET
            confirm_reminder_count = ?,
            confirm_last_reminded_at = ?
        WHERE id = ?
        """,
        (count, now_iso, conv_id),
    )
    conn.commit()

    if pending == "rider":
        target_hint = "biker/rider"
        msg = (
            f"🔔 Reminder {count}/{CONFIRM_REMINDER_MAX}: Your companion confirmed. "
            f"Please confirm this ride within 2 minutes or the post will be suspended."
        )
    else:
        target_hint = "student"
        msg = (
            f"🔔 Reminder {count}/{CONFIRM_REMINDER_MAX}: Your companion confirmed. "
            f"Please confirm this ride within 2 minutes or the post will be cancelled."
        )

    await _save_and_broadcast_message(
        conv_id,
        {
            "rideId": conv_id,
            "senderId": "system",
            "senderName": "DIU Ride System",
            "text": msg,
            "isLocationShare": False,
            "timestamp": now_iso,
        },
    )

    event = {
        "conversationId": conv_id,
        "sourcePostId": conv_row.get("source_post_id"),
        "reminderCount": count,
        "maxReminders": CONFIRM_REMINDER_MAX,
        "pendingRole": pending,
        "message": msg,
        "title": "Confirm ride reminder",
    }
    await _manager.send_to_pair(
        conv_row["user_a_id"], conv_row["user_b_id"], "confirm_reminder", event
    )
    await _manager.broadcast("push_notification", event)
    print(f"[CONFIRM REMINDER] {conv_id} -> {target_hint} #{count}")
    conn.close()


async def periodic_confirm_reminder_task():
    # small delay so server finishes boot
    await asyncio.sleep(15)
    while True:
        try:
            await process_confirm_reminders()
        except Exception as e:
            print(f"[CONFIRM REMINDER TASK ERROR] {e}")
        await asyncio.sleep(30)
