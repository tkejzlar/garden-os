# GardenOS Frontend Rewrite — React SPA

## Decision

Strip all ERB views. Keep Sinatra as a JSON API. Build a React SPA with Vite.

**Why:** The current ERB + Alpine.js stack cannot support the level of interactivity the app needs (drag-and-drop bed editor, real-time state, complex modals, optimistic updates). Every UX improvement is a fight against the architecture.

**What stays:** Sinatra routes (as JSON API), Sequel models, SQLite database, RubyLLM integration, all existing data.

**What goes:** All `.erb` views, Alpine.js, inline styles, Tailwind CDN, plan-tab.js, bed-editor.js.

---

## Architecture

```
┌─────────────────────────────────────────┐
│  React SPA (Vite)                       │
│  └── public/app/                        │
│      ├── src/                           │
│      │   ├── pages/                     │
│      │   ├── components/                │
│      │   ├── hooks/                     │
│      │   ├── lib/api.ts                 │
│      │   └── lib/companions.ts          │
│      ├── index.html                     │
│      └── vite.config.ts                 │
├─────────────────────────────────────────┤
│  Sinatra API (existing, cleaned up)     │
│  └── routes/                            │
│      ├── api_beds.rb                    │
│      ├── api_plants.rb                  │
│      ├── api_seeds.rb                   │
│      ├── api_tasks.rb                   │
│      ├── api_planner.rb (SSE)           │
│      └── api_gardens.rb                 │
├─────────────────────────────────────────┤
│  Models & Services (unchanged)          │
│  └── models/, services/, config/        │
└─────────────────────────────────────────┘
```

**Dev mode:** Vite dev server on :5173, proxies API calls to Sinatra on :9292.
**Prod mode:** `vite build` → static files in `public/dist/`, Sinatra serves them with a catch-all route.

---

## Tech Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Framework | React 19 | Known by user, largest ecosystem |
| Build | Vite | Fast dev, simple config |
| Routing | React Router v7 | Standard, supports URL state |
| State | Zustand | Lightweight, no boilerplate (vs Redux) |
| Styling | Tailwind CSS 4 | Already used partially, utility-first |
| Drag & Drop | @dnd-kit | Best React DnD library, touch support built-in |
| SVG Bed Editor | React + SVG | Direct JSX SVG, no imperative DOM manipulation |
| Charts/Timeline | Recharts or custom SVG | For Gantt/timeline view |
| AI Chat | Server-Sent Events | Already works in Sinatra, React hook to consume |
| HTTP | fetch + custom hooks | Simple, no axios needed |
| TypeScript | Yes | Catch bugs at compile time |
| Icons | Lucide React | Already using Lucide |

---

## Pages & Components

### Pages (React Router)

| Route | Page | Current equivalent |
|-------|------|--------------------|
| `/` | Dashboard | dashboard.erb |
| `/garden` | Garden Designer | garden.erb |
| `/plants` | Plants List | plants/index.erb |
| `/plants/:id` | Plant Detail | plants/show.erb |
| `/seeds` | Seeds Inventory | seeds/index.erb |
| `/seeds/new` | Add Seed | seeds/show.erb |
| `/seeds/:id` | Edit Seed | seeds/show.erb |
| `/plan` | Plan Hub | succession.erb |
| `/plan?bed=:id` | Plan + Bed Modal | succession.erb + bed modal |

### Key Components

**Layout:**
- `AppShell` — tab bar, garden switcher, toast notifications
- `BottomNav` — 5-tab navigation
- `GardenSwitcher` — dropdown, API call to switch
- `Toast` — global toast system (Zustand store)

**Bed Editor (the big win):**
- `BedModal` — dialog wrapper with URL state sync
- `BedCanvas` — React SVG component, replaces imperative bed-editor.js
  - `PlantRect` — draggable plant rectangle (uses @dnd-kit)
  - `GridLines` — SVG grid overlay
  - `GhostPreview` — placement preview on hover
  - `DropZone` — collision-aware drop target
- `BedSidebar` — search, plant list, companions
  - `SeedSearch` — input with filtered results
  - `PlantList` — with inline actions (delete, duplicate)
  - `CompanionPanel` — good/bad pairs
  - `SowingTag` — timeline hint per plant

**Plan Hub:**
- `TaskList` — grouped by urgency, optimistic completion
- `Timeline` — Gantt chart (Recharts or custom SVG)
- `BedsGrid` — bed cards with drag-to-reorder
- `AIDrawer` — chat with SSE streaming

**Garden Designer:**
- `DesignerCanvas` — SVG canvas with zoom/pan
- `BedShape` — draggable/resizable bed
- `ToolBar` — select/rect/polygon tools
- `PropertiesPanel` — selected bed properties

---

## API Cleanup

The current API is a mix of `/api/beds`, `/beds/:id/distribute`, `/plants/:id` (no /api/ prefix), etc. Normalize everything under `/api/`:

| Current | New | Notes |
|---------|-----|-------|
| `GET /api/beds` | Keep | |
| `PATCH /api/beds/reorder` | Keep | |
| `POST /api/beds` | Keep | |
| `PATCH /api/beds/:id` | Keep | |
| `DELETE /api/beds/:id` | Keep | |
| `POST /beds/:id/distribute` | `POST /api/beds/:id/distribute` | Move under /api/ |
| `POST /beds/:id/apply-layout` | `POST /api/beds/:id/apply-layout` | Move under /api/ |
| `GET /api/plants` | Keep | |
| `POST /api/plants` | Keep | |
| `DELETE /api/plants/:id` | Keep | |
| `PATCH /plants/:id` | `PATCH /api/plants/:id` | Move under /api/ |
| `POST /plants/:id/advance` | `POST /api/plants/:id/advance` | Move under /api/ |
| `POST /plants/batch_advance` | `POST /api/plants/batch-advance` | Move under /api/ |
| `GET /api/seeds` | Keep | |
| `POST /seeds` | `POST /api/seeds` | Move under /api/ |
| `PATCH /seeds/:id` | `PATCH /api/seeds/:id` | Move under /api/ |
| `DELETE /seeds/:id` | `DELETE /api/seeds/:id` | Move under /api/ |
| `GET /api/seeds/lookup` | Keep | AI catalog lookup |
| `POST /succession/planner/ask` | `POST /api/planner/ask` | SSE streaming |
| `POST /succession/planner/commit` | `POST /api/planner/commit` | |
| `GET /api/plan/bed-timeline` | Keep | |
| `GET /api/tasks` | New | Currently tasks are only in ERB |
| `POST /api/tasks/:id/complete` | New | Currently POST with redirect |
| `GET /api/gardens` | New | For garden switcher |
| `POST /api/gardens/switch/:id` | Keep | |
| `GET /api/dashboard` | New | Aggregated dashboard data |

---

## Migration Strategy

### Phase 1: Scaffolding (1 session)
- Set up Vite + React + TypeScript in `public/app/`
- Configure Vite proxy to Sinatra API
- Create `AppShell` with routing and bottom nav
- Add Sinatra catch-all route to serve the SPA
- Verify: can navigate between empty pages, API calls work

### Phase 2: Dashboard + Plants (1 session)
- Port dashboard (simplest page, good test of the stack)
- Port plants list + detail pages
- Add task completion API endpoint
- Add toast notification system (Zustand)
- Verify: full dashboard and plants workflow works

### Phase 3: Seeds (1 session)
- Port seeds list + form with typeahead
- Port the AI catalog lookup
- Verify: full seed CRUD works

### Phase 4: Bed Editor — the big one (2 sessions)
- Build `BedCanvas` as React SVG component
- Implement @dnd-kit drag-and-drop for plants
- Build `BedSidebar` with search, plant list, companions
- Click-to-place with ghost preview
- Row/column add
- URL state sync (`?bed=123`)
- Verify: full bed planning workflow works

### Phase 5: Plan Hub (1 session)
- Task list with optimistic completion
- Timeline/Gantt view
- Beds grid with reorder
- AI chat drawer with SSE streaming
- Verify: full planning workflow works

### Phase 6: Garden Designer (1 session)
- SVG canvas with zoom/pan
- Bed drawing (rect + polygon)
- Bed selection + properties panel
- Plant overlay toggle
- Verify: full garden design workflow works

### Phase 7: Cleanup (1 session)
- Remove all .erb views (except error.erb as fallback)
- Remove Alpine.js, plan-tab.js, bed-editor.js
- Normalize all API routes under /api/
- Add API error handling middleware
- Production build + deployment config

---

## What Improves Immediately

Every UX issue from the audit gets fixed by the architecture change:

| Issue | How React fixes it |
|-------|--------------------|
| Delete plant doesn't update | React state → automatic re-render |
| URL state lost on refresh | React Router manages it natively |
| `confirm()` dialogs | React component with state |
| `location.reload()` everywhere | Never needed — state updates trigger re-renders |
| Inline styles inconsistent | Tailwind everywhere, component-scoped |
| Touch targets too small | Component library with size props |
| SVG text too small/broken | React SVG components with proper props |
| No error feedback | Global toast via Zustand store |
| Sidebar panels hiding each other | Component state, not `x-if` mutual exclusion |
| Drag-drop collision | @dnd-kit has collision detection built in |
| Search not auto-focusing | `useRef` + `useEffect` |
| No undo | State history trivial with Zustand middleware |

---

## Estimated Effort

7 phases × ~1 session each = approximately 7 focused sessions to complete the migration. Each phase produces a working, testable app — no big-bang cutover needed.

The existing Sinatra API continues serving the old ERB views until each page is ported. Both can coexist during migration.
