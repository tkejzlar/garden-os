require_relative "../models/plant"
require_relative "../models/bed"
require_relative "../models/stage_history"
require_relative "../models/harvest"
require_relative "../models/photo"

class GardenApp
  get "/plants" do
    @plants = Plant.exclude(lifecycle_stage: "done").order(:crop_type, :variety_name).all
    @done_plants = Plant.where(lifecycle_stage: "done").all
    erb :"plants/index"
  end

  get "/plants/:id" do
    @plant    = Plant[params[:id].to_i]
    halt 404, "Plant not found" unless @plant
    @history  = StageHistory.where(plant_id: @plant.id).order(:changed_at).all
    @harvests = Harvest.where(plant_id: @plant.id).order(Sequel.desc(:date)).all
    @photos   = Photo.where(plant_id: @plant.id).order(Sequel.desc(:taken_at)).all
    erb :"plants/show"
  end

  post "/plants/:id/advance" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant
    plant.advance_stage!(params[:stage], note: params[:note])
    redirect back
  end

  post "/plants/:id/harvests" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant

    harvest = Harvest.new(
      plant_id: plant.id,
      date:     params[:date].to_s.empty? ? Date.today : Date.parse(params[:date]),
      quantity: params[:quantity],
      notes:    params[:notes].to_s.strip.then { |n| n.empty? ? nil : n }
    )

    if harvest.valid?
      harvest.save
    else
      # Re-render show with error — simple approach consistent with existing redirect pattern
      @plant   = plant
      @history = StageHistory.where(plant_id: plant.id).order(:changed_at).all
      @harvests = Harvest.where(plant_id: plant.id).order(Sequel.desc(:date)).all
      @photos   = Photo.where(plant_id: plant.id).order(Sequel.desc(:taken_at)).all
      @harvest_error = harvest.errors.full_messages.join(", ")
      return erb :"plants/show"
    end

    redirect "/plants/#{plant.id}"
  end

  get "/api/plants/:id/harvests" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant

    harvests = Harvest.where(plant_id: plant.id).order(Sequel.desc(:date)).all.map do |h|
      {
        id:         h.id,
        date:       h.date.to_s,
        quantity:   h.quantity,
        notes:      h.notes,
        created_at: h.created_at.to_s
      }
    end

    json harvests
  end

  post "/plants/batch_advance" do
    ids = params[:plant_ids].split(",").map(&:to_i)
    Plant.where(id: ids).all.each do |plant|
      plant.advance_stage!(params[:stage], note: params[:note])
    end
    redirect back
  end

  post "/api/plants" do
    data = JSON.parse(request.body.read)
    plant = Plant.create(
      garden_id: @current_garden.id,
      variety_name: data["variety_name"],
      crop_type: data["crop_type"],
      source: data["source"],
      lifecycle_stage: data.fetch("lifecycle_stage", "seed_packet")
    )
    status 201
    json plant.values
  end

  get "/api/plants" do
    json Plant.exclude(lifecycle_stage: "done").all.map(&:values)
  end

  get "/api/plants/:id" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant
    json plant.values.merge(
      days_in_stage: plant.days_in_stage,
      history: plant.stage_histories.map(&:values)
    )
  end
end
