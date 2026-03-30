require "ruby_llm"
require "yaml"

class CheckFeatureRequestsTool < RubyLLM::Tool
  description "Check what feature requests have already been logged. Use BEFORE logging a new request to avoid duplicates. Returns open requests with their summaries."

  param :query, type: :string, desc: "Optional keyword to filter by (searches summary and detail)"

  def execute(query: nil)
    gaps_dir = File.join(File.dirname(__FILE__), "..", "..", "docs", "gaps")
    return "No feature requests logged yet." unless File.directory?(gaps_dir)

    files = Dir.glob(File.join(gaps_dir, "*-feature-request.yml"))
    requests = files.map do |f|
      data = YAML.safe_load(File.read(f))
      data["file"] = File.basename(f)
      data
    rescue
      nil
    end.compact

    if query
      q = query.downcase
      requests = requests.select { |r|
        (r["summary"].to_s.downcase.include?(q) || r["detail"].to_s.downcase.include?(q))
      }
    end

    return "No matching feature requests found." if requests.empty?

    requests.sort_by { |r| r["timestamp"] || "" }.reverse.first(10).map { |r|
      status = r["status"] || "open"
      "- [#{status}] #{r['summary']}: #{r['detail']}"
    }.join("\n")
  end
end
