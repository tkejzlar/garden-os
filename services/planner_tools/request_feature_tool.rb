require "ruby_llm"
require_relative "../garden_logger"

class RequestFeatureTool < RubyLLM::Tool
  description "Log a feature request when you identify something useful you COULD do for the user but lack the tools to accomplish. Examples: editing bed dimensions, moving plants between beds, deleting plants, updating seed inventory. Call this proactively when you notice a gap — don't just say you can't do it."

  param :action, type: :string, desc: "What the user wanted to do (e.g., 'move tomato from BB1 to SB2')"
  param :capability, type: :string, desc: "What tool/capability is missing (e.g., 'move_plant_between_beds')"
  param :context, type: :string, desc: "Brief context on why this would be valuable"

  def execute(action:, capability:, context:)
    GardenLogger.record_gap!(
      category: "feature-request",
      summary: capability,
      detail: action,
      context: { reason: context, source: "ai-planner", requested_at: Time.now.iso8601 }
    )

    "Feature request logged: '#{capability}'. Let the user know you've noted this and it may be available in the future."
  end
end
