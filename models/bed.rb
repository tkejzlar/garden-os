require "json"
require_relative "../config/database"

class Bed < Sequel::Model
  many_to_one :garden
  one_to_many :plants

  def grid_cols
    (((width || 100).to_f) / 10.0).ceil.clamp(1, 50)
  end

  def grid_rows
    (((length || 100).to_f) / 10.0).ceil.clamp(1, 50)
  end

  def canvas_points_array
    return [] unless canvas_points
    JSON.parse(canvas_points)
  rescue JSON::ParserError
    []
  end

  def canvas_points_array=(pts)
    self.canvas_points = pts.nil? || pts.empty? ? nil : pts.to_json
  end

  def placed?
    !canvas_x.nil?
  end

  def polygon?
    !canvas_points.nil?
  end
end

class Arch < Sequel::Model
  many_to_one :garden
end

class IndoorStation < Sequel::Model
  many_to_one :garden
end
