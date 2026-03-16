require "securerandom"
require_relative "../models/plant"
require_relative "../models/photo"

class GardenApp
  # POST /plants/:id/photos — multipart file upload
  post "/plants/:id/photos" do
    plant = Plant[params[:id].to_i]
    halt 404, "Plant not found" unless plant

    upload = params[:photo]
    halt 400, "No file provided" unless upload && upload[:tempfile]

    # Enforce 10 MB limit
    tempfile = upload[:tempfile]
    tempfile.seek(0, IO::SEEK_END)
    halt 413, "File too large (max 10 MB)" if tempfile.pos > Photo::MAX_BYTES
    tempfile.rewind

    rel_path  = Photo.storage_path(upload[:filename])
    full_path = File.join(Photo::UPLOAD_ROOT, rel_path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.open(full_path, "wb") { |f| f.write(tempfile.read) }

    photo = Photo.create(
      plant_id:        plant.id,
      lifecycle_stage: plant.lifecycle_stage,
      filename:        rel_path,
      caption:         params[:caption].to_s.strip.then { |s| s.empty? ? nil : s },
      taken_at:        Time.now
    )
    photo.generate_thumbnail!

    redirect "/plants/#{plant.id}"
  end

  # GET /plants/:id/photos — full photo gallery for a plant
  get "/plants/:id/photos" do
    @plant  = Plant[params[:id].to_i]
    halt 404, "Plant not found" unless @plant
    @photos = Photo.where(plant_id: @plant.id).order(Sequel.desc(:taken_at)).all
    erb :"plants/photos"
  end

  # DELETE /photos/:id — delete record and file
  delete "/photos/:id" do
    photo = Photo[params[:id].to_i]
    halt 404, "Photo not found" unless photo
    plant_id = photo.plant_id
    photo.delete_files!
    photo.destroy
    redirect plant_id ? "/plants/#{plant_id}" : "/"
  end
end
