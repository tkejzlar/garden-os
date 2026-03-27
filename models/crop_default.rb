require_relative "../config/database"

class CropDefault < Sequel::Model
  # Cache lookups to avoid repeated DB hits
  def self.grid_size(crop_type)
    @cache ||= {}
    key = crop_type.to_s.downcase
    @cache[key] ||= begin
      row = first(name: key)
      row ? [row.grid_w, row.grid_h] : nil
    end
  end

  def self.clear_cache!
    @cache = {}
  end
end
