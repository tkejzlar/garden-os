# GardenOS — Product Spec
## A garden management app with Home Assistant integration

> Draft spec v0.2 — 2026-03-15 — Decisions locked: HACS, AI assist, Calendar

---

## The problem

Managing a productive garden involves tracking dozens of overlapping timelines — sowing dates, germination windows, succession schedules, transplant readiness, weather dependencies, and harvest periods — across multiple beds, arches, and indoor stations. Currently this lives in markdown files, memory, and ad-hoc conversations. The result: missed succession windows, forgotten sowings, and no feedback loop between what the garden needs and what the weather/sensors are saying.

## Who is this for

Me. One user, one garden, Prague climate. If it works for me, maybe others later. But the MVP is a tool I actually use every day from March to October.

## Core concept

A single-page web app that knows:
- **What's planted where** (the living garden.md)
- **What stage everything is at** (seed → germinating → seedling → hardening → planted out → producing → done)
- **What needs doing today** based on calendar + weather + sensor data
- **What's coming up** in the next 7/14 days

It pushes notifications to my phone via Home Assistant.

---

## Data model

### Garden structure (mostly static, set up once per season)

```
Garden
├── Beds (BB1, BB2, Corner, SB1, SB2, Tiny)
│   ├── dimensions, orientation, wall type
│   └── Rows/Zones (Row A, Row B, etc.)
│       └── Slots (named positions within rows)
├── Arches (A1, A2, A3, A4)
│   ├── between_beds, gap_width
│   └── spring_crop, summer_crop
└── Indoor stations
    ├── Heat mat (with target temp)
    ├── Grow light shelf
    └── Windowsills
```

### Plants (the living data — changes throughout season)

```
Plant
├── variety_name (e.g. "Raf", "Mini Bell Trio")
├── crop_type (tomato, pepper, herb, flower, etc.)
├── source (Magic Garden Seeds, Loukykvět, saved seed)
├── target_location (bed + row + position)
├── lifecycle_stage: enum
│   ├── seed_packet      — not yet sown
│   ├── pre_treating      — soaking, stratifying, scarifying
│   ├── sown_indoor       — in modules/trays
│   ├── germinating       — waiting for emergence
│   ├── seedling          — up and growing under lights
│   ├── potted_up         — moved to larger pot
│   ├── hardening_off     — going outside during days
│   ├── planted_out       — in final bed position
│   ├── producing         — actively harvestable
│   ├── done              — pulled / finished for season
│   └── stratifying       — in fridge (lavender, hartwort)
├── stage_history[]       — timestamped log of stage transitions
├── sow_date
├── germination_date
├── transplant_date
├── notes[]               — freeform observations
└── succession_group      — links to sibling sowings (lettuce #1, #2, etc.)
```

### Succession schedules (repeating patterns)

```
SuccessionPlan
├── crop (e.g. "Lettuce", "Radish")
├── varieties[] (rotate through these)
├── interval_days (e.g. 18 for lettuce, 21 for radish)
├── season_start, season_end
├── target_beds[]
├── total_planned_sowings (e.g. 8 for lettuce)
└── sowings[] → links to Plant records
```

### Tasks (generated + manual)

```
Task
├── title
├── type: enum (sow, transplant, feed, water, harvest, 
│               build, prep, check, order)
├── due_date (can be fuzzy: "when soil >5°C")
├── conditions{}          — weather/sensor gates
│   ├── min_temp, max_temp
│   ├── no_frost_days_ahead (e.g. 3)
│   ├── soil_temp_min
│   └── rain_ok: boolean
├── related_plants[]
├── related_beds[]
├── priority: enum (must, should, could)
├── status: enum (upcoming, ready, done, skipped, deferred)
└── recurrence (for succession sowings)
```

---

## Features — MVP (what I build first)

### 1. Dashboard — "What do I do today?"

The home screen. Shows:
- **Weather strip** — today + 3 day forecast (from HA weather entity or OpenWeatherMap)
- **Frost alert** — prominent warning if overnight frost expected within 3 days
- **Today's tasks** — filtered by weather conditions being met
- **Germination watch** — anything on the heat mat / in modules that needs checking (with days-since-sown counter)
- **Upcoming this week** — next 7 days of tasks

This is the screen I open every morning with coffee.

### 2. Plant tracker

List/grid of all active plants with current stage. Tap a plant to see its full lifecycle timeline. Quick-action buttons: "Mark as germinated", "Potted up today", "Planted out", etc. Each transition auto-logs the date.

Batch operations matter — "Mark all 6 pepper varieties as germinated" in one tap, not six.

### 3. Bed map (read-only in MVP)

Visual representation of the garden layout from garden.md. Shows what's in each position and its current stage. Colour-coded by crop type (same palette as our diagrams: red=tomato, orange=pepper, green=cucumber, etc.)

Interactive version (click a position to see the plant detail) is MVP. Drag-and-drop rearrangement is NOT MVP.

### 4. Succession planner

Shows all succession schedules with: which sowings are done, which is next, and when it's due. The "next lettuce sowing is in 4 days" prompt that I currently track in my head.

### 5. HA notifications

Push notifications to phone via HA notify service:
- **Morning brief** (07:00) — "3 tasks today. No frost risk. Peppers day 5 on heat mat."
- **Frost alert** — immediate if forecast drops below 0°C within 48 hours and anything tender is outside
- **Germination check** — "Peppers have been on heat mat for 7 days — check for radicles"
- **Succession reminder** — "Lettuce #4 due in 2 days"
- **Weather window** — "Dry + warm weekend ahead — good time to transplant"

---

## Features — V2 (after MVP works for a month)

### 6. Harvest log
Track what's harvested, when, and roughly how much. Over multiple seasons this becomes useful data about which varieties performed. AI end-of-season summary uses this data.

### 7. Photo journal
Snap a photo, tag it to a plant/bed/date. Auto-builds a visual timeline per plant. Photos attached to stage transitions ("here's the pepper at seedling stage").

### 8. Sensor integration
- **Soil temperature probes** (if added to HA) — auto-triggers "soil ready for peas" task
- **Indoor temperature sensors** — verify heat mat is actually at 30°C, alert if it drops
- **Rain gauge** — auto-skip watering tasks
- **Cat motion sensor near seedlings** — alert if the bastards are back

### 9. Season planner (next year)
Pre-plan the full season in Nov/Dec. Set up all beds, assign varieties, generate the task calendar. Basically automate the conversation we had today. AI suggests variety assignments based on previous season performance.

### 10. Seed inventory
Track what seed packets you have, quantities remaining, sow-by dates. Auto-suggests reorders. Link to Loukykvět / Magic Garden Seeds product pages.

### 11. Succession planner view
Visual timeline showing all succession groups — which sowings are done, which is next, gaps to fill. Gantt-chart style.

---

## Architecture

### Tech stack

| Layer | Choice | Why |
|-------|--------|-----|
| Backend | Ruby / Sinatra | My stack. Fast to build, simple to deploy |
| Database | SQLite | Single user, file-based, zero config. Can migrate to Postgres later if needed |
| Frontend | HTML + Alpine.js + Tailwind | No build step, progressive enhancement, works on mobile |
| API | JSON REST | Sinatra serves both HTML pages and JSON endpoints |
| HA integration | HACS custom integration + REST API | Sensor entities, calendar entity, Lovelace cards, notifications |
| AI | Claude API (Sonnet) | One structured call per morning for contextual advisories |
| Hosting | Same box as HA (port 4567) | Single box, shared backups, no extra infra |
| Background jobs | Rufus-scheduler or cron | Daily AI call, morning brief, weather checks, reminder scheduling |

### HA integration detail

**Outbound (app → HA):**
- POST to `ha_url/api/services/notify/mobile_app_toms_phone` for push notifications
- Use HA long-lived access token, stored in env var

**Inbound (HA → app):**
- Weather data: poll HA weather entity every 6 hours, or use OpenWeatherMap API directly
- Sensor data (V2): poll specific HA sensor entities (soil temp, indoor temp)
- Alternative: HA automation sends webhook to app when sensor thresholds are crossed

**Notification templates:**
```yaml
# Morning brief — triggered by cron at 07:00
service: notify.mobile_app
data:
  title: "🌱 Garden — {{ date }}"
  message: >
    {{ task_count }} tasks today.
    {{ weather_summary }}.
    {{ germination_alerts }}.
  data:
    url: "https://garden.local/dashboard"
    
# Frost alert — triggered by weather check
service: notify.mobile_app
data:
  title: "🥶 Frost warning"
  message: >
    {{ min_temp }}°C expected {{ when }}.
    {{ tender_plants_outside_count }} tender plants outside.
  data:
    actions:
      - action: "FROST_ACKNOWLEDGE"
        title: "Got it"
```

### Data flow

```
garden.md (static reference)
     ↓ (import once, then app is source of truth)
  SQLite DB
     ↓
  Sinatra app ← → HA REST API (weather, sensors)
     ↓                    ↓
  Web UI (mobile)    Push notifications
```

### Key design decisions

1. **garden.md is the seed, not the master.** Import it once to populate the DB. After that, the app is the single source of truth. garden.md becomes a generated export, not an input.

2. **Mobile-first.** I'm in the garden with muddy hands. Big tap targets, simple flows, works on phone browser. No native app needed — PWA with add-to-homescreen.

3. **Offline-tolerant.** If HA is down, the app still works for tracking. Notifications queue and send when connection restores.

4. **Opinionated defaults.** Pre-populate Prague climate data: last frost May 12-15, first frost mid-Oct, typical soil warming curve. Don't make me configure what I already know.

5. **Low ceremony.** Adding a plant or logging a stage change should be 2 taps, not a form with 15 fields. Most fields auto-populate from the variety database.

---

## Data seeding

### Variety database (built-in)

Pre-populate with common crop metadata so I don't have to enter it per plant:

```json
{
  "tomato": {
    "sow_indoor_weeks_before_last_frost": 8,
    "germination_temp_min": 20, "germination_temp_ideal": 25,
    "germination_days_min": 5, "germination_days_max": 14,
    "days_to_maturity_range": [60, 90],
    "frost_tender": true,
    "feed_from": "first_truss"
  },
  "pepper": {
    "sow_indoor_weeks_before_last_frost": 10,
    "germination_temp_min": 25, "germination_temp_ideal": 30,
    "germination_days_min": 7, "germination_days_max": 21,
    "days_to_maturity_range": [70, 100],
    "frost_tender": true
  }
  // ... etc for all crop types
}
```

### Import from garden.md

Parse the markdown to create:
- Bed + Row + Slot records
- Plant records with target locations
- Arch records with crop assignments
- Succession plans from the succession table

This is a one-time script, not an ongoing sync.

---

## MVP scope — what I build in the first weekend

### Day 1: Data + backend
- SQLite schema + models (Sequel ORM)
- Import garden.md parser
- Sinatra routes for dashboard, plants, beds
- Background job for weather polling
- Claude API integration (morning advisory call)

### Day 2: Frontend + HA
- Dashboard page with today's tasks + weather + germination watch + AI insights panel
- Plant list with stage-change buttons
- HA notification integration (morning brief + frost alert)
- PWA manifest for homescreen install

### Day 3: HACS + calendar + deploy
- HACS custom integration scaffold (sensor entities for plants, binary sensors for alerts)
- Calendar entity exposing tasks as events (syncs to Google Calendar via HA)
- Bed map (static SVG, clickable)
- Deploy to HA box
- Test full flow: AI call → dashboard → notifications → calendar

---

## Decisions locked in

1. **HACS integration: YES.** Build GardenOS as a HACS custom integration. This gives: native HA dashboard cards (embed bed map, task list, germination watch as Lovelace cards), sensor entities (each plant becomes an entity with stage as state), calendar entity (tasks appear in HA calendar), and free notification infrastructure via existing HA automations. The web app still exists as the main UI, but HA becomes the integration bus rather than just a notification pipe.

2. **Single user.** Just me. No auth, no multi-user. Keeps everything simple.

3. **Calendar: YES.** Expose a `calendar.gardenOS` entity in HA. Tasks appear as calendar events. This syncs to Google Calendar via the existing HA Google Calendar integration — no direct Google API needed. Succession sowings, transplant dates, harvest windows all show as events.

4. **Voice assistant: NO.** Not MVP, not V2. Maybe never. I'll be in the garden with dirty hands looking at my phone, not talking to a speaker.

5. **AI assist: YES.** Claude API integration for contextual recommendations. Not a chatbot — a background advisor that enriches the dashboard. Examples:
   - Germination watch: "Peppers day 8 at 30°C — no emergence. AI says: check paper towel moisture, consider bumping to 32°C. Normal range is 5-10 days."
   - Weather-aware: "Dry spell forecast for next 5 days + temps above 25°C. AI says: good transplant window for tomatoes if they're ready."
   - Succession timing: "Lettuce #3 was sown 3 days late. AI says: still fine, but sow #4 on schedule to avoid a gap in July."
   - End of season: "Comparing your 23 tomato varieties — AI generates a performance summary based on lifecycle data, harvest dates, and your notes."

### AI integration architecture

```
Daily cron (06:30, before morning brief)
    ↓
Collect context:
  - All plants + current stages + days-in-stage
  - Weather forecast (3 day)
  - Upcoming tasks
  - Recent notes
  - Sensor data (if available)
    ↓
POST to Claude API (Sonnet — fast + cheap)
  System prompt: "You are a garden advisor for a Prague garden..."
  User message: structured JSON of current garden state
  Response: JSON with per-plant advisories + general recommendations
    ↓
Store advisories in DB
    ↓
Surface in morning brief notification + dashboard "AI insights" panel
```

**Key constraints:**
- One API call per day (morning), not per interaction. Keeps costs trivial
- Sonnet not Opus — this is structured advisory, not creative work
- AI output is always advisory, never auto-executes (no auto-skipping tasks)
- Context window includes variety database so it knows germination norms
- Responses are JSON-structured so they slot into the UI cleanly, not freeform prose

### HACS integration architecture

```
GardenOS HACS custom integration
├── config_flow.py          — setup: point to GardenOS web app URL
├── sensor.py               — one sensor entity per plant (state = lifecycle stage)
│   └── attributes: variety, bed, row, days_in_stage, sow_date, etc.
├── calendar.py             — calendar entity with tasks as events
├── binary_sensor.py        — frost_risk, germination_overdue, succession_due
├── services.yaml           — advance_stage, log_note, skip_task
└── lovelace/
    ├── garden-dashboard.yaml    — pre-built dashboard card
    ├── germination-watch.yaml   — card for heat mat / indoor station
    └── bed-map.yaml             — SVG bed layout card
```

**HA entities created:**

| Entity | Type | Example state |
|--------|------|---------------|
| `sensor.gardenOS_pepper_raf` | sensor | `germinating` |
| `sensor.gardenOS_tomato_murielle` | sensor | `seedling` |
| `binary_sensor.gardenOS_frost_risk` | binary_sensor | `on` / `off` |
| `binary_sensor.gardenOS_succession_due` | binary_sensor | `on` when next sowing overdue |
| `calendar.gardenOS` | calendar | upcoming tasks as events |

This means I can build HA automations on top — e.g. "if frost_risk turns on AND any plant has stage=hardening_off, send critical alert". Or use the plant sensors in energy dashboard style long-term statistics.

### Calendar detail

Tasks flow into the HA calendar entity:

```
Event: "Sow Lettuce #4 — BB1, BB2, Corner"
Start: 2026-04-15
All-day: true
Description: "Varieties: Tre Colori, Qualitas. Succession #4 of 8."

Event: "Transplant ALL tomatoes — after Ice Saints"  
Start: 2026-05-16
End: 2026-05-21
Description: "22 varieties → BB1, BB2, Corner. Check forecast for frost-free window."
```

From HA calendar, these auto-sync to Google Calendar if the Google Calendar integration is configured. No extra work needed.

---

## Open questions (remaining)

1. **Web app hosting** — same box as HA (Sinatra on port 4567), or separate? Same box is simpler but adds load to HA hardware.

2. **Bed map rendering** — static SVG generated from data, or interactive Canvas/D3? SVG is simpler and works in Lovelace cards. Canvas is prettier but harder to embed.

3. **Data backup** — SQLite file backup to Google Drive / NAS? Or just rely on the HA backup system if hosted on same box?

---

## Success criteria

The app is working if:
- I open it every morning and it tells me something useful
- I never miss a succession sowing window
- I get frost alerts before I lose plants
- I can look back in October and see the full lifecycle of every tomato variety from seed to harvest
- The AI insight in the morning brief teaches me something I didn't know at least once a week
- Tasks show up in my calendar without me having to enter them twice
- It takes less time to use than not using it
