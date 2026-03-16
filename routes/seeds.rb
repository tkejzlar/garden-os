require_relative "../models/seed_packet"

class GardenApp
  get "/seeds" do
    @packets = SeedPacket.order(:crop_type, :variety_name).all
    erb :"seeds/index"
  end

  # AI variety lookup
  get "/api/seeds/lookup" do
    variety = params[:q].to_s.strip
    halt 400, json(error: "q parameter required") if variety.empty?

    require_relative "../services/variety_lookup_service"
    source = params[:source].to_s.strip
    result = VarietyLookupService.lookup(variety, source: source.empty? ? nil : source)

    if result
      json result
    else
      halt 503, json(error: "Lookup failed — check AI provider config")
    end
  end

  get "/seeds/new" do
    @packet = SeedPacket.new
    erb :"seeds/show"
  end

  get "/seeds/:id" do
    @packet = SeedPacket[params[:id].to_i]
    halt 404, "Seed packet not found" unless @packet
    erb :"seeds/show"
  end

  post "/seeds" do
    SeedPacket.create(
      variety_name: params[:variety_name].to_s.strip,
      crop_type:    params[:crop_type].to_s.strip,
      source:       params[:source].to_s.strip.then { |v| v.empty? ? nil : v },
      notes:        params[:notes].to_s.strip.then { |v| v.empty? ? nil : v },
      created_at:   Time.now,
      updated_at:   Time.now
    )
    redirect "/seeds"
  end

  patch "/seeds/:id" do
    packet = SeedPacket[params[:id].to_i]
    halt 404 unless packet
    packet.update(
      variety_name: params[:variety_name].to_s.strip,
      crop_type:    params[:crop_type].to_s.strip,
      source:       params[:source].to_s.strip.then { |v| v.empty? ? nil : v },
      notes:        params[:notes].to_s.strip.then { |v| v.empty? ? nil : v },
      updated_at:   Time.now
    )
    redirect "/seeds/#{packet.id}"
  end

  delete "/seeds/:id" do
    packet = SeedPacket[params[:id].to_i]
    halt 404 unless packet
    packet.destroy
    redirect "/seeds"
  end

  get "/api/seeds" do
    json SeedPacket.order(:crop_type, :variety_name).all.map(&:values)
  end
end
