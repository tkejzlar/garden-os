# Bed Distribute Improvements

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the "AI Distribute" feature produce realistic garden layouts by doubling grid resolution, adding seed suggestions for empty space, and rendering row crops as quantity-aware strips.

**Architecture:** Three independent changes: (1) halve cell size from 10cm to 5cm so plants have finer positioning granularity, (2) after distributing, calculate empty %, ask LLM to suggest plants from seed inventory if >30% empty, (3) row crops (radish/carrot/onion) render as strips with quantity matching their width.

**Tech Stack:** Ruby/Sequel, Alpine.js, SVG, RubyLLM

---

## File Map

| File | Change | Purpose |
|------|--------|---------|
| `models/bed.rb` | Modify | Change divisor 10.0 → 5.0 in `grid_cols`/`grid_rows` |
| `models/plant.rb` | Modify | Double all `CROP_SPACING` values |
| `models/crop_default.rb` | No change | Already reads from DB |
| `db/migrations/017_refine_grid_resolution.rb` | Create | Double existing plant grid positions + crop_defaults |
| `public/js/bed-editor.js` | Modify | `cell: 10` → `cell: 5` |
| `views/shared/_bed_svg.erb` | Modify | `cell = 10` → `cell = 5` |
| `routes/beds.rb` | Modify | Update distribute: large threshold, row crop quantity, LLM seed suggestions |
| `services/plan_committer.rb` | Verify | Uses `bed.grid_cols` dynamically — should just work |

---

### Task 1: Grid Resolution — Migration

**Files:**
- Create: `db/migrations/017_refine_grid_resolution.rb`

- [ ] **Step 1: Write migration that doubles all grid positions and crop defaults**

```ruby
Sequel.migration do
  up do
    # Double all plant grid positions/sizes (10cm cells → 5cm cells)
    self[:plants].all.each do |plant|
      self[:plants].where(id: plant[:id]).update(
        grid_x: (plant[:grid_x] || 0) * 2,
        grid_y: (plant[:grid_y] || 0) * 2,
        grid_w: (plant[:grid_w] || 1) * 2,
        grid_h: (plant[:grid_h] || 1) * 2
      )
    end

    # Double crop_defaults grid sizes
    self[:crop_defaults].all.each do |cd|
      self[:crop_defaults].where(id: cd[:id]).update(
        grid_w: cd[:grid_w] * 2,
        grid_h: cd[:grid_h] * 2
      )
    end
  end

  down do
    self[:plants].all.each do |plant|
      self[:plants].where(id: plant[:id]).update(
        grid_x: (plant[:grid_x] || 0) / 2,
        grid_y: (plant[:grid_y] || 0) / 2,
        grid_w: [plant[:grid_w].to_i / 2, 1].max,
        grid_h: [plant[:grid_h].to_i / 2, 1].max
      )
    end
    self[:crop_defaults].all.each do |cd|
      self[:crop_defaults].where(id: cd[:id]).update(
        grid_w: [cd[:grid_w] / 2, 1].max,
        grid_h: [cd[:grid_h] / 2, 1].max
      )
    end
  end
end
```

- [ ] **Step 2: Run migration**

Run: `ruby -e "require_relative 'config/database'; Sequel::Migrator.run(DB, 'db/migrations')"`

- [ ] **Step 3: Verify data migrated**

Run: `ruby -e 'require_relative "config/database"; require_relative "models/crop_default"; CropDefault.all.each { |c| puts "#{c.name}: #{c.grid_w}x#{c.grid_h}" }'`
Expected: tomato: 6x6, lettuce: 4x4, radish: 2x2, etc. (all doubled)

- [ ] **Step 4: Commit**

```bash
git add db/migrations/017_refine_grid_resolution.rb
git commit -m "feat: migration to double grid positions for 5cm cell resolution"
```

---

### Task 2: Grid Resolution — Model + Frontend Constants

**Files:**
- Modify: `models/bed.rb:17,28` — change `10.0` to `5.0`
- Modify: `models/plant.rb:15-35` — double `CROP_SPACING` fallback values
- Modify: `public/js/bed-editor.js:8` — `cell: 10` to `cell: 5`
- Modify: `views/shared/_bed_svg.erb:13` — `cell = 10` to `cell = 5`

- [ ] **Step 1: Update bed.rb grid calculations**

In `models/bed.rb`, change both `grid_cols` and `grid_rows` methods:
- `(w / 10.0).ceil.clamp(1, 50)` → `(w / 5.0).ceil.clamp(1, 100)`
- `(l / 10.0).ceil.clamp(1, 50)` → `(l / 5.0).ceil.clamp(1, 100)`

Also update the max clamp from 50 to 100 since grid dimensions doubled.

- [ ] **Step 2: Update plant.rb CROP_SPACING fallback**

Double all values in the `CROP_SPACING` hash. These are fallbacks only (DB is primary via `CropDefault`):
```ruby
"tomato" => [6, 6], "pepper" => [6, 6], "eggplant" => [6, 6],
"lettuce" => [4, 4], "spinach" => [2, 4], "chard" => [4, 6], "kale" => [6, 6],
"herb" => [4, 4], "basil" => [4, 4], "cucumber" => [6, 6],
"squash" => [8, 8], "zucchini" => [6, 8], "melon" => [8, 8],
"flower" => [4, 4], "radish" => [2, 2], "carrot" => [2, 2], "onion" => [2, 2],
"bean" => [4, 4], "pea" => [2, 4]
```

- [ ] **Step 3: Update bed-editor.js cell constant**

Line 8: `cell: 10` → `cell: 5`

- [ ] **Step 4: Update _bed_svg.erb cell constant**

Line 13: `cell = 10` → `cell = 5`

- [ ] **Step 5: Clear CropDefault cache**

Since we migrated the DB values, clear the in-memory cache on next restart. The `CropDefault.clear_cache!` method exists. No code change needed — cache clears on server restart.

- [ ] **Step 6: Verify bed editor renders correctly**

Start server, open a bed modal. Grid should be 2× finer. Existing plants should appear at the same physical positions (doubled grid coords × halved cell size = same SVG position).

- [ ] **Step 7: Commit**

```bash
git add models/bed.rb models/plant.rb public/js/bed-editor.js views/shared/_bed_svg.erb
git commit -m "feat: 5cm grid resolution — finer plant positioning"
```

---

### Task 3: Update Distribute Algorithm Thresholds

**Files:**
- Modify: `routes/beds.rb` — distribute endpoint

- [ ] **Step 1: Update large plant threshold**

In the distribute endpoint, the large/small separator uses `w >= 3 && h >= 3`. With doubled grid, this should be `w >= 5 && h >= 5` (plants ≥25cm in both dimensions = large).

```ruby
# Before:
if w >= 3 && h >= 3
# After:
if w >= 5 && h >= 5
```

- [ ] **Step 2: Update circular reservation corner skip**

The `mark_plant` lambda skips corners for `w >= 3 && h >= 3`. Update to `w >= 5 && h >= 5`. Also, with larger grid sizes, skip more than 1 corner cell — skip a 2×2 corner triangle for plants ≥6×6:

```ruby
mark_plant = ->(x, y, w, h, circular) {
  (y...y + h).each do |cy|
    (x...x + w).each do |cx|
      next if cx < 0 || cy < 0 || cx >= cols || cy >= rows
      if circular && w >= 5 && h >= 5
        # Skip corner triangles for circular canopy
        dx_left = cx - x
        dx_right = (x + w - 1) - cx
        dy_top = cy - y
        dy_bot = (y + h - 1) - cy
        corner_dist = [dx_left + dy_top, dx_right + dy_top, dx_left + dy_bot, dx_right + dy_bot].min
        next if corner_dist <= 1  # skip ~2-cell corner triangles
      end
      grid[cy][cx] = true
    end
  end
}
```

- [ ] **Step 3: Commit**

```bash
git add routes/beds.rb
git commit -m "feat: update distribute thresholds for 5cm grid"
```

---

### Task 4: Row Crop Quantities

**Files:**
- Modify: `routes/beds.rb` — distribute endpoint, row crop placement section

- [ ] **Step 1: Update row crop strip placement to set quantity**

When placing a row crop as a full-width strip, set the plant's `quantity` to match how many individual plants the strip represents (strip_width / single_plant_width):

In the row crop placement section, after determining the strip placement, update the plant's quantity:

```ruby
# After placing the strip:
single_w = entry[:w]  # original crop width (e.g., 2 cells for radish at 5cm grid)
strip_cells = cols     # full bed width in cells
plants_in_strip = strip_cells / [single_w, 1].max
placements << { plant: entry[:plant], x: 0, y: best_y, w: cols, h: strip_h, quantity: plants_in_strip }
```

Then in the DB update section, save the quantity:

```ruby
DB.transaction do
  placements.each do |p|
    update_hash = { grid_x: p[:x], grid_y: p[:y], grid_w: p[:w], grid_h: p[:h], updated_at: Time.now }
    update_hash[:quantity] = p[:quantity] if p[:quantity]
    p[:plant].update(update_hash)
    moved += 1
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add routes/beds.rb
git commit -m "feat: row crops set quantity based on strip width"
```

---

### Task 5: Seed Suggestions for Empty Space

**Files:**
- Modify: `routes/beds.rb` — distribute endpoint, add post-placement LLM call

- [ ] **Step 1: Calculate empty percentage after placement**

After all existing plants are placed, count free cells:

```ruby
total_cells = cols * rows
occupied = grid.sum { |row| row.count(true) }
empty_pct = ((total_cells - occupied).to_f / total_cells * 100).round
```

- [ ] **Step 2: If >30% empty, ask LLM for seed suggestions**

```ruby
if empty_pct > 30
  seeds = begin
    require_relative "../models/seed_packet"
    SeedPacket.where(garden_id: @current_garden.id).all.map { |s|
      "#{s.variety_name}(#{s.crop_type})"
    }
  rescue
    []
  end

  if seeds.any?
    # List what's already planted
    planted_crops = placements.map { |p| p[:plant].crop_type.to_s.downcase }.uniq
    seed_list = seeds.reject { |s| planted_crops.any? { |pc| s.downcase.include?(pc) } }

    if seed_list.any?
      suggest_prompt = <<~PROMPT
        A garden bed (#{cols * 5}cm × #{rows * 5}cm) has #{empty_pct}% empty space after
        placing existing plants. Suggest 2-4 additional plants from this seed inventory
        to fill the gaps. Consider companion planting with what's already there: #{planted_crops.join(", ")}.

        Available seeds: #{seed_list.join(", ")}

        Return ONLY a JSON array of objects: [{"variety_name": "X", "crop_type": "Y"}]
        Keep it short — only varieties from the list above.
      PROMPT

      suggest_response = RubyLLM.chat(model: model_id, provider: provider, assume_model_exists: true)
        .ask(suggest_prompt)
      suggest_raw = suggest_response.content.strip.gsub(/\A```json\s*/, "").gsub(/\s*```\z/, "")
      suggestions = begin JSON.parse(suggest_raw) rescue [] end

      # Create new plants and place them in empty space
      suggestions.each do |s|
        next unless s["variety_name"] && s["crop_type"]
        w, h = Plant.default_grid_size(s["crop_type"])

        # Find best free position (companion scoring)
        best_pos = nil
        best_score = -Float::INFINITY
        (0..rows - h).each do |sy|
          (0..cols - w).each do |sx|
            next unless area_free.call(sx, sy, w, h)
            score = 0.0
            placements.each do |placed|
              pc = placed[:plant].crop_type.to_s.downcase
              is_comp = (companions[pc] || []).include?(s["crop_type"].downcase)
              dist = (sx + w/2.0 - placed[:x] - placed[:w]/2.0).abs + (sy + h/2.0 - placed[:y] - placed[:h]/2.0).abs
              score += (20.0 - dist) * 2 if is_comp
            end
            if score > best_score
              best_score = score
              best_pos = [sx, sy]
            end
          end
        end

        next unless best_pos
        new_plant = Plant.create(
          garden_id: @current_garden.id, bed_id: bed.id,
          variety_name: s["variety_name"], crop_type: s["crop_type"],
          grid_x: best_pos[0], grid_y: best_pos[1], grid_w: w, grid_h: h,
          quantity: 1, lifecycle_stage: "seed_packet"
        )
        mark_plant.call(best_pos[0], best_pos[1], w, h, w >= 5 && h >= 5)
        placements << { plant: new_plant, x: best_pos[0], y: best_pos[1], w: w, h: h }
      end
    end
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add routes/beds.rb
git commit -m "feat: LLM suggests seeds to fill empty bed space after distribute"
```

---

### Task 6: Smoke Test

- [ ] **Step 1: Run migration and start server**

```bash
ruby -e "require_relative 'config/database'; Sequel::Migrator.run(DB, 'db/migrations')"
```

- [ ] **Step 2: Test bed editor renders correctly**

Open a bed modal. Grid should be 2× finer. Existing plants at correct positions.

- [ ] **Step 3: Test distribute on a full bed**

Click "AI Distribute" on a bed with many plants. Verify:
- Plants spread across full bed
- Companions tucked in corners between large plants
- Row crops as full-width strips
- No overlap

- [ ] **Step 4: Test distribute on a sparse bed**

Click "AI Distribute" on a bed with few plants. Verify:
- Existing plants distributed
- LLM suggests new plants from seed inventory
- New plants created and placed in gaps

- [ ] **Step 5: Final commit if any fixes needed**
