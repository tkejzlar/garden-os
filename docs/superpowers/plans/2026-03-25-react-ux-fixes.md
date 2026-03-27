# React SPA — UX Fixes

Issues found by code review of the bed editor components.

---

## Critical

### 1. Escape key should cancel placing mode, not close modal
**File:** `src/components/bed/BedModal.tsx:70-76`
**Problem:** The `<dialog>` native close event fires on Escape, which calls `onClose()` — closing the modal. If the user is in placing mode, Escape should cancel placing first.
**Fix:** Intercept the `cancel` event on the dialog (fires before `close` on Escape). If `placingSeed` is set, prevent default and cancel placing instead. Only let the modal close on Escape if nothing is in progress.

### 2. Placing mode persists after placing — should auto-cancel
**File:** `src/components/bed/BedModal.tsx:196-218`
**Problem:** After clicking to place a seed, `placingSeed` is never cleared. The user keeps placing copies.
**Fix:** Add `setPlacingSeed(null)` after the plant is created in `handlePlaceSeed`. If the user wants to place multiple, they can click "Place" again.

### 3. Row add creates N plants instead of one strip
**File:** `src/components/bed/BedModal.tsx:120-152`
**Problem:** `handleAddRow` fires N parallel `plants.create()` calls. Slow, creates clutter, hard to undo.
**Fix:** Create a single plant with `grid_w = cols * cell` (horizontal) or `grid_h = rows * cell` (vertical) and `quantity = count`. This matches how the Sinatra distribute algorithm handles row crops.

### 4. Search auto-focus interferes with canvas interactions
**File:** `src/components/bed/BedSidebar.tsx:39-41`
**Problem:** `inputRef.current?.focus()` on mount steals focus from the bed canvas. If the user opened the modal to drag plants, focus jumping to the sidebar is jarring.
**Fix:** Only auto-focus if the bed is empty (no plants). If the bed has plants, don't auto-focus — the user is more likely to interact with the canvas first.

---

## Major

### 5. Too many seed action buttons (Hick's Law)
**File:** `src/components/bed/BedSidebar.tsx:147-176`
**Problem:** 4 icon buttons per seed row (Place, Row, Column, Quick-add). In a 300px sidebar this is overwhelming and cramped.
**Fix:** Show just 2 buttons: "Place" (click on grid) and "+" (quick add at 0,0). Put Row/Col behind a long-press or context menu on the "+" button. Or: make the entire seed row clickable to start placing, with a single "+" for quick add.

### 6. Plant selection not toggled from canvas click
**File:** `src/components/bed/PlantRect.tsx:183-191`
**Problem:** Clicking a selected plant in the canvas doesn't deselect it (onClick always calls onSelect, never null).
**Fix:** The parent BedCanvas should check if the clicked plant is already selected and call `onSelectPlant(null)` in that case. Actually, PlantRect's `onSelect` callback is `() => onSelectPlant(plant.id)` — so the parent needs to toggle. Change to: `onSelect={() => onSelectPlant(selectedPlantId === plant.id ? null : plant.id)}`.

### 7. No Escape handling in placing mode from canvas
**File:** `src/components/bed/BedCanvas.tsx`
**Problem:** When in placing mode, pressing Escape while the canvas is focused does nothing (it bubbles to the dialog and closes it — see issue #1).
**Fix:** Combined with fix #1 — the modal intercepts Escape and cancels placing first.

### 8. Ghost preview doesn't account for plant size
**File:** `src/components/bed/BedCanvas.tsx:229-248`
**Problem:** Ghost preview is positioned at `ghost.x * CELL` but doesn't clamp to bed boundaries. The preview can extend past the bed edge.
**Fix:** Clamp ghost position: `Math.min(ghost.x, cols - gw)` and `Math.min(ghost.y, rows - gh)`.

---

## Minor

### 9. Duplicate plant position doesn't check for space
**File:** `src/components/bed/BedModal.tsx:165-185`
**Problem:** Duplicate places at `grid_x + grid_w` which may be out of bounds.
**Fix:** Wrap position: if `x + w > cols`, try `x = 0, y = y + h` (next row).

### 10. "Add more" chips section always shows first 12 seeds by insertion order
**File:** `src/components/bed/BedSidebar.tsx:292-314`
**Problem:** Not sorted by companion relevance.
**Fix:** Sort by companion status (good first) before slicing.

### 11. No loading state in sidebar during mutations
**Problem:** When adding/removing plants, the sidebar shows no feedback until the toast appears.
**Fix:** The `saving` state exists in BedModal but isn't passed to BedSidebar. Pass it through and show a subtle loading indicator on the action that triggered it.

### 12. Dialog sizing on mobile
**File:** `src/components/bed/BedModal.tsx:238-241`
**Problem:** `max-sm:h-full` makes the dialog full-screen on mobile with no visible backdrop. Feels like a page transition, not a modal.
**Fix:** Change to `max-sm:h-[95dvh]` with `max-sm:rounded-t-2xl` for a bottom-sheet feel.
