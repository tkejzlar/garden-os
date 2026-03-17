require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class GetBedsTool < RubyLLM::Tool
  description "Get all garden beds with dimensions, grid layout, and which plants are currently assigned"

  def execute
    garden_id = Thread.current[:current_garden_id]
    beds = (garden_id ? Bed.where(garden_id: garden_id) : Bed).all.map do |bed|
      plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all.map { |p|
        { id: p.id, variety_name: p.variety_name, crop_type: p.crop_type,
          lifecycle_stage: p.lifecycle_stage,
          grid_x: p.grid_x, grid_y: p.grid_y, grid_w: p.grid_w, grid_h: p.grid_h,
          quantity: p.quantity }
      }

      # Use real dimensions if set, otherwise derive from canvas (1 canvas unit = 1 cm)
      points = bed.canvas_points_array
      is_polygon = points && points.length >= 3

      if is_polygon
        # Shoelace formula for polygon area
        area_cm2 = 0.0
        points.each_with_index do |pt, i|
          j = (i + 1) % points.length
          area_cm2 += pt[0] * points[j][1]
          area_cm2 -= points[j][0] * pt[1]
        end
        area_sqm = (area_cm2.abs / 2.0 / 10000.0).round(1)
        length_cm = nil
        width_cm = nil
      else
        length_cm = bed.length || bed.canvas_height&.round
        width_cm  = bed.width  || bed.canvas_width&.round
        area_sqm  = (length_cm && width_cm) ? (length_cm * width_cm / 10000.0).round(1) : nil
      end

      {
        name: bed.name,
        bed_type: bed.bed_type,
        shape: is_polygon ? "polygon" : "rectangle",
        length_cm: length_cm,
        width_cm: width_cm,
        area_sqm: area_sqm,
        orientation: bed.orientation,
        grid_cols: bed.grid_cols,
        grid_rows: bed.grid_rows,
        plants: plants,
        total_plants: plants.length
      }
    end

    # Also include arches and indoor stations
    arches = (garden_id ? Arch.where(garden_id: garden_id) : Arch).all.map { |a| { name: a.name, between_beds: a.between_beds, spring_crop: a.spring_crop, summer_crop: a.summer_crop } }
    indoor = (garden_id ? IndoorStation.where(garden_id: garden_id) : IndoorStation).all.map { |s| { name: s.name, type: s.station_type, target_temp: s.target_temp } }

    JSON.generate({ beds: beds, arches: arches, indoor_stations: indoor })
  end
end
