require "ruby_llm"
require_relative "../../models/plant"

class GetPlantsTool < RubyLLM::Tool
  description "Get all active plants currently being grown — variety, stage, location, days in stage"

  def execute
    garden_id = Thread.current[:current_garden_id]
    base = garden_id ? Plant.where(garden_id: garden_id) : Plant
    plants = base.exclude(lifecycle_stage: "done").all.map do |p|
      bed = p.bed
      {
        variety_name: p.variety_name,
        crop_type: p.crop_type,
        stage: p.lifecycle_stage,
        days_in_stage: p.days_in_stage,
        bed: bed&.name,
        sow_date: p.sow_date&.to_s,
        grid_x: p.grid_x,
        grid_y: p.grid_y,
        grid_w: p.grid_w,
        grid_h: p.grid_h
      }
    end
    JSON.generate({ plants: plants, total: plants.length })
  end
end
