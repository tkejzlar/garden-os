require "json"
require_relative "../config/database"

class Bed < Sequel::Model
  many_to_one :garden
  one_to_many :plants
  one_to_many :bed_zones

  def grid_cols
    w = (width || 0).to_f
    # For polygon beds with no width, derive from canvas_points bounding box
    if w <= 0 && polygon?
      pts = canvas_points_array
      xs = pts.map { |p| p[0] }
      w = (xs.max - xs.min).to_f if xs.any?
    end
    w = 100.0 if w <= 0
    (w / 5.0).ceil.clamp(1, 100)
  end

  def grid_rows
    l = (length || 0).to_f
    if l <= 0 && polygon?
      pts = canvas_points_array
      ys = pts.map { |p| p[1] }
      l = (ys.max - ys.min).to_f if ys.any?
    end
    l = 100.0 if l <= 0
    (l / 5.0).ceil.clamp(1, 100)
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

  # Ray-casting point-in-polygon test.
  # grid_x, grid_y are in 5cm grid cells. Converts to canvas coords using bounding box.
  def point_in_polygon?(grid_x, grid_y)
    return true unless polygon?
    pts = canvas_points_array
    return true if pts.length < 3

    # Convert grid coords to canvas coords
    xs = pts.map { |p| p[0] }
    ys = pts.map { |p| p[1] }
    min_x, max_x = xs.min, xs.max
    min_y, max_y = ys.min, ys.max
    poly_w = max_x - min_x
    poly_h = max_y - min_y
    return true if poly_w == 0 || poly_h == 0

    # Cell center in canvas coords
    cx = min_x + (grid_x * 5.0 + 2.5) * poly_w / (grid_cols * 5.0)
    cy = min_y + (grid_y * 5.0 + 2.5) * poly_h / (grid_rows * 5.0)

    # Ray-casting algorithm
    inside = false
    j = pts.length - 1
    pts.length.times do |i|
      xi, yi = pts[i]
      xj, yj = pts[j]
      if ((yi > cy) != (yj > cy)) && (cx < (xj - xi) * (cy - yi) / (yj - yi) + xi)
        inside = !inside
      end
      j = i
    end
    inside
  end
end

class Arch < Sequel::Model
  many_to_one :garden
end

class IndoorStation < Sequel::Model
  many_to_one :garden
end
