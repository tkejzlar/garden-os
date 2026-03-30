require "ruby_llm"
require "yaml"

class ResolveFeatureRequestTool < RubyLLM::Tool
  description "Mark a feature request as resolved. Use when a capability has been implemented. Searches by keyword in summary."

  param :keyword, type: :string, desc: "Keyword to find the request (searches summary)"

  def execute(keyword:)
    gaps_dir = File.join(File.dirname(__FILE__), "..", "..", "docs", "gaps")
    return "No feature requests directory." unless File.directory?(gaps_dir)

    files = Dir.glob(File.join(gaps_dir, "*-feature-request.yml"))
    resolved = 0

    files.each do |f|
      data = YAML.safe_load(File.read(f))
      next unless data["summary"].to_s.downcase.include?(keyword.downcase)
      next if data["status"] == "resolved"

      data["status"] = "resolved"
      data["resolved_at"] = Time.now.iso8601
      File.write(f, YAML.dump(data))
      resolved += 1
    end

    resolved > 0 ? "Resolved #{resolved} request(s) matching '#{keyword}'." : "No open requests matching '#{keyword}'."
  end
end
