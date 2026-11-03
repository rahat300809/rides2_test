# DIU Ride — Session Updates Log

**Date:** 3–4 Nov 2026  
**Scope:** Local run, Student↔Biker mode isolation, self-accept block, multi-chat confirm flow, confirm timeout, messaging reliability.

---

## 1. Local project run + demo account

- Ran FastAPI backend with Flutter `web_build` on **http://127.0.0.1:8080/ride/**
- Created verified demo student for login:
  - **Student ID:** `221-15-99999`
  - **Password:** `Demo@1234`
  - **Email:** `221-15-99999@diu.edu.bd`

---

## 2. Student ↔ Biker hard mode switch

**Goal:** Switching modes feels like opening a separate app (runtime isolation), without wiping trip/money history.

### Behavior
- Toggle starts a **~12 second** full-screen setup overlay
- Previous mode UI is closed; live caches for the other mode are cleared
- Navigation shell **remounts** (IndexedStack keyed by generation)
- WebSocket handlers are gated by active mode (no cross-mode alerts)
- Account history / payments / earnings stay on the same user account

### Key files
- `lib/core/providers/mode_session_provider.dart`
- `lib/core/utils/mode_switch_controller.dart`
- `lib/shared/widgets/mode_bootstrap_overlay.dart`
- `lib/shared/widgets/liquid_glass_3d_toggle.dart`
- `lib/shared/navigation/main_navigation_screen.dart`

### Bugfix
- Setup stuck at **28%** while invalidating many providers synchronously  
  → remount first, invalidate in microtask, 18s watchdog so overlay never hangs forever

---

## 3. Same-account self-accept block

**Rule:** After mode switch, the same login cannot accept its own student request or book its own biker offer.

### Behavior
- Stronger identity matching (user id / student id / phone tokens)
- Client guard snackbars + server `403` enforcement
- Applied on accept-request and book-seat paths

### Key files
- `lib/core/utils/same_account_guard.dart`
- `lib/features/rides/presentation/providers/rides_provider.dart` (identity helpers)
- `server/main.py` (`is_same_account`, accept/book endpoints)

---

## 4. Multi-student chat + mutual confirm + auto-notify others

**Goal:** Like real ride apps — many people can message; only one confirmed pair locks the post.

### Behavior
1. Biker posts a ride → stays **visible** while students book/message (soft interest; seats not locked on book)
2. Multiple students get **individual chat boxes** with the biker
3. Biker can switch chats and talk to each student
4. When **both** Confirm Ride in one chat:
   - Post → `occupied` (hidden from others)
   - Other chats on same post get system inbox SMS:  
     *“The rider has accepted another student's offer. Please try to find a new rider.”*
5. Same pattern for **student ride requests** (other bikers notified)

### Key files
- `server/confirm_flow.py`
- `server/main.py` (`create_booking` soft book, `chat/session/confirm`)
- `lib/shared/navigation/main_navigation_screen.dart` (WS: `ride_taken_by_other`)

---

## 5. Confirm timeout (3 reminders × 2 minutes → suspend)

**Scenario:** Student confirms, biker does not (or reverse).

### Behavior
- Reminder every **2 minutes**, max **3** times
- If still not confirmed → post **`suspended`**, hidden from public feed
- Biker dashboard shows **SUSPENDED • NO CONFIRM** with explanation
- Same for request-ride conversations

### Key files
- `server/confirm_flow.py` (reminder loop + suspend)
- `lib/features/rides/data/models/ride_model.dart` (`occupied`, `suspended`)
- `lib/features/rides/presentation/widgets/my_rides_activity_view.dart`

---

## 6. Messaging reliability (Messenger / WhatsApp / Instagram *behavior*)

**Note:** UI look was **not** copied — only how messaging should *work*.

### Fixes
| Issue | Fix |
|--------|-----|
| Dual conversation IDs (`peer_dm` vs hash) | Canonical `peer_dm_{sorted ids}` only |
| WS relay without DB → ghost messages | Persist-then-broadcast; WS chat also persists via save path |
| Fake always-read double ticks | Real sending / sent / read / failed states |
| Failed send looked successful | Failed icon + tap to retry |
| Aggressive 3s polling | Poll every 12s **only when WS disconnected** |
| Text-based dedupe dropped “ok/ok” | Dedupe by message **id** only |
| Unread never updated | Server increments peer unread; mark-read on open chat |
| Empty/wrong history on reopen | Merge server + local pending; catch-up after reconnect |

### Key files
- `lib/core/utils/peer_dm_id.dart`
- `lib/features/chat/data/models/chat_message.dart`
- `lib/features/chat/data/repositories/shared_sync_chat_repository.dart`
- `lib/features/chat/presentation/providers/chat_provider.dart`
- `lib/features/chat/presentation/screens/chat_screen.dart` (ticks / retry)
- `lib/features/chat/presentation/screens/campus_messages_screen.dart`
- `server/main.py` (`_save_and_broadcast_message`, `mark-read`, WS handler)

### New API
- `POST /ride/api/messages/mark-read` — clear unread + mark peer messages read when a thread is opened

---

## How to run locally

```bash
# Backend
cd server
python -m uvicorn main:app --host 127.0.0.1 --port 8080 --workers 1

# App URL
http://127.0.0.1:8080/ride/
```

Hard refresh after web rebuild: `Ctrl+Shift+R`

---

## Build notes

- Flutter web build required `CardThemeData` + `google_fonts` upgrade for current Flutter SDK
- `RideStatus` switches updated for `occupied` / `suspended`
