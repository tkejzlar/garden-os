require "json"
require_relative "../config/ruby_llm"

class VarietyLookupService
  def self.model_id
    ENV.fetch("GARDEN_AI_MODEL", "gpt-4o")
  end

  def self.system_prompt
    <<~PROMPT
      You are a garden variety identification expert. Given a plant variety name,
      identify what it is and provide growing information.

      Respond with JSON only — no markdown, no explanation:
      {
        "crop_type": "tomato|pepper|cucumber|lettuce|radish|herb|flower|pea|bean|other",
        "variety_notes": "Brief description: origin, fruit type, flavor, disease resistance, etc.",
        "days_to_maturity": "65-75",
        "frost_tender": true,
        "sow_indoor_weeks_before_last_frost": 8,
        "direct_sow": false,
        "germination_days": "5-14",
        "germination_temp_ideal": 25,
        "spacing_cm": 45,
        "height_cm": "150-180",
        "sun": "full",
        "notes": "Any special growing tips for Prague climate (zone 6b/7a, last frost ~May 13)"
      }

      If you don't recognize the variety name, make your best guess based on the name
      and note your uncertainty in variety_notes. Set crop_type to your best guess.
    PROMPT
  end

  def self.lookup(variety_name)
    return nil if variety_name.nil? || variety_name.strip.empty?

    chat = RubyLLM.chat(model: model_id, assume_model_exists: true)
      .with_instructions(system_prompt)
      .with_temperature(0.2)

    response = chat.ask("Variety: #{variety_name.strip}")
    parsed = JSON.parse(response.content)
    parse_response(parsed)
  rescue => e
    warn "VarietyLookup error: #{e.message}"
    nil
  end

  def self.parse_response(data)
    return { crop_type: nil, notes: nil } if data.nil? || data.empty?

    notes_parts = [
      data["variety_notes"],
      data["days_to_maturity"] ? "#{data["days_to_maturity"]} days to maturity" : nil,
      data["height_cm"] ? "Height: #{data["height_cm"]}cm" : nil,
      data["spacing_cm"] ? "Spacing: #{data["spacing_cm"]}cm" : nil,
      data["germination_days"] ? "Germination: #{data["germination_days"]} days at #{data["germination_temp_ideal"]}°C" : nil,
      data["direct_sow"] ? "Can direct sow" : nil,
      data["frost_tender"] ? "Frost tender" : "Frost hardy",
      data["sow_indoor_weeks_before_last_frost"] ? "Start indoors #{data["sow_indoor_weeks_before_last_frost"]} weeks before last frost" : nil,
      data["notes"]
    ].compact

    {
      crop_type: data["crop_type"],
      notes: notes_parts.join(". "),
      frost_tender: data["frost_tender"],
      direct_sow: data["direct_sow"],
      days_to_maturity: data["days_to_maturity"],
      sow_indoor_weeks: data["sow_indoor_weeks_before_last_frost"],
      raw: data
    }
  end
end
