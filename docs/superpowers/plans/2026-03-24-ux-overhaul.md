# GardenOS UX Overhaul Plan

## Audit Summary

Full-app UX audit against responsive web best practices and Laws of UX (lawsofux.com).
Covers all 9 views, 5 route files, 2 JS components, and the global layout.

---

## Session 1: Foundation — Error Handling, URLs, Feedback

*Everything here makes the app feel broken. Fix before anything else.*

### 1.1 Replace all silent `console.error` with user-visible feedback
**Law:** Peak-End Rule — silent failures are the worst "peak" moment
**Files:** `bed-editor.js` (5 catch blocks), `plan-tab.js` (timeline fetch)
**Fix:** Add a shared `showToast(message, type)` function (Alpine store or simple DOM injection). Replace every `console.error` with `showToast('Could not save — check connection', 'error')`. Add success toasts for distribute ("Arranged 8 plants"), add, remove.

### 1.2 Replace all `window.confirm()` with inline confirmation
**Law:** Jakob's Law — confirm dialogs are blocked on mobile and feel system-level
**Files:** `bed-editor.js:removePlant`, `plants/show.erb` (photo delete), `seeds/show.erb` (delete seed)
**Fix:** On remove click, transform the row to a red "Remove? / Cancel" state for 3 seconds. No browser dialog.

### 1.3 Replace `location.reload()` with optimistic DOM updates
**Law:** Doherty Threshold — reload costs 1-3s, optimistic update costs 0ms
**Files:** `succession.erb:74,98` (task complete), `plan-tab.js:127` (moveBed)
**Fix:** Remove the task row from DOM on click. If fetch fails, restore it. Same for bed reorder.

### 1.4 Add permanent URLs for modal state
**Law:** Jakob's Law — users expect refresh to preserve state
**Fix:** When bed modal opens, push `?bed=123` to history. On page load, check for `?bed=` param and auto-open. When AI drawer opens, push `?ai=1`. This makes modals bookmarkable and survives refresh.

### 1.5 Proper 404/500 error pages
**Files:** `app.rb` — add `not_found` and `error` handlers that render within `layout.erb`
**Fix:** Users currently see raw text "Plant not found" with no navigation. Wrap in the layout with a "Go home" link.

### 1.6 Add `::backdrop` and click-outside-to-close on all dialogs
**Law:** Jakob's Law — standard modal behavior
**Files:** `succession.erb` (bed modal, AI drawer)
**Fix:** Add CSS `dialog::backdrop { background: rgba(0,0,0,0.4); }`. Add `@click.self` on dialog to close.

---

## Session 2: Mobile & Responsive

*The app is a PWA but several views break on phones.*

### 2.1 Bed modal: collapse to stacked layout on mobile
**Law:** Fitts's Law — 960px modal on 375px phone is broken
**Files:** `succession.erb:334-519`
**Fix:** At `max-width: 640px`, switch to `flex-direction: column`. Canvas on top (50vh), sidebar below as scrollable sheet. Sidebar gets a drag handle for bottom-sheet behavior.

### 2.2 Touch targets: enforce 44px minimum on all interactive elements
**Law:** Fitts's Law
**Files:** All views
**Fix:** Audit every `<button>`, `<a>`, and clickable `<div>`. Add `@media (pointer: coarse) { min-height: 44px; min-width: 44px; }` to a shared style block. Key offenders:
- Task complete circles (22px → 44px)
- Stage advance pills (24px → 44px)
- Bed editor ⊕/━/┃ buttons (22px → 44px)
- Photo delete × (16px → 44px)
- Modal close × (26px → 44px)

### 2.3 Bed reorder: add touch support
**Law:** Jakob's Law — touch users expect drag-and-drop
**Files:** `plan-tab.js:startBedDrag`, `succession.erb:295-296`
**Fix:** Replace "Shift+drag" with long-press drag (500ms hold triggers drag mode). Add touch event handlers alongside mouse events.

### 2.4 Garden canvas: fit-to-content on load
**Files:** `garden.erb`
**Fix:** On init, calculate bounding box of all beds and set zoom/pan to fit them in view. Currently starts at zoom=1 with (0,0) origin regardless of bed positions.

---

## Session 3: Information Architecture & Navigation

*Fix broken navigation flows and orphaned pages.*

### 3.1 Kill `beds/show.erb` — it's orphaned and empty
**Law:** Law of Uniform Connectedness — orphaned pages break mental model
**Fix:** Remove the template. Change all "Details" links to open the bed modal instead. The modal already has everything the detail page has, plus editing.

### 3.2 Add cross-entity navigation links
**Law:** Law of Uniform Connectedness
**Fix:**
- Plant detail → link to its bed ("In bed: BB1" → opens bed modal)
- Seed packet → link to plants using that seed
- Task → link to its succession plan
- Bed modal → show succession plans targeting this bed

### 3.3 Fix the "List view →" dead link in garden.erb
**Law:** Jakob's Law — links should go somewhere
**Fix:** Remove the link (it redirects to `/garden` which is the current page). Or implement a real beds list at `/beds` as an alternative view.

### 3.4 Fix duplicate header on dashboard
**Files:** `dashboard.erb:4-9` and `layout.erb`
**Fix:** Remove the `<h1>GardenOS</h1>` from dashboard.erb — the layout already shows the garden name.

### 3.5 Scope seeds to garden
**Law:** Postel's Law — the app should not leak data between contexts
**Files:** `routes/seeds.rb`
**Fix:** Add `where(garden_id: @current_garden.id)` to all seed queries. Add a migration to assign existing seeds to the default garden.

### 3.6 Garden switching preserves current page
**Files:** `routes/dashboard.rb` (garden switch handler)
**Fix:** Read `Referer` header and redirect back to the same path after switching gardens.

---

## Session 4: Interaction Design — Bed Editor

*Make the bed planning workflow feel like a real tool.*

### 4.1 Search-first seed picker improvements
**Law:** Hick's Law — reduce choices
**Fix:**
- Auto-focus search input on modal open
- Sort seed chips by companion relevance (good first)
- Keep plant list visible while searching (don't hide it)

### 4.2 Simplify seed action buttons
**Law:** Hick's Law — 3 opaque symbol buttons per row is overwhelming
**Fix:** Single "Add" button per seed row (default: place at first available spot). Long-press or right-click → popover with "Place on grid / Add row / Add column".

### 4.3 Click-to-place ghost preview on canvas
**Law:** Doherty Threshold — feedback during interaction
**Fix:** In placing mode, render a semi-transparent preview rect on SVG following the cursor. Show red if position overlaps another plant. Add Escape key to cancel (document-level handler).

### 4.4 Drag-drop collision detection
**Law:** Postel's Law — prevent impossible states
**Fix:** During drag, check if drop target overlaps. Change drop indicator to red on collision. On drop, either reject (snap back) or warn.

### 4.5 Auto-arrange feedback
**Law:** Peak-End Rule — the peak creative moment needs a good ending
**Fix:** After distribute completes, show a toast: "Arranged 8 plants. Added 2 from seeds." The API already returns `moves` and `empty_pct`.

### 4.6 Fix the typo: `placingSeeed` → `placingSeed`
**Files:** `bed-editor.js:16,75,83,88,89`, `succession.erb:382`

---

## Session 5: Design System Consistency

*Unify the visual language across all views.*

### 5.1 Consolidate crop colors to one source
**Law:** Aesthetic-Usability Effect
**Currently defined in:** `beds/index.erb`, `plan-tab.js`, `bed-editor.js`, `shared/_bed_svg.erb`
**Fix:** Move to a single JSON file (`public/data/crop-colors.json`) loaded once. Or define in a `<script>` tag in `layout.erb` so all views share it.

### 5.2 Migrate inline styles to Tailwind
**Law:** Aesthetic-Usability Effect — inconsistent styles undermine trust
**Focus:** `succession.erb` is the worst offender (100% inline styles while other views use Tailwind)
**Fix:** Convert section by section. Start with task cards and the Plan summary strip.

### 5.3 Establish button hierarchy
**Law:** Von Restorff Effect — primary CTAs must stand out
**Fix:** Define 3 button tiers:
- **Primary:** `bg-green-900 text-white` — one per page, the main action
- **Secondary:** `border border-green-900 text-green-900` — supporting actions
- **Ghost:** `text-gray-500 hover:bg-gray-100` — tertiary/cancel actions
Apply consistently. Fix the "Cancel" button in plants/index select mode (currently green, should be ghost).

### 5.4 Minimum text size: 11px
**Law:** Fitts's Law (readability corollary)
**Fix:** Find and replace all `font-size: 9px` and `text-[9px]` with minimum 11px. Key offenders: timeline bed labels, crop legend, bed editor sidebar annotations.

### 5.5 Add focus rings for keyboard navigation
**Law:** Accessibility
**Fix:** Add `focus-visible:ring-2 focus-visible:ring-green-500` to all interactive elements. The tab bar `<a>` elements currently have no visible focus state.

---

## Session 6: Workflow Improvements

*Reduce friction in the most common daily tasks.*

### 6.1 Optimistic task completion (no reload)
**Law:** Doherty Threshold
**Fix:** Already covered in 1.3 but deserves its own task for the Plan tab. Fade out the completed task row, don't reload.

### 6.2 Stage advance consistency
**Law:** Law of Similarity — same action should look the same everywhere
**Fix:** Use one visual pattern for stage-advance buttons: compact pill with right-arrow icon. Apply in: Plan tab (task circles), Plants list (gray pills), Plant detail (full-width buttons).

### 6.3 Normalize `crop_type` to lowercase on save
**Law:** Postel's Law — accept liberal input, store canonical
**Files:** `routes/seeds.rb`, `routes/plants.rb`
**Fix:** `.to_s.strip.downcase` on crop_type before save. Prevents color/companion mismatches.

### 6.4 Replace free-text `crop_type` input with datalist
**Law:** Tesler's Law — move complexity from user to system
**Files:** `seeds/show.erb`
**Fix:** Use `<datalist>` populated with known crop types. User can still type freely but gets suggestions.

### 6.5 Validate stage progression direction
**Law:** Postel's Law — prevent impossible states
**Files:** `routes/plants.rb:batch_advance`, `models/plant.rb:advance_stage!`
**Fix:** Reject advances to stages before the current stage. The batch advance dropdown should only show forward stages.

### 6.6 Seed creation redirect fix
**Law:** Jakob's Law — create → view result
**Files:** `routes/seeds.rb:66`
**Fix:** `redirect "/seeds/#{packet.id}"` instead of `redirect "/seeds/new"`.

---

## Session 7: Progress & Motivation

*Help users see where they are and what's next.*

### 7.1 Plant lifecycle progress bar
**Law:** Zeigarnik Effect — show progress on incomplete tasks
**Files:** `plants/index.erb`
**Fix:** Thin progress line on each plant row: current_stage / total_stages as a green bar.

### 7.2 Season progress indicator
**Law:** Goal-Gradient Effect — show proximity to harvest
**Fix:** Thin bar in Plan summary strip showing position in growing season (frost-free period highlighted). Today marker. Already have the data (Prague: May 13 – Oct 15).

### 7.3 Fix the done/total counter in Plan tab
**Law:** Zeigarnik Effect — progress counter should be meaningful
**Files:** `routes/succession.rb:25-26`
**Fix:** Show "8 done · 7 remaining" instead of "8/15" (where 15 includes the 8 done).

### 7.4 Collapse "Later" tasks by default
**Law:** Serial Position Effect — end the visible list with the most actionable group
**Files:** `succession.erb:118-130`
**Fix:** Show "Later" as collapsed with "Show X more" link. The visible list ends with "This Week" tasks.

---

## Session 8: Polish & Delight

*The final 10% that makes the app feel loved.*

### 8.1 AI FAB: use recognizable icon + label
**Law:** Von Restorff Effect
**Fix:** Replace `✦` with Lucide `sparkles` SVG. Add "AI" text below. Pulse animation on first visit.

### 8.2 Empty bed quick-start
**Fix:** When a bed has 0 plants and the modal opens, show a prominent "What should I plant here?" card with (a) search seeds and (b) ask AI as two clear paths.

### 8.3 Companion data: expand and move to server
**Law:** Postel's Law — incomplete data gives false confidence
**Fix:** Move companion data to a JSON file or DB table. Expand coverage to all crop types. Serve via API so both bed-editor.js and the distribute algorithm share one source of truth.

### 8.4 Add color legend inside bed modal
**Law:** Miller's Law — don't make users memorize abbreviations
**Fix:** Small collapsible legend at the bottom of the canvas area showing crop type → color/abbreviation mapping.

### 8.5 Dashboard: remove nested tabs, use scroll sections
**Law:** Hick's Law — reduce simultaneous choices
**Fix:** Default to Tasks visible. Weather/Seeds/Insights as expandable accordion sections below.
