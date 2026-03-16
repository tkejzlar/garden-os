require "json"
require_relative "../config/ruby_llm"
require_relative "../models/planner_message"
require_relative "planner_tools/get_beds_tool"
require_relative "planner_tools/get_seed_inventory_tool"
require_relative "planner_tools/get_plants_tool"
require_relative "planner_tools/get_succession_plans_tool"
require_relative "planner_tools/get_weather_tool"
require_relative "planner_tools/draft_plan_tool"

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
  end

  def system_prompt
    <<~PROMPT
      You are a garden planning consultant for a productive vegetable garden in Prague,
      Czech Republic (zone 6b/7a, last frost ~May 13, first frost ~Oct 15, continental climate).

      ALWAYS use the available tools to look up the garden's actual data before making
      recommendations. Don't assume — check the beds, seeds, and existing plants.

      CRITICAL: When referencing beds, rows, or slots in your draft_plan, use ONLY the
      exact names and positions returned by get_beds. Never invent bed or row names.

      When the user describes what they want to grow, help them create a complete plan:
      1. First, check what beds are available and their dimensions
      2. Check what seeds they already have
      3. Propose bed assignments considering: sun exposure, spacing, companion planting,
         crop rotation, and the user's preferences
      4. Set up succession schedules for crops that benefit from them
      5. Create a task timeline with sowing dates (indoor + outdoor), transplant dates,
         and other key milestones

      When you have a complete plan, call the draft_plan tool with ALL the structured data.
      The user will see a visual preview and can request changes before committing.

      Be conversational, practical, and opinionated. If the user asks for something that
      doesn't make horticultural sense, say so and suggest alternatives.

      Prague climate notes:
      - Indoor sowing: Feb-April (peppers early Feb, tomatoes early March)
      - Last frost: ~May 13 (Ice Saints)
      - Transplant tender crops: after May 15
      - Growing season: May-October
      - First frost: ~Oct 15
    PROMPT
  end

  def chat
    @chat ||= begin
      c = RubyLLM.chat(model: self.class.model_id, provider: self.class.provider, assume_model_exists: true)
        .with_instructions(system_prompt)
        .with_tool(GetBedsTool)
        .with_tool(GetSeedInventoryTool)
        .with_tool(GetPlantsTool)
        .with_tool(GetSuccessionPlansTool)
        .with_tool(GetWeatherTool)
        .with_tool(DraftPlanTool)

      # Replay conversation history so the AI has context
      PlannerMessage.order(:created_at).all.each do |msg|
        c.add_message(role: msg.role.to_sym, content: msg.content)
      end

      c
    end
  end

  def send_message(user_text)
    PlannerMessage.create(role: "user", content: user_text, created_at: Time.now)

    Thread.current[:planner_draft] = nil

    response = chat.ask(user_text)

    @last_draft = Thread.current[:planner_draft]

    PlannerMessage.create(
      role: "assistant",
      content: response.content,
      draft_payload: @last_draft ? JSON.generate(@last_draft) : nil,
      created_at: Time.now
    )

    { content: response.content, draft: @last_draft }
  rescue => e
    warn "PlannerService error: #{e.message}"
    PlannerMessage.create(role: "assistant", content: "Sorry, I encountered an error. Please try again.", created_at: Time.now)
    { content: "Sorry, I encountered an error: #{e.message}", draft: nil }
  end
end
