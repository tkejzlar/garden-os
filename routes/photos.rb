require "securerandom"
require_relative "../models/plant"
require_relative "../models/photo"

class GardenApp
  # POST /plants/:id/photos — multipart file upload
  post "/plants/:id/photos" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant

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

  # Photo gallery page route removed — React SPA handles this

  # DELETE /photos/:id — delete record and file
  delete "/photos/:id" do
    photo = Photo[params[:id].to_i]
    halt 404 unless photo
    plant_id = photo.plant_id
    photo.delete_files!
    photo.destroy
    redirect plant_id ? "/plants/#{plant_id}" : "/"
  end

  # ── API versions (JSON, no redirects) ──

  # API version of photo upload
  post "/api/plants/:id/photos" do
    content_type :json
    plant = Plant[params[:id].to_i]
    halt 404, json(error: "Not found") unless plant

    upload = params[:photo]
    halt 400, json(error: "No file provided") unless upload && upload[:tempfile]

    tempfile = upload[:tempfile]
    tempfile.seek(0, IO::SEEK_END)
    halt 413, json(error: "File too large (max 10 MB)") if tempfile.pos > Photo::MAX_BYTES
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

    json({ id: photo.id, url: "/uploads/#{photo.filename}", taken_at: photo.taken_at&.to_s, caption: photo.caption, lifecycle_stage: photo.lifecycle_stage })
  end

  # API version of photo list
  get "/api/plants/:id/photos" do
    content_type :json
    plant = Plant[params[:id].to_i]
    halt 404, json(error: "Not found") unless plant
    photos = Photo.where(plant_id: plant.id).order(Sequel.desc(:taken_at)).all
    json photos.map { |p|
      { id: p.id, url: "/uploads/#{p.filename}", taken_at: p.taken_at&.to_s, caption: p.caption, lifecycle_stage: p.lifecycle_stage }
    }
  end

  # API version of photo delete
  delete "/api/plants/:id/photos/:photo_id" do
    content_type :json
    photo = Photo[params[:photo_id].to_i]
    halt 404, json(error: "Not found") unless photo
    photo.delete_files!
    photo.destroy
    json(ok: true)
  end
end
