require "json"
require_relative "../config/ruby_llm"

class VarietyLookupService
  def self.model_id
    ENV.fetch("GARDEN_AI_MODEL", "gpt-4o")
  end

  def self.provider
    m = model_id
    if m.start_with?("claude") then :anthropic
    elsif m.start_with?("gemini") then :gemini
    else :openai
    end
  end

  def self.system_prompt
    <<~PROMPT
      You are a seed catalog expert specializing in European vegetable and herb varieties.
      Your knowledge covers major seed suppliers including:
      - Loukykvět, Semo, Moravoseed (Czech)
      - Magic Garden Seeds, Dreschflegel, Bingenheimer (German)
      - Kokopelli, Ferme de Sainte Marthe (French)
      - Real Seeds, Chiltern Seeds (UK)
      - Baker Creek, Johnny's Selected Seeds (US)

      When given a variety name (and optionally a supplier), identify exactly what plant
      it is and provide detailed growing information. Search your knowledge thoroughly —
      many varieties have regional names, translations, or catalog-specific naming.

      IMPORTANT: If the name could be a pepper, tomato, or any nightshade variety,
      check those first — they are the most commonly looked up.

      Respond with JSON only — no markdown, no explanation, no code fences:
      {
        "crop_type": "tomato|pepper|cucumber|lettuce|radish|herb|flower|pea|bean|squash|brassica|onion|root|other",
        "variety_notes": "Brief but specific description: species, fruit type/shape/color, flavor, origin, disease resistance",
        "days_to_maturity": "65-75",
        "frost_tender": true,
        "sow_indoor_weeks_before_last_frost": 8,
        "direct_sow": false,
        "germination_days": "5-14",
        "germination_temp_ideal": 25,
        "spacing_cm": 45,
        "height_cm": "150-180",
        "sun": "full",
        "notes": "Growing tips for Prague climate (zone 6b/7a, last frost ~May 13, continental)"
      }
    PROMPT
  end

  def self.lookup(variety_name, source: nil)
    return nil if variety_name.nil? || variety_name.strip.empty?

    chat = RubyLLM.chat(model: model_id, provider: provider, assume_model_exists: true)
      .with_instructions(system_prompt)
      .with_temperature(0.1)

    query = "Identify this seed variety: \"#{variety_name.strip}\""
    query += " (from #{source.strip})" if source && !source.strip.empty?

    response = chat.ask(query)

    # Strip markdown code fences if the model wraps its response
    text = response.content.strip
    text = text.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")

    parsed = JSON.parse(text)
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
