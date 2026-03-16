require "json"

module Varieties
  DATA_PATH = File.join(File.dirname(__FILE__), "varieties.json")

  def self.all
    @all ||= JSON.parse(File.read(DATA_PATH))
  end

  def self.for(crop_type)
    all[crop_type.to_s.downcase]
  end

  # Prague climate defaults
  LAST_FROST_DATE = Date.new(Date.today.year, 5, 13)
  FIRST_FROST_DATE = Date.new(Date.today.year, 10, 15)
end
