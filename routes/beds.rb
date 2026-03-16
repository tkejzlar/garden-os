require_relative "../models/bed"
require_relative "../models/plant"

class GardenApp
  get "/beds" do
    @beds = Bed.all
    @arches = Arch.all
    @indoor_stations = IndoorStation.all
    @bed_data = @beds.map do |bed|
      rows = Row.where(bed_id: bed.id).order(:position).all
      row_data = rows.map do |row|
        slots = Slot.where(row_id: row.id).order(:position).all
        slot_ids = slots.map(&:id)
        plants_by_slot = Plant.where(slot_id: slot_ids)
                              .exclude(lifecycle_stage: "done")
                              .all.group_by(&:slot_id)
        { row: row, slots: slots.map { |s| { slot: s, plant: plants_by_slot[s.id]&.first } } }
      end
      { bed: bed, rows: row_data }
    end
    erb :"beds/index"
  end

  get "/beds/:id" do
    @bed = Bed[params[:id].to_i]
    halt 404 unless @bed
    @rows = Row.where(bed_id: @bed.id).order(:position).all
    row_ids = @rows.map(&:id)
    all_slots = Slot.where(row_id: row_ids).order(:position).all
    slot_ids = all_slots.map(&:id)
    @plants_by_slot = Plant.where(slot_id: slot_ids)
                           .exclude(lifecycle_stage: "done")
                           .all.group_by(&:slot_id)
    @slots_by_row = all_slots.group_by(&:row_id)
    erb :"beds/show"
  end

  get "/api/beds" do
    beds = Bed.all.map do |bed|
      rows = Row.where(bed_id: bed.id).order(:position).all.map do |row|
        slots = Slot.where(row_id: row.id).order(:position).all.map do |slot|
          plant = Plant.where(slot_id: slot.id).exclude(lifecycle_stage: "done").first
          slot.values.merge(plant: plant&.values)
        end
        row.values.merge(slots: slots)
      end
      bed.values.merge(rows: rows)
    end
    json beds
  end
end
