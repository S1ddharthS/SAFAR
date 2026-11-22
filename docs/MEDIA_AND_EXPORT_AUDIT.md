# SAFAR — Media, Upload & Document Export Audit

**Date:** 2026-11-22  
**Scope:** Media ingestion, file validation, storage architecture, URL signing, offline queuing, and document export workflows across Flutter and FastAPI.  
**Tested On:** Motorola Edge 50 Pro (Physical Android 14/15), Staging API (Port 8020).

---

## 1. Media Storage & Ingestion Architecture

### Storage Configuration
- **Root Directory:** Staging uses `services/api/storage_staging/`.
- **Directory Isolation:** Uploads are strictly partitioned by trip ID:
  $$\text{storage\_staging/media/}\{trip\_id\}/\{filename\}$$
- **File Naming:** UUIDv4 hex string + validated extension (e.g. `d7a31b2...jpg`). Directory traversal (`../`) is rejected with HTTP 422.

### Supported File Types & MIME Validation
The backend enforces a strict whitelist of allowed formats in `services/api/app/routers/memories.py`:
- **Images:** `image/jpeg` (`.jpg`), `image/png` (`.png`), `image/webp` (`.webp`).
- **Video:** `video/mp4` (`.mp4`).
- **Audio:** `audio/webm` (`.webm`), `audio/mpeg` (`.mp3`), `audio/ogg` (`.ogg`), `audio/wav` (`.wav`).

### Magic-Byte Sniffing
File validation does not rely on the client's declared `Content-Type` header or extension:
- `services/api/app/services/media.py::media_matches_type()` inspects file magic headers (e.g. `\xFF\xD8\xFF` for JPEG, `\x89PNG` for PNG, `RIFF...WEBP` for WebP).
- Spoofed extensions or disguised executables are rejected with HTTP 422.
- Maximum payload limit is strictly enforced at $25\text{ MB}$ ($26,214,400\text{ bytes}$).

---

## 2. Media Upload & Access Lifecycle Audit

| Step | Design Specification | Actual Implementation | Audit Finding & Status |
|---|---|---|---|
| **Capture: Photo** | Camera capture & gallery selection | `image_picker` package in Flutter `MemoriesScreen` | **WORKING:** Allows camera capture and gallery selection with max width 1600px, quality 82%. |
| **Capture: Video** | Select or record video clips | Not implemented in Flutter UI | **MISSING:** `_MemorySheet` only triggers `pickImage()`; `pickVideo()` is absent. |
| **Capture: Voice** | In-app voice memo recording | Not implemented in Flutter UI | **MISSING:** No microphone recorder widget or audio picker in `MemoriesScreen`. |
| **Upload Progress** | Real-time percentage indicator | Dio multipart without `onSendProgress` | **MISSING:** Progress is not tracked; button shows generic spinner only. |
| **Upload Cancellation** | User can cancel ongoing upload | No `CancelToken` wired to UI | **MISSING:** Upload cannot be aborted once initiated. |
| **Retry on Failure** | Failed uploads can be retried | SnackBar error; form preserved | **PARTIAL:** User can re-tap submit, but no automatic chunked retry exists. |
| **Authenticated Read** | Expiring HMAC-signed URLs | `sign_media_url()` in `services/media.py` | **WORKING:** Generates 12-hour signed tokens (`?sig=...&expires=...`); unsigned requests return 403. |
| **Media Deletion** | Owner or admin can delete media | `DELETE /api/trips/{id}/memories/{id}` | **WORKING:** Soft-deletes DB record and purges cached signatures. |
| **Offline Media Queue**| Queue media uploads offline | Only text JSON mutations queued | **MISSING:** `OfflineQueue` cannot store binary images or resume upload when reconnected. |
| **Expired Signature** | Expired signed URLs handled | CachedNetworkImage error placeholder | **PARTIAL:** If a 12-hour signed URL expires in a cached view, image fails without auto-refresh. |

---

## 3. Document Export, Sharing & Print Workflows

A critical finding of this audit is that **every single export feature in the mobile application is incomplete or broken in presentation**:

```
[User taps "Open travel book"] ──> [API returns HTML] ──> [SelectableText displays raw HTML code] ──❌ BROKEN
[User taps "Export CSV"]       ──> [API returns CSV]  ──> [SelectableText displays raw CSV text]  ──❌ BROKEN
[User taps "Export data"]      ──> [API returns JSON] ──> [SelectableText displays raw JSON text] ──❌ BROKEN
```

### A. Journey Replay & Travel Book (F18 / F44)
- **Current Behavior:**
  1. The backend endpoint `GET /api/trips/{trip_id}/travel-book` generates a complete, valid HTML5 document containing Georgia serif typography, trip header, itinerary daily sections, approved memories with signed image thumbnails, bylines, and print stylesheet rules (`@media print`).
  2. In `apps/mobile/lib/features/trip/replay_screen.dart`, `_openTravelBook()` calls `travelBook()` and displays the resulting string in `SelectableText(book)` inside a bottom sheet modal.
  3. The user on the Motorola Edge 50 Pro is presented with raw source code: `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">...`.
- **Root Cause:**
  - The Flutter application does not render the HTML.
  - `pubspec.yaml` contains neither `webview_flutter` nor `url_launcher` nor `printing`.
- **Required Solution:**
  1. Add `url_launcher` and `path_provider` to mobile dependencies.
  2. Implement an in-app browser or Chrome Custom Tab launch via `launchUrl()` pointing to the authenticated travel book URL or a temporary local HTML file.
  3. Add a dedicated **Share HTML** action using `SharePlus.instance.shareXFile()` so the document can be sent via WhatsApp, Email, or Google Drive as a real `.html` attachment.
  4. Add a **Print / Save as PDF** action utilizing Android's native print framework.

### B. Shared Expenses CSV Export (F13)
- **Current Behavior:**
  1. Backend `GET /api/trips/{trip_id}/expenses/export` returns RFC 4180 compliant CSV string with columns: `date,title,payer,amount,currency,split_type,members`.
  2. In `apps/mobile/lib/features/trip/expenses_screen.dart`, the download button displays the CSV text in a `SelectableText` block inside a sheet with subtitle: *"Copy this into a spreadsheet. It stays on your device."*
- **Root Cause:**
  - No file is created on the device filesystem.
  - No native Android share intent is dispatched.
- **Required Solution:**
  1. Write CSV content to a temporary cache file: `${cacheDir}/expenses_${trip_id}.csv`.
  2. Call `SharePlus.instance.shareXFile(XFile(path, mimeType: 'text/csv'))`.
  3. This allows the user to directly open the CSV in Google Sheets, Microsoft Excel, or save to Android Downloads.

### C. Personal Data Export (GDPR / F01)
- **Current Behavior:**
  1. Backend `GET /api/me/export` returns JSON containing profile data, granted consents, trip memberships, and authored memories.
  2. In `apps/mobile/lib/features/profile/settings_screen.dart`, `_export()` dumps the JSON string into `SelectableText(data)`.
- **Required Solution:**
  1. Write JSON content to `${cacheDir}/safar_user_data_export.json`.
  2. Share via `SharePlus.instance.shareXFile(XFile(path, mimeType: 'application/json'))`.

---

## 4. Android 14+ Platform Storage Compatibility

On the Motorola Edge 50 Pro running Android 14 (API 34/35):
- **Scoped Storage:** SAFAR cannot write arbitrary files to public directories like `/sdcard/` without MediaStore integration.
- **Cache Directory Safety:** Exported artifacts (HTML, CSV, JSON) must be stored in `getTemporaryDirectory()` or `getApplicationDocumentsDirectory()`, which require zero runtime storage permissions.
- **Android Share Sheet:** `share_plus` uses `FileProvider` (`androidx.core.content.FileProvider`), which safely grants read URIs to recipient apps (Gmail, Drive, Sheets, Chrome) without exposing filesystem paths.
- **Photo Selection:** `image_picker` uses the Android Photo Picker (`ActivityResultContracts.PickVisualMedia`), ensuring privacy without demanding broad `READ_EXTERNAL_STORAGE` permissions.
