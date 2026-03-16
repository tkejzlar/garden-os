require_relative "../test_helper"
require_relative "../../app"
require "tempfile"

class TestPhotos < GardenTest
  def setup
    super
    @plant = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seedling")
    # Point upload root to a temp directory so tests never touch public/
    @tmp_dir = Dir.mktmpdir("garden_photos_test")
    Photo.send(:remove_const, :UPLOAD_ROOT) rescue nil
    Photo.const_set(:UPLOAD_ROOT, @tmp_dir)
  end

  def teardown
    FileUtils.remove_entry(@tmp_dir) if File.exist?(@tmp_dir)
  end

  # --- Upload ---

  def test_upload_photo_redirects_to_plant
    post "/plants/#{@plant.id}/photos", photo_params("test.jpg")
    assert_equal 302, last_response.status
    assert_includes last_response.headers["Location"], "/plants/#{@plant.id}"
  end

  def test_upload_creates_db_record
    post "/plants/#{@plant.id}/photos", photo_params("test.jpg")
    assert_equal 1, Photo.count
    photo = Photo.first
    assert_equal @plant.id,          photo.plant_id
    assert_equal "seedling",         photo.lifecycle_stage
    assert_match /\.jpg$/,           photo.filename
  end

  def test_upload_saves_file_to_disk
    post "/plants/#{@plant.id}/photos", photo_params("test.jpg")
    photo = Photo.first
    assert File.exist?(photo.file_path), "Expected file at #{photo.file_path}"
  end

  def test_upload_with_caption
    post "/plants/#{@plant.id}/photos", photo_params("test.jpg").merge(caption: "First leaf!")
    assert_equal "First leaf!", Photo.first.caption
  end

  def test_upload_rejects_missing_file
    post "/plants/#{@plant.id}/photos", {}
    assert_equal 400, last_response.status
  end

  def test_upload_rejects_oversized_file
    # Build a 1-byte-over-limit tempfile
    oversized = Tempfile.new(["big", ".jpg"])
    oversized.write("x" * (Photo::MAX_BYTES + 1))
    oversized.flush
    oversized.rewind
    uf = Rack::Test::UploadedFile.new(oversized.path, "image/jpeg", true)
    post "/plants/#{@plant.id}/photos", { photo: uf }
    assert_equal 413, last_response.status
  ensure
    oversized&.close!
  end

  def test_upload_returns_404_for_unknown_plant
    post "/plants/99999/photos", photo_params("test.jpg")
    assert_equal 404, last_response.status
  end

  # --- Gallery page ---

  def test_gallery_page_renders
    get "/plants/#{@plant.id}/photos"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "No photos yet"
  end

  def test_gallery_page_lists_photos
    post "/plants/#{@plant.id}/photos", photo_params("a.jpg").merge(caption: "Day one")
    get "/plants/#{@plant.id}/photos"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Day one"
  end

  # --- Delete ---

  def test_delete_removes_record
    post "/plants/#{@plant.id}/photos", photo_params("del.jpg")
    photo = Photo.first
    delete "/photos/#{photo.id}"
    assert_equal 0, Photo.count
  end

  def test_delete_removes_file_from_disk
    post "/plants/#{@plant.id}/photos", photo_params("del.jpg")
    photo = Photo.first
    path = photo.file_path
    assert File.exist?(path)
    delete "/photos/#{photo.id}"
    refute File.exist?(path)
  end

  def test_delete_redirects_to_plant
    post "/plants/#{@plant.id}/photos", photo_params("del.jpg")
    photo = Photo.first
    delete "/photos/#{photo.id}"
    assert_equal 302, last_response.status
    assert_includes last_response.headers["Location"], "/plants/#{@plant.id}"
  end

  def test_delete_returns_404_for_unknown_photo
    delete "/photos/99999"
    assert_equal 404, last_response.status
  end

  # --- Plant show page includes photos ---

  def test_plant_show_includes_photo_thumbnails
    post "/plants/#{@plant.id}/photos", photo_params("vis.jpg").merge(caption: "Visible")
    get "/plants/#{@plant.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Visible"
  end

  private

  def photo_params(filename)
    tf = Tempfile.new([File.basename(filename, ".*"), File.extname(filename)])
    tf.write("\xff\xd8\xff\xe0" + "fake jpeg data")  # minimal JPEG magic bytes
    tf.flush
    tf.rewind
    # Store tempfile reference so GC doesn't close it before Rack reads it
    @tempfiles ||= []
    @tempfiles << tf
    uf = Rack::Test::UploadedFile.new(tf.path, "image/jpeg", true)
    { photo: uf }
  end
end
