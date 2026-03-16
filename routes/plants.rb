require_relative "../models/plant"
require_relative "../models/bed"
require_relative "../models/stage_history"

class GardenApp
  get "/plants" do
    @plants = Plant.exclude(lifecycle_stage: "done").order(:crop_type, :variety_name).all
    @done_plants = Plant.where(lifecycle_stage: "done").all
    erb :"plants/index"
  end

  get "/plants/:id" do
    @plant = Plant[params[:id].to_i]
    halt 404, "Plant not found" unless @plant
    @history = StageHistory.where(plant_id: @plant.id).order(:changed_at).all
    erb :"plants/show"
  end

  post "/plants/:id/advance" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant
    plant.advance_stage!(params[:stage], note: params[:note])
    redirect back
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
