require_relative "../config/database"

class Photo < Sequel::Model
  many_to_one :plant
  many_to_one :bed

  UPLOAD_ROOT = File.expand_path("../public/uploads", __dir__).freeze
  MAX_BYTES   = 10 * 1024 * 1024  # 10 MB

  # Absolute path to the original file on disk.
  def file_path
    File.join(UPLOAD_ROOT, filename)
  end

  # Absolute path to the thumbnail (200px-wide), or nil if it does not exist.
  def thumbnail_path
    thumb = file_path.sub(/(\.\w+)$/, "_thumb\\1")
    File.exist?(thumb) ? thumb : nil
  end

  # Web-accessible URL path for use in src= attributes.
  def url
    "/uploads/#{filename}"
  end

  # Web-accessible URL path for the thumbnail, falling back to the original.
  def thumbnail_url
    thumb_file = file_path.sub(/(\.\w+)$/, "_thumb\\1")
    if File.exist?(thumb_file)
      "/uploads/#{filename.sub(/(\.\w+)$/, '_thumb\\1')}"
    else
      url
    end
  end

  # Generate a thumbnail with ImageMagick. Silently skips if `convert` is
  # unavailable or the conversion fails.
  def generate_thumbnail!
    thumb = file_path.sub(/(\.\w+)$/, "_thumb\\1")
    system("convert", "-resize", "200x", file_path, thumb)
  end

  # Delete the file (and thumbnail if present) from disk. Call before
  # destroying the record.
  def delete_files!
    File.delete(file_path) if File.exist?(file_path)
    thumb = file_path.sub(/(\.\w+)$/, "_thumb\\1")
    File.delete(thumb) if File.exist?(thumb)
  end

  # Build a datestamped relative storage path, e.g. "2026/03/abc123.jpg".
  # The caller is responsible for ensuring the directory exists.
  def self.storage_path(original_filename)
    now = Time.now
    ext = File.extname(original_filename).downcase
    basename = "#{now.to_i}_#{SecureRandom.hex(6)}#{ext}"
    File.join(now.strftime("%Y"), now.strftime("%m"), basename)
  end
end
