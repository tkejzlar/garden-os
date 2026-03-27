require_relative "../models/seed_packet"

class GardenApp
  # Page route removed — React SPA serves /seeds

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

  # EAN barcode lookup — queries free product databases
  get "/api/seeds/ean/:code" do
    code = params[:code].to_s.strip
    halt 400, json(error: "EAN code required") if code.empty?

    require "net/http"
    require "json"

    result = nil

    # 1. Try Open Food Facts (large database, free, no key)
    begin
      uri = URI("https://world.openfoodfacts.org/api/v2/product/#{code}.json")
      res = Net::HTTP.get_response(uri)
      if res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body)
        if data["status"] == 1 && data["product"]
          p = data["product"]
          result = {
            source: "openfoodfacts",
            name: p["product_name"] || p["generic_name"],
            brand: p["brands"],
            categories: p["categories"],
            image_url: p["image_url"],
          }
        end
      end
    rescue => e
      GardenLogger.info "[EAN] Open Food Facts error: #{e.message}" rescue nil
    end

    # 2. Try UPC Item DB (free trial, broad coverage)
    unless result
      begin
        uri = URI("https://api.upcitemdb.com/prod/trial/lookup?upc=#{code}")
        req = Net::HTTP::Get.new(uri)
        req["Accept"] = "application/json"
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        res = http.request(req)
        if res.is_a?(Net::HTTPSuccess)
          data = JSON.parse(res.body)
          if data["items"] && data["items"].any?
            item = data["items"].first
            result = {
              source: "upcitemdb",
              name: item["title"],
              brand: item["brand"],
              categories: item["category"],
              image_url: item["images"]&.first,
            }
          end
        end
      rescue => e
        GardenLogger.info "[EAN] UPC Item DB error: #{e.message}" rescue nil
      end
    end

    # 3. Try Open GTINdb (European products)
    unless result
      begin
        uri = URI("https://opengtindb.org/api2.php?ean=#{code}&cmd=query&queryid=400000000")
        res = Net::HTTP.get_response(uri)
        if res.is_a?(Net::HTTPSuccess) && !res.body.include?("error")
          lines = res.body.strip.split("\n")
          # Format: error\nean\nname\ndetails...
          if lines.length >= 3 && lines[0].strip == "0"
            result = {
              source: "opengtindb",
              name: lines[2]&.strip,
              brand: lines[4]&.strip,
              categories: lines[3]&.strip,
            }
          end
        end
      rescue => e
        GardenLogger.info "[EAN] OpenGTINdb error: #{e.message}" rescue nil
      end
    end

    if result && result[:name]
      json(found: true, **result)
    else
      json(found: false, ean: code, message: "Not found in product databases")
    end
  end

  # Fetch enriched detail for a catalog entry (scrapes product page on first call, caches)
  get "/api/seeds/catalog/:id" do
    require_relative "../models/seed_catalog_entry"
    entry = SeedCatalogEntry[params[:id].to_i]
    halt 404, json(error: "Not found") unless entry

    entry.enrich!
    json({
      id: entry.id,
      variety_name: entry.variety_name,
      crop_type: entry.crop_type,
      supplier: entry.supplier,
      supplier_url: entry.supplier_url,
      description: entry.description,
      germination_temp: entry.germination_temp,
      spacing: entry.spacing,
      sowing_info: entry.sowing_info,
      notes: entry.notes_summary
    })
  end

  # Seed detail/new page routes removed — React SPA handles these

  post "/seeds" do
    packet = SeedPacket.create(
      garden_id:    @current_garden.id,
      variety_name: params[:variety_name].to_s.strip,
      crop_type:    params[:crop_type].to_s.strip.downcase,
      source:       params[:source].to_s.strip.then { |v| v.empty? ? nil : v },
      notes:        params[:notes].to_s.strip.then { |v| v.empty? ? nil : v },
      created_at:   Time.now,
      updated_at:   Time.now
    )
    redirect "/seeds/#{packet.id}"
  end

  patch "/seeds/:id" do
    packet = SeedPacket[params[:id].to_i]
    halt 404 unless packet
    packet.update(
      variety_name: params[:variety_name].to_s.strip,
      crop_type:    params[:crop_type].to_s.strip.downcase,
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
    json SeedPacket.where(garden_id: @current_garden.id).order(:crop_type, :variety_name).all.map(&:values)
  end

  # ── API-prefixed duplicates (SPA) ──────────────────────────────────────

  post "/api/seeds" do
    content_type :json
    request.body.rewind
    data = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    packet = SeedPacket.create(
      garden_id:    @current_garden.id,
      variety_name: data["variety_name"].to_s.strip,
      crop_type:    data["crop_type"].to_s.strip.downcase,
      source:       data["source"].to_s.strip.then { |v| v.empty? ? nil : v },
      notes:        data["notes"].to_s.strip.then { |v| v.empty? ? nil : v },
      created_at:   Time.now,
      updated_at:   Time.now
    )
    status 201
    json packet.values
  end

  patch "/api/seeds/:id" do
    content_type :json
    packet = SeedPacket[params[:id].to_i]
    halt 404, json(error: "Not found") unless packet

    request.body.rewind
    data = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    updates = {}
    updates[:variety_name] = data["variety_name"].to_s.strip if data["variety_name"]
    updates[:crop_type]    = data["crop_type"].to_s.strip.downcase if data["crop_type"]
    updates[:source]       = data["source"].to_s.strip.then { |v| v.empty? ? nil : v } if data.key?("source")
    updates[:notes]        = data["notes"].to_s.strip.then { |v| v.empty? ? nil : v } if data.key?("notes")
    updates[:updated_at]   = Time.now if updates.any?

    packet.update(updates) if updates.any?
    json packet.values
  end

  delete "/api/seeds/:id" do
    content_type :json
    packet = SeedPacket[params[:id].to_i]
    halt 404, json(error: "Not found") unless packet
    packet.destroy
    json(ok: true)
  end
end
