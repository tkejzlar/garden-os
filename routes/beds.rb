# routes/beds.rb
require_relative "../models/bed"
require_relative "../models/plant"
require "json"

class GardenApp

  # Page routes removed — React SPA serves /garden and /beds

  # ── Existing bed detail (preserved) ─────────────────────────────────────────

  get "/beds/:id" do
    bed = Bed[params[:id].to_i]
    halt 404 unless bed
    redirect "/succession?bed=#{bed.id}"
  end

  # ── Existing beds JSON API (preserved) ───────────────────────────────────────

  get "/api/beds/:id" do
    bed = Bed.where(id: params[:id].to_i, garden_id: @current_garden.id).first
    halt 404, json(error: "Bed not found") unless bed
    active_plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
    json({
      id: bed.id, name: bed.name,
      width_cm: bed.width, length_cm: bed.length,
      grid_cols: bed.grid_cols, grid_rows: bed.grid_rows,
      canvas_color: bed.canvas_color,
      canvas_x: bed.canvas_x, canvas_y: bed.canvas_y,
      canvas_width: bed.canvas_width, canvas_height: bed.canvas_height,
      canvas_points: bed.canvas_points_array,
      bed_type: bed.bed_type,
      position: bed.position,
      plants: active_plants.map { |p|
        { id: p.id, variety_name: p.variety_name, crop_type: p.crop_type,
          lifecycle_stage: p.lifecycle_stage,
          grid_x: p.grid_x, grid_y: p.grid_y, grid_w: p.grid_w, grid_h: p.grid_h,
          quantity: p.quantity, notes: p.notes }
      }
    })
  end

  get "/api/beds" do
    beds = Bed.where(garden_id: @current_garden.id).all.map do |bed|
      active_plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
      {
        id: bed.id, name: bed.name,
        width_cm: bed.width, length_cm: bed.length,
        grid_cols: bed.grid_cols, grid_rows: bed.grid_rows,
        canvas_color: bed.canvas_color,
        canvas_x: bed.canvas_x, canvas_y: bed.canvas_y,
        canvas_width: bed.canvas_width, canvas_height: bed.canvas_height,
        canvas_points: bed.canvas_points_array,
        bed_type: bed.bed_type,
        plants: active_plants.map { |p|
          { id: p.id, variety_name: p.variety_name, crop_type: p.crop_type,
            lifecycle_stage: p.lifecycle_stage,
            grid_x: p.grid_x, grid_y: p.grid_y, grid_w: p.grid_w, grid_h: p.grid_h,
            quantity: p.quantity, notes: p.notes }
        }
      }
    end
    json beds
  end

  # ── API: reorder beds ─────────────────────────────────────────────────────────
  patch "/api/beds/reorder" do
    content_type :json
    request.body.rewind
    body = begin JSON.parse(request.body.read) rescue halt 400, json(error: "Invalid JSON") end

    ids = body["bed_ids"]
    halt 400, json(error: "bed_ids array required") unless ids.is_a?(Array)

    DB.transaction do
      ids.each_with_index do |id, i|
        Bed.where(id: id.to_i, garden_id: @current_garden.id).update(position: i)
      end
    end
    json(ok: true)
  end

  # ── API: create a new bed ────────────────────────────────────────────────────
  # POST /api/beds
  # Body (JSON): { name, bed_type?, canvas_x?, canvas_y?, canvas_width?, canvas_height?,
  #                canvas_points?, canvas_color? }

  post "/api/beds" do
    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue JSON::ParserError
      halt 400, json(error: "Invalid JSON")
    end

    name = body["name"].to_s.strip
    halt 422, json(error: "name is required") if name.empty?

    attrs = { name: name, garden_id: @current_garden.id }
    attrs[:bed_type]      = body["bed_type"]      if body.key?("bed_type")
    attrs[:canvas_x]      = body["canvas_x"]&.to_f
    attrs[:canvas_y]      = body["canvas_y"]&.to_f
    attrs[:canvas_width]  = body["canvas_width"]&.to_f
    attrs[:canvas_height] = body["canvas_height"]&.to_f
    attrs[:canvas_color]  = body["canvas_color"]
    attrs[:canvas_points] = body["canvas_points"].is_a?(Array) \
                              ? body["canvas_points"].to_json \
                              : body["canvas_points"]

    bed = Bed.new(attrs)
    if bed.valid? && bed.save
      status 201
      json bed.values
    else
      halt 422, json(error: bed.errors.full_messages.join(", "))
    end
  end

  # ── API: update canvas position / size ──────────────────────────────────────
  # PATCH /api/beds/:id/position
  # Body (JSON): { canvas_x, canvas_y, canvas_width?, canvas_height?, canvas_points?, canvas_color? }

  patch "/api/beds/:id/position" do
    bed = Bed[params[:id].to_i]
    halt 404, json(error: "Bed not found") unless bed

    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue JSON::ParserError
      halt 400, json(error: "Invalid JSON")
    end

    update = {}
    update[:canvas_x]      = body["canvas_x"].to_f      if body.key?("canvas_x")
    update[:canvas_y]      = body["canvas_y"].to_f      if body.key?("canvas_y")
    if body.key?("canvas_width")
      update[:canvas_width] = body["canvas_width"].to_f
      update[:width] = body["canvas_width"].to_f.round  # sync real dimensions (cm)
    end
    if body.key?("canvas_height")
      update[:canvas_height] = body["canvas_height"].to_f
      update[:length] = body["canvas_height"].to_f.round  # sync real dimensions (cm)
    end
    update[:canvas_color]  = body["canvas_color"]       if body.key?("canvas_color")
    if body.key?("canvas_points")
      pts = body["canvas_points"]
      update[:canvas_points] = pts.is_a?(Array) ? pts.to_json : pts
    end

    bed.update(update)
    json bed.reload.values
  end

  # ── API: update bed properties ───────────────────────────────────────────────
  # PATCH /api/beds/:id
  # Body (JSON): { name?, bed_type?, orientation?, wall_type?, notes?,
  #                canvas_x?, canvas_y?, canvas_width?, canvas_height?,
  #                canvas_points?, canvas_color? }

  patch "/api/beds/:id" do
    bed = Bed[params[:id].to_i]
    halt 404, json(error: "Bed not found") unless bed

    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue JSON::ParserError
      halt 400, json(error: "Invalid JSON")
    end

    allowed = %w[name bed_type orientation wall_type notes
                 canvas_x canvas_y canvas_width canvas_height canvas_color]
    update = body.slice(*allowed).transform_keys(&:to_sym)
    update[:canvas_x]      = update[:canvas_x].to_f      if update[:canvas_x]
    update[:canvas_y]      = update[:canvas_y].to_f      if update[:canvas_y]
    update[:canvas_width]  = update[:canvas_width].to_f  if update[:canvas_width]
    update[:canvas_height] = update[:canvas_height].to_f if update[:canvas_height]

    if body.key?("canvas_points")
      pts = body["canvas_points"]
      update[:canvas_points] = pts.is_a?(Array) ? pts.to_json : pts
    end

    bed.update(update)
    json bed.reload.values
  end

  # ── Distribute: LLM designs row layout, algorithm computes coordinates ────
  post "/beds/:id/distribute" do
    content_type :json
    bed = Bed[params[:id].to_i]
    halt 404, json(error: "Bed not found") unless bed
    halt 403, json(error: "Not your bed") unless bed.garden_id == @current_garden.id

    plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
    halt 200, json(ok: true, moves: 0) if plants.empty?

    # Ensure fresh crop sizing (cache may be stale after migrations)
    require_relative "../models/crop_default"
    CropDefault.clear_cache!

    cols = bed.grid_cols
    rows = bed.grid_rows

    plant_list = plants.map { |p|
      w, h = Plant.default_grid_size(p.crop_type)
      "#{p.id}:#{p.variety_name}(#{p.crop_type},#{w}x#{h})"
    }.join(", ")

    # Ask LLM for ordering — large plants first (north), then small companions
    prompt = <<~PROMPT
      You are a companion planting expert. Order these plants for a garden bed.
      The algorithm will place large plants in a 2D grid and tuck small companions
      into the gaps between them. You just decide the ORDER.

      Plants: #{plant_list}

      Rules:
      - ALL large plants (tomato, pepper, squash, cucumber, eggplant, bean, pea) first.
        Order them north-to-south: tallest varieties first.
      - THEN all small plants (herb, basil, lettuce, radish, onion, flower, spinach, etc.).
        Order small plants so the BEST companions come first — they'll be placed nearest
        to the large plants. E.g. basil first (great tomato companion), then herbs, then
        lettuce, then flowers, then root veg.

      Return ONLY a JSON array of plant IDs. Example: [12,5,13,8,3,9,7]
      Every ID exactly once.
    PROMPT

    require_relative "../config/ruby_llm"
    model_id = ENV.fetch("GARDEN_AI_MODEL", "gpt-4o")
    provider = if model_id.start_with?("claude") then :anthropic
               elsif model_id.start_with?("gemini") then :gemini
               else :openai end

    response = RubyLLM.chat(model: model_id, provider: provider, assume_model_exists: true)
      .ask(prompt)

    raw = response.content.strip.gsub(/\A```json\s*/, "").gsub(/\s*```\z/, "")
    ordered_ids = begin JSON.parse(raw) rescue halt 422, json(error: "AI returned invalid JSON", raw: raw) end
    ordered_ids = Array(ordered_ids).flatten.map(&:to_i)

    # Build plant lookup, ensure every plant is in the list
    plant_map = plants.each_with_object({}) { |p, h| h[p.id] = p }
    missing_ids = plants.map(&:id) - ordered_ids
    ordered_ids = (ordered_ids + missing_ids).uniq.select { |id| plant_map[id] }

    # Row crops: these are sown as full-width strips, not individual dots
    row_crops = %w[radish carrot onion spinach]

    # Categorize plants: large (≥5×5 = 25cm+), row crops (1×1 sown as strips), small (rest)
    large = []
    row_crop_plants = []
    small = []
    ordered_ids.each do |id|
      p = plant_map[id]
      w, h = Plant.default_grid_size(p.crop_type)
      crop = p.crop_type.to_s.downcase
      entry = { plant: p, w: w, h: h, crop: crop }
      if w >= 5 && h >= 5
        large << entry
      elsif row_crops.include?(crop)
        row_crop_plants << entry
      else
        small << entry
      end
    end

    # Occupancy grid
    grid = Array.new(rows) { Array.new(cols, false) }

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

    area_free = ->(x, y, w, h) {
      return false if x < 0 || y < 0 || x + w > cols || y + h > rows
      (y...y + h).all? { |cy| (x...x + w).all? { |cx| !grid[cy][cx] } }
    }

    placements = []

    # ── Step 1: Place large plants spread across the FULL bed height ──
    if large.any?
      pw = large.first[:w]
      ph = large.first[:h]
      per_row = cols / pw
      num_large_rows = (large.size.to_f / per_row).ceil

      # Horizontal: even margins between plants
      total_plant_w = [per_row, large.size].min * pw
      h_margin = (cols - total_plant_w).to_f / ([per_row, large.size].min + 1)

      # Vertical: spread across full bed, not packed at top
      total_large_h = num_large_rows * ph
      v_gap = (rows - total_large_h).to_f / (num_large_rows + 1)
      v_gap = [v_gap, 0].max

      large.each_with_index do |entry, i|
        col_i = i % per_row
        row_i = i / per_row
        plants_in_this_row = [large.size - row_i * per_row, per_row].min

        # Recalculate horizontal margin for partial last row
        row_plant_w = plants_in_this_row * pw
        row_h_margin = (cols - row_plant_w).to_f / (plants_in_this_row + 1)

        x = (row_h_margin + col_i * (pw + row_h_margin)).round
        y = (v_gap + row_i * (ph + v_gap)).round

        x = [x, cols - entry[:w]].min
        y = [y, rows - entry[:h]].min

        mark_plant.call(x, y, entry[:w], entry[:h], true)
        placements << { plant: entry[:plant], x: x, y: y, w: entry[:w], h: entry[:h] }
      end
    end

    # ── Step 2: Place row crops as strips toward the SOUTH (bottom) of bed ──
    row_crop_plants.each do |entry|
      strip_h = entry[:h]
      # Strip width = plant's quantity × single width, capped at bed width
      qty = entry[:plant].quantity.to_i
      qty = 5 if qty <= 1  # minimum sensible row = 5 plants
      single_w = entry[:w]
      strip_w = [qty * single_w, cols].min

      best_y = nil
      best_score = -Float::INFINITY

      (0..rows - strip_h).each do |y|
        # Check if strip fits at this y
        # Find a contiguous free run wide enough
        free_run = 0
        max_run = 0
        (0...cols).each do |x|
          if (y...y + strip_h).all? { |cy| !grid[cy][x] }
            free_run += 1
            max_run = [max_run, free_run].max
          else
            free_run = 0
          end
        end
        next if max_run < strip_w

        # Score: strongly prefer SOUTH (bottom) of bed for short crops
        score = y.to_f * 2.0  # higher y = further south = better
        # Mild companion proximity bonus
        placements.each do |placed|
          dy = (y + strip_h / 2.0 - placed[:y] - placed[:h] / 2.0).abs
          score += (15.0 - dy) * 0.3 if dy < 15
        end

        if score > best_score
          best_score = score
          best_y = y
        end
      end

      next unless best_y
      # Find the starting x for the strip (first contiguous free run)
      strip_x = 0
      free_run = 0
      (0...cols).each do |x|
        if (best_y...best_y + strip_h).all? { |cy| !grid[cy][x] }
          strip_x = x - free_run if free_run == 0
          free_run += 1
          if free_run >= strip_w
            strip_x = x - strip_w + 1
            break
          end
        else
          free_run = 0
          strip_x = x + 1
        end
      end

      # Mark and place
      actual_w = [strip_w, cols - strip_x].min
      (strip_x...strip_x + actual_w).each do |x|
        (best_y...best_y + strip_h).each { |cy| grid[cy][x] = true if cy < rows && x < cols }
      end
      plants_in_strip = actual_w / [single_w, 1].max
      placements << { plant: entry[:plant], x: strip_x, y: best_y, w: actual_w, h: strip_h, quantity: plants_in_strip }
    end

    # ── Step 3: Place small companion plants in gaps ──
    companions = {
      "tomato"   => %w[basil herb carrot lettuce radish onion flower celery],
      "pepper"   => %w[basil herb carrot onion lettuce tomato],
      "eggplant" => %w[basil herb lettuce bean pepper],
      "cucumber" => %w[radish lettuce bean pea flower onion],
      "squash"   => %w[radish bean flower onion corn],
      "zucchini" => %w[radish bean flower onion corn],
      "melon"    => %w[corn radish flower],
      "bean"     => %w[carrot radish lettuce cucumber squash corn celery eggplant],
      "pea"      => %w[carrot radish lettuce cucumber corn],
      "lettuce"  => %w[carrot radish onion bean],
      "carrot"   => %w[tomato lettuce onion pea radish bean],
      "radish"   => %w[lettuce pea bean cucumber carrot spinach],
      "onion"    => %w[carrot lettuce tomato pepper],
      "kale"     => %w[bean onion lettuce spinach herb],
      "chard"    => %w[bean onion lettuce],
      "basil"    => %w[tomato pepper lettuce],
      "herb"     => %w[tomato pepper carrot lettuce],
      "flower"   => %w[tomato cucumber squash bean],
    }

    small.each do |entry|
      w, h = entry[:w], entry[:h]
      crop = entry[:crop]
      best_pos = nil
      best_score = -Float::INFINITY

      (0..rows - h).each do |y|
        (0..cols - w).each do |x|
          next unless area_free.call(x, y, w, h)

          score = 0.0
          placements.each do |placed|
            pc = placed[:plant].crop_type.to_s.downcase
            is_companion = (companions[pc] || []).include?(crop)
            dx = (x + w / 2.0 - placed[:x] - placed[:w] / 2.0).abs
            dy = (y + h / 2.0 - placed[:y] - placed[:h] / 2.0).abs
            dist = dx + dy
            score += (20.0 - dist) * 2 if is_companion
            score += (10.0 - dist) * 0.3 if dist < 10
          end

          # Spread across bed — prefer positions that fill empty vertical zones
          score += y * 0.1

          if score > best_score
            best_score = score
            best_pos = [x, y]
          end
        end
      end

      next unless best_pos
      x, y = best_pos
      mark_plant.call(x, y, w, h, false)
      placements << { plant: entry[:plant], x: x, y: y, w: w, h: h }
    end

    # ── Step 4: If bed is >30% empty, suggest plants from seed inventory ──
    total_cells = cols * rows
    occupied = grid.sum { |row| row.count(true) }
    empty_pct = ((total_cells - occupied).to_f / total_cells * 100).round

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
        planted_crops = placements.map { |p| p[:plant].crop_type.to_s.downcase }.uniq

        suggest_prompt = <<~PROMPT
          A garden bed (#{cols * 5}cm x #{rows * 5}cm) has #{empty_pct}% empty space after
          placing existing plants. Suggest 2-4 additional plants from this seed inventory
          to fill the gaps. Consider companion planting with what's already there: #{planted_crops.join(", ")}.

          Available seeds: #{seeds.join(", ")}

          Return ONLY a JSON array of objects: [{"variety_name": "X", "crop_type": "Y"}]
          Only use varieties from the list above.
        PROMPT

        suggest_response = RubyLLM.chat(model: model_id, provider: provider, assume_model_exists: true)
          .ask(suggest_prompt)
        suggest_raw = suggest_response.content.strip.gsub(/\A```json\s*/, "").gsub(/\s*```\z/, "")
        suggestions = begin JSON.parse(suggest_raw) rescue [] end

        suggestions.each do |s|
          next unless s["variety_name"] && s["crop_type"]
          w, h = Plant.default_grid_size(s["crop_type"])

          best_pos = nil
          best_score = -Float::INFINITY
          (0..rows - h).each do |sy|
            (0..cols - w).each do |sx|
              next unless area_free.call(sx, sy, w, h)
              score = 0.0
              placements.each do |placed|
                pc = placed[:plant].crop_type.to_s.downcase
                is_comp = (companions[pc] || []).include?(s["crop_type"].downcase)
                dist = (sx + w / 2.0 - placed[:x] - placed[:w] / 2.0).abs + (sy + h / 2.0 - placed[:y] - placed[:h] / 2.0).abs
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

    # Apply to database
    moved = 0
    DB.transaction do
      placements.each do |p|
        update_hash = { grid_x: p[:x], grid_y: p[:y], grid_w: p[:w], grid_h: p[:h], updated_at: Time.now }
        update_hash[:quantity] = p[:quantity] if p[:quantity]
        p[:plant].update(update_hash)
        moved += 1
      end
    end

    suggested = placements.count { |p| p[:plant].lifecycle_stage == "seed_packet" && p[:plant].new? rescue false }
    json(ok: true, moves: moved, empty_pct: empty_pct)
  end


  # ── API: delete bed ──────────────────────────────────────────────────────────
  delete "/api/beds/:id" do
    bed = Bed[params[:id].to_i]
    halt 404, json(error: "Bed not found") unless bed

    bed.destroy
    json(success: true)
  end

end
