require "json"
require_relative "../config/database"

class Bed < Sequel::Model
  many_to_one :garden
  one_to_many :plants

  def grid_cols
    w = (width || 0).to_f
    # For polygon beds with no width, derive from canvas_points bounding box
    if w <= 0 && polygon?
      pts = canvas_points_array
      xs = pts.map { |p| p[0] }
      w = (xs.max - xs.min).to_f if xs.any?
    end
    w = 100.0 if w <= 0
    (w / 10.0).ceil.clamp(1, 50)
  end

  def grid_rows
    l = (length || 0).to_f
    if l <= 0 && polygon?
      pts = canvas_points_array
      ys = pts.map { |p| p[1] }
      l = (ys.max - ys.min).to_f if ys.any?
    end
    l = 100.0 if l <= 0
    (l / 10.0).ceil.clamp(1, 50)
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
