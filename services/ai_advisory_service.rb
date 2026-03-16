# services/ai_advisory_service.rb
require "json"
require_relative "../config/ruby_llm"
require_relative "../models/plant"
require_relative "../models/harvest"
require_relative "../models/task"
require_relative "../models/advisory"
require_relative "../db/seeds/seed_varieties"

class AIAdvisoryService
  DEFAULT_MODEL = "claude-sonnet-4-6"

  def self.model_id
    ENV.fetch("GARDEN_AI_MODEL", DEFAULT_MODEL)
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
      You are a garden advisor for a productive vegetable garden in Prague, Czech Republic (zone 6b/7a).
      Climate: last frost ~May 13, first frost ~Oct 15. Continental climate with hot summers.

      You receive the current state of all plants, upcoming tasks, and weather forecast.
      Provide actionable, specific advisories. Focus on:
      - Germination progress (is it on track for the crop type?)
      - Weather-based timing recommendations
      - Succession sowing reminders
      - Potential issues (overdue germination, frost risk for tender plants)

      Respond with JSON only:
      {
        "advisories": [
          {"type": "general|plant_specific|weather", "plant": "name or null", "summary": "one sentence", "detail": "explanation"}
        ]
      }
    PROMPT
  end

  def self.build_context
    plants = Plant.exclude(lifecycle_stage: "done").all.map do |p|
      harvest_rows = Harvest.where(plant_id: p.id).all
      harvest_counts = harvest_rows.group_by(&:quantity).transform_values(&:count)
      total_harvests = harvest_rows.count

      {
        variety_name:   p.variety_name,
        crop_type:      p.crop_type,
        stage:          p.lifecycle_stage,
        days_in_stage:  p.days_in_stage,
        sow_date:       p.sow_date&.to_s,
        total_harvests: total_harvests,
        harvest_counts: harvest_counts   # e.g. {"small"=>2, "large"=>1}
      }
    end

    tasks = Task.where(due_date: Date.today..(Date.today + 7))
                .exclude(status: "done").all.map do |t|
      { title: t.title, type: t.task_type, due: t.due_date.to_s }
    end

    weather = WeatherService.fetch_current rescue nil

    {
      date:           Date.today.to_s,
      plants:         plants,
      upcoming_tasks: tasks,
      weather:        weather,
      variety_data:   Varieties.all
    }
  end

  def self.parse_response(data)
    (data["advisories"] || []).map do |adv|
      {
        type: adv["type"],
        plant: adv["plant"],
        summary: adv["summary"],
        detail: adv["detail"]
      }
    end
  end

  def self.run_daily!
    context = build_context

    chat = RubyLLM.chat(model: model_id, provider: provider, assume_model_exists: true)
      .with_instructions(system_prompt)
      .with_temperature(0.3)

    response = chat.ask(JSON.pretty_generate(context))
    text = response.content

    parsed = JSON.parse(text)
    advisories = parse_response(parsed)

    advisories.each do |adv|
      plant_id = nil
      if adv[:plant]
        plant = Plant.where(variety_name: adv[:plant]).first
        plant_id = plant&.id
      end

      Advisory.create(
        date: Date.today,
        advisory_type: adv[:type],
        content: JSON.generate(adv),
        plant_id: plant_id
      )
    end

    advisories
  rescue => e
    warn "AI Advisory error: #{e.message}"
    []
  end
end
