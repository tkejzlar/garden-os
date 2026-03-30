require "json"
require_relative "../config/ruby_llm"
require_relative "../models/planner_message"
require_relative "garden_logger"
require_relative "planner_tools/get_beds_tool"
require_relative "planner_tools/get_seed_inventory_tool"
require_relative "planner_tools/get_plants_tool"
require_relative "planner_tools/get_succession_plans_tool"
require_relative "planner_tools/get_weather_tool"
require_relative "planner_tools/draft_plan_tool"
require_relative "planner_tools/draft_bed_layout_tool"
require_relative "planner_tools/request_feature_tool"
require_relative "planner_tools/clear_bed_tool"
require_relative "planner_tools/remove_plants_tool"
require_relative "planner_tools/move_plant_tool"
require_relative "planner_tools/update_plant_tool"
require_relative "planner_tools/delete_succession_plan_tool"
require_relative "planner_tools/place_row_tool"
require_relative "planner_tools/place_column_tool"
require_relative "planner_tools/place_single_tool"
require_relative "planner_tools/place_border_tool"
require_relative "planner_tools/place_fill_tool"
require_relative "planner_tools/manage_zones_tool"
require_relative "planner_tools/update_bed_metadata_tool"
require_relative "planner_tools/deduplicate_bed_tool"
require_relative "planner_tools/set_plant_notes_tool"
require_relative "planner_tools/update_succession_plan_tool"
require_relative "planner_tools/deduplicate_succession_plans_tool"
require_relative "planner_tools/place_in_zone_tool"
require_relative "planner_tools/align_plants_tool"
require_relative "planner_tools/group_edit_tool"
require_relative "planner_tools/place_band_tool"
require_relative "planner_tools/copy_layout_tool"
require_relative "planner_tools/get_empty_space_tool"
require_relative "planner_tools/draft_variants_tool"

class PlannerService
  attr_reader :last_draft

  def self.model_id  = ENV.fetch("GARDEN_AI_MODEL", "gpt-4o")
  def self.provider
    m = model_id
    if m.start_with?("claude") then :anthropic
    elsif m.start_with?("gemini") then :gemini
    else :openai
    end
  end

  def initialize
    @last_draft = nil
    @tool_calls = []
    @garden_id = Thread.current[:current_garden_id]
  end

  def system_prompt
    garden = @garden_id ? (require_relative "../models/garden"; Garden.first(id: @garden_id)) : nil
    garden_name = garden&.name || "the garden"
    <<~PROMPT
      You are a garden planning consultant for #{garden_name}, a productive vegetable garden in Prague,
      Czech Republic (zone 6b/7a, last frost ~May 13, first frost ~Oct 15, continental climate).

      ALWAYS use the available tools to look up the garden's actual data before making
      recommendations. Don't assume — check the beds, seeds, and existing plants.

      IMPORTANT ABOUT BEDS:
      - Use ONLY bed names returned by get_beds. Never invent bed names.
      - Beds may or may not have rows/slots configured yet — that's OK.
      - When assigning plants to beds, just specify the bed_name and the variety.
        Do NOT worry about row_name or slot_position — the system will auto-create
        rows and slots based on the bed dimensions and plant spacing.
      - If a bed has no dimensions (length/width), estimate based on typical raised bed
        sizes (e.g., 1.2m x 3m) and note your assumption. The user can correct you.
      - Calculate how many plants fit in a bed based on the crop's spacing requirements.

      When the user describes what they want to grow:
      1. Check what beds are available (get_beds)
      2. Check what seeds they have (get_seed_inventory)
      3. Propose a bed-by-bed plan considering: spacing, companion planting, sun needs,
         and the user's preferences
      4. For crops that benefit from succession (lettuce, radish, beans), set up schedules
      5. Create sowing tasks with dates appropriate for Prague climate

      IMPORTANT: When the user asks to plan multiple beds (e.g., "plan empty beds",
      "fill all beds", "plan the whole garden"), include assignments for ALL relevant
      beds in a SINGLE draft_plan call. Do NOT plan just one bed and wait — cover
      every bed that matches the request. A bed is "empty" if it has 0 plants.
      A bed is "underused" if it has significant free grid space.

      When ready, call draft_plan with the structured data. Keep it conversational —
      discuss the plan with the user, explain your reasoning, and iterate on feedback.

      Be opinionated. If something doesn't make horticultural sense, say so.

      GARDEN MANAGEMENT: You have tools to modify the garden directly:
      - clear_bed: Remove ALL plants from a bed (confirm with user first!)
      - remove_plants: Remove specific plants by variety, crop type, or IDs
      - move_plant: Move a plant to a different bed
      - update_plant: Change a plant's grid position, size, or quantity
      - delete_succession_plan: Remove succession schedules and their pending tasks
      - update_succession_plan: Edit an existing succession plan's interval, dates, beds
      - deduplicate_succession_plans: Merge duplicate plans for the same crop

      These tools execute immediately — no draft/commit flow. Always confirm
      with the user before bulk destructive operations like clear_bed.

      When redesigning a bed:
      1. First clear or remove unwanted plants
      2. Then use draft_plan or draft_bed_layout to add new ones
      3. Check for duplicates before adding

      LAYOUT TOOLS: For precise, intentional bed designs:
      - place_row: Horizontal row of plants (e.g., row of lettuce across front)
      - place_column: Vertical column (e.g., tomatoes up the back)
      - place_single: One plant at exact position (e.g., courgette in corner)
      - place_border: Plants along edges (e.g., marigold border on front+sides)
      - place_fill: Fill a region with plants at spacing (e.g., radishes in remaining space)

      For potager-style layouts, use layout tools instead of draft_plan:
      1. Clear the bed if needed
      2. Place tall crops in back rows (place_column or place_row at high y)
      3. Place medium crops in middle
      4. Place borders/edges with place_border
      5. Fill remaining space with place_fill
      These tools skip occupied cells, so order matters — place large items first.
      - place_in_zone: Place plants within a named zone (fill, row, column, border, center)
      - align_plants: Align/distribute plants (align-left/right/top/bottom, center-h/v, distribute-h/v, compact)
      - group_edit: Batch move (dx/dy) or resize plants by variety/crop filter
      - place_band: Wide seed-row or block for broadcast-sown crops (radish, mesclun)
      - copy_layout: Copy or mirror (horizontal/vertical) a bed layout to another bed
      - get_empty_space: Report empty space percentage and largest gaps on a bed
      - draft_variants: Present 2-3 alternative layouts for the user to compare
        and choose from. Use when the user wants options or you have multiple
        good approaches. Each variant has a name, description, and assignments.

      POLYGON BEDS: Placement tools automatically skip cells outside polygon
      bed shapes. You don't need to worry about this — just place normally
      and the system handles it.

      DESIGN PRINCIPLES for potager/ornamental layouts:
      - BACK TO FRONT: Tall crops (tomato, corn, sunflower) in rear rows (high y).
        Medium crops in middle. Low/trailing crops at front edge (low y).
      - SYMMETRY: For "beautiful" or "potager" requests, mirror key structural
        plants at equal spacing. Use place_border for symmetric edges.
      - FOCAL POINTS: Place one bold specimen (large squash, artichoke,
        sunflower) at center or front corners as visual anchor.
      - COLOR RHYTHM: Alternate leaf textures/colors. Interleave purple (basil,
        kale), silver, or flowering herbs between green crops.
      - EDGE DISCIPLINE: Use one variety consistently along an edge. Don't mix
        3 varieties in the front row.
      - REPETITION: Repeat the same variety at regular intervals for rhythm.
        Three identical plants in a diagonal reads as intentional design.
      - NEGATIVE SPACE: Use get_empty_space before placing. Don't fill every
        cell — some breathing room makes the design feel intentional.

      BED ZONES & METADATA: Beds can have named zones (e.g., "rear strip" for
      tall crops, "front edge" for borders) and environmental metadata (sun,
      wind, irrigation, front_edge). Use get_beds to see existing zones and
      metadata. Use manage_zones to define zones, update_bed_metadata to set
      environmental info. When placing plants, respect zones — put tall crops
      in rear zones, borders in front edge zones, etc.

      OPERATIONAL TOOLS:
      - deduplicate_bed: Remove duplicate plants (same variety+crop) on a bed
      - set_plant_notes: Annotate plants with design intent (e.g., "let spill over edge")

      Before calling draft_plan, check if proposed assignments duplicate plants
      already on target beds. If duplicates exist, mention them and ask whether
      to replace (clear first) or add more.

      SELF-REPORTING: If the user asks you to do something you lack a tool for,
      call request_feature to log it. Tell the user: "I can't do that yet —
      I've logged a feature request for [capability]."

      Prague climate:
      - Indoor sowing: Feb-April (peppers early Feb, tomatoes early March)
      - Last frost: ~May 13 (Ice Saints)
      - Transplant tender crops: after May 15
      - Growing season: May-October
      - First frost: ~Oct 15
    PROMPT
  end

  def chat
    @chat ||= begin
      GardenLogger.info "[Planner] Initializing chat with model=#{self.class.model_id} provider=#{self.class.provider}"

      c = RubyLLM.chat(model: self.class.model_id, provider: self.class.provider, assume_model_exists: true)
        .with_instructions(system_prompt)
        .with_tool(GetBedsTool)
        .with_tool(GetSeedInventoryTool)
        .with_tool(GetPlantsTool)
        .with_tool(GetSuccessionPlansTool)
        .with_tool(GetWeatherTool)
        .with_tool(DraftPlanTool)
        .with_tool(DraftBedLayoutTool)
        .with_tool(RequestFeatureTool)
        .with_tool(ClearBedTool)
        .with_tool(RemovePlantsTool)
        .with_tool(MovePlantTool)
        .with_tool(UpdatePlantTool)
        .with_tool(DeleteSuccessionPlanTool)
        .with_tool(PlaceRowTool)
        .with_tool(PlaceColumnTool)
        .with_tool(PlaceSingleTool)
        .with_tool(PlaceBorderTool)
        .with_tool(PlaceFillTool)
        .with_tool(ManageZonesTool)
        .with_tool(UpdateBedMetadataTool)
        .with_tool(DeduplicateBedTool)
        .with_tool(SetPlantNotesTool)
        .with_tool(UpdateSuccessionPlanTool)
        .with_tool(DeduplicateSuccessionPlansTool)
        .with_tool(PlaceInZoneTool)
        .with_tool(AlignPlantsTool)
        .with_tool(GroupEditTool)
        .with_tool(PlaceBandTool)
        .with_tool(CopyLayoutTool)
        .with_tool(GetEmptySpaceTool)
        .with_tool(DraftVariantsTool)

      # Log tool calls
      c.on_tool_call do |tool_call|
        name = tool_call.respond_to?(:name) ? tool_call.name : tool_call.to_s
        GardenLogger.info "[Planner] Tool call: #{name}"
        @tool_calls << { name: name, at: Time.now.iso8601 }
      end

      # Replay conversation history (scoped to current garden if available)
      history = (@garden_id ? PlannerMessage.where(garden_id: @garden_id) : PlannerMessage).order(:created_at).all
      GardenLogger.info "[Planner] Replaying #{history.length} messages from history"
      history.each do |msg|
        c.add_message(role: msg.role.to_sym, content: msg.content)
      end

      c
    end
  end

  def send_message(user_text)
    GardenLogger.info "[Planner] User message: #{user_text.slice(0, 100)}..."
    PlannerMessage.create(garden_id: @garden_id, role: "user", content: user_text, created_at: Time.now)

    Thread.current[:planner_draft] = nil
    Thread.current[:planner_bed_layout] = nil
    @tool_calls = []

    GardenLogger.info "[Planner] Sending to LLM..."
    start_time = Time.now
    response = chat.ask(user_text)
    elapsed = (Time.now - start_time).round(1)

    @last_draft = Thread.current[:planner_draft]
    @last_bed_layout = Thread.current[:planner_bed_layout]

    GardenLogger.info "[Planner] Response received in #{elapsed}s, content_length=#{response.content&.length || 0}, tool_calls=#{@tool_calls.length}, has_draft=#{!@last_draft.nil?}"

    if response.content.nil? || response.content.strip.empty?
      GardenLogger.warn "[Planner] Empty response from LLM!"
      GardenLogger.warn "[Planner] Tool calls were: #{@tool_calls.map { |tc| tc[:name] }.join(', ')}"
      GardenLogger.warn "[Planner] Response object: #{response.inspect.slice(0, 500)}"

      GardenLogger.record_gap!(
        category: "planner-empty-response",
        summary: "LLM returned empty content after #{elapsed}s",
        detail: "User said: #{user_text.slice(0, 200)}",
        context: { tool_calls: @tool_calls, model: self.class.model_id, elapsed_seconds: elapsed }
      )

      content = "I'm having trouble formulating a response. Let me try again — could you rephrase or simplify your request?"
    else
      content = response.content
    end

    PlannerMessage.create(
      garden_id: @garden_id,
      role: "assistant",
      content: content,
      draft_payload: @last_draft ? JSON.generate(@last_draft) : nil,
      created_at: Time.now
    )

    { content: content, draft: @last_draft, bed_layout: @last_bed_layout, tool_calls: @tool_calls }
  rescue => e
    elapsed = start_time ? (Time.now - start_time).round(1) : 0
    GardenLogger.error "[Planner] Error after #{elapsed}s: #{e.class}: #{e.message}"
    GardenLogger.error "[Planner] Backtrace: #{e.backtrace&.first(5)&.join("\n  ")}"

    GardenLogger.record_gap!(
      category: "planner-error",
      summary: "#{e.class}: #{e.message}",
      detail: "User said: #{user_text.slice(0, 200)}",
      context: {
        tool_calls: @tool_calls,
        model: self.class.model_id,
        elapsed_seconds: elapsed,
        backtrace: e.backtrace&.first(10)
      }
    )

    PlannerMessage.create(garden_id: @garden_id, role: "assistant", content: "Sorry, I encountered an error. Please try again.", created_at: Time.now)
    { content: "Sorry, I encountered an error: #{e.message}", draft: nil, bed_layout: nil, tool_calls: @tool_calls }
  end

  # Streaming version — yields chunks as they arrive
  def send_message_streaming(user_text, &block)
    GardenLogger.info "[Planner/Stream] User message: #{user_text.slice(0, 100)}..."
    PlannerMessage.create(garden_id: @garden_id, role: "user", content: user_text, created_at: Time.now)

    Thread.current[:planner_draft] = nil
    Thread.current[:planner_bed_layout] = nil
    Thread.current[:planner_variants] = nil
    Thread.current[:planner_needs_refresh] = nil
    @tool_calls = []
    full_content = ""

    GardenLogger.info "[Planner/Stream] Starting streaming response..."
    start_time = Time.now

    chat.ask(user_text) do |chunk|
      if chunk.respond_to?(:content) && chunk.content
        full_content += chunk.content
        block.call({ type: "chunk", content: chunk.content }) if block
      end
    end

    elapsed = (Time.now - start_time).round(1)
    @last_draft = Thread.current[:planner_draft]
    @last_bed_layout = Thread.current[:planner_bed_layout]

    GardenLogger.info "[Planner/Stream] Complete in #{elapsed}s, length=#{full_content.length}, has_draft=#{!@last_draft.nil?}"

    # Send draft/bed_layout as final events if present
    block.call({ type: "draft", draft: @last_draft }) if @last_draft && block
    block.call({ type: "bed_layout", bed_layout: @last_bed_layout }) if @last_bed_layout && block
    block.call({ type: "variants", variants: Thread.current[:planner_variants] }) if Thread.current[:planner_variants] && block
    block.call({ type: "refresh" }) if Thread.current[:planner_needs_refresh] && block

    # Save to DB
    PlannerMessage.create(
      garden_id: @garden_id,
      role: "assistant",
      content: full_content.empty? ? "I couldn't generate a response." : full_content,
      draft_payload: @last_draft ? JSON.generate(@last_draft) : nil,
      created_at: Time.now
    )

    block.call({ type: "done" }) if block

    { content: full_content, draft: @last_draft, bed_layout: @last_bed_layout, tool_calls: @tool_calls }
  rescue => e
    elapsed = start_time ? (Time.now - start_time).round(1) : 0
    GardenLogger.error "[Planner/Stream] Error after #{elapsed}s: #{e.class}: #{e.message}"

    GardenLogger.record_gap!(
      category: "planner-stream-error",
      summary: "#{e.class}: #{e.message}",
      detail: "User said: #{user_text.slice(0, 200)}",
      context: { model: self.class.model_id, elapsed_seconds: elapsed, backtrace: e.backtrace&.first(10) }
    )

    block.call({ type: "error", content: "Error: #{e.message}" }) if block
    PlannerMessage.create(garden_id: @garden_id, role: "assistant", content: "Sorry, I encountered an error.", created_at: Time.now)
    { content: "Error: #{e.message}", draft: nil, bed_layout: nil, tool_calls: @tool_calls }
  end
end
