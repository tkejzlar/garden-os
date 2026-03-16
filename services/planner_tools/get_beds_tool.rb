require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class GetBedsTool < RubyLLM::Tool
  description "Get all garden beds with dimensions, rows, slots, and which plants are currently assigned to each slot"

  def execute
    beds = Bed.all.map do |bed|
      rows = Row.where(bed_id: bed.id).order(:position).all.map do |row|
        slots = Slot.where(row_id: row.id).order(:position).all.map do |slot|
          plant = Plant.where(slot_id: slot.id).exclude(lifecycle_stage: "done").first
          {
            position: slot.position,
            name: slot.name,
            plant: plant ? { variety_name: plant.variety_name, crop_type: plant.crop_type, stage: plant.lifecycle_stage } : nil
          }
        end
        { name: row.name, slots: slots }
      end

      {
        name: bed.name,
        bed_type: bed.bed_type,
        length: bed.length,
        width: bed.width,
        orientation: bed.orientation,
        rows: rows,
        total_slots: rows.sum { |r| r[:slots].length },
        occupied_slots: rows.sum { |r| r[:slots].count { |s| s[:plant] } }
      }
    end

    # Also include arches and indoor stations
    arches = Arch.all.map { |a| { name: a.name, between_beds: a.between_beds, spring_crop: a.spring_crop, summer_crop: a.summer_crop } }
    indoor = IndoorStation.all.map { |s| { name: s.name, type: s.station_type, target_temp: s.target_temp } }

    JSON.generate({ beds: beds, arches: arches, indoor_stations: indoor })
  end
end
