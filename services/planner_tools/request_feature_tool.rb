require "ruby_llm"
require "yaml"
require_relative "../garden_logger"

class RequestFeatureTool < RubyLLM::Tool
  description "Log a feature request when you identify something useful you COULD do for the user but lack the tools to accomplish. Examples: editing bed dimensions, moving plants between beds, deleting plants, updating seed inventory. Call this proactively when you notice a gap — don't just say you can't do it."

  param :action, type: :string, desc: "What the user wanted to do (e.g., 'move tomato from BB1 to SB2')"
  param :capability, type: :string, desc: "What tool/capability is missing (e.g., 'move_plant_between_beds')"
  param :context, type: :string, desc: "Brief context on why this would be valuable"
  param :batch, type: :string, desc: "Optional JSON array of {action, capability, context} objects to log multiple requests at once"

  def execute(action: nil, capability: nil, context: nil, batch: nil)
    if batch
      items = JSON.parse(batch) rescue []
      items.each do |item|
        GardenLogger.record_gap!(
          category: "feature-request",
          summary: item["capability"] || item["summary"],
          detail: item["action"] || item["detail"],
          context: { reason: item["context"] || item["reason"], source: "ai-planner", requested_at: Time.now.iso8601 }
        )
      end
      return "Logged #{items.length} feature requests."
    end

    # Check for existing request with same summary
    gaps_dir = File.join(File.dirname(__FILE__), "..", "..", "docs", "gaps")
    if File.directory?(gaps_dir)
      existing = Dir.glob(File.join(gaps_dir, "*-feature-request.yml")).any? do |f|
        data = YAML.safe_load(File.read(f)) rescue {}
        data["summary"].to_s.downcase.strip == capability.to_s.downcase.strip && data["status"] != "resolved"
      end
      return "Feature request '#{capability}' already logged — skipping duplicate." if existing
    end

    GardenLogger.record_gap!(
      category: "feature-request",
      summary: capability,
      detail: action,
      context: { reason: context, source: "ai-planner", requested_at: Time.now.iso8601 }
    )

    "Feature request logged: '#{capability}'. Let the user know you've noted this and it may be available in the future."
  end
end
