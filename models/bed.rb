require_relative "../config/database"
require "json"

class Bed < Sequel::Model
  many_to_one :garden
  one_to_many :rows

  # Returns parsed [[x,y],…] array, or [] when the bed is a rectangle / unplaced.
  def canvas_points_array
    canvas_points ? JSON.parse(canvas_points) : []
  end

  # Accepts an array of [x,y] pairs and serialises to JSON.
  def canvas_points_array=(pts)
    self.canvas_points = pts.nil? || pts.empty? ? nil : pts.to_json
  end

  # True when the bed has been placed on the canvas.
  def placed?
    !canvas_x.nil?
  end

  # True when this bed is a polygon rather than a rectangle.
  def polygon?
    !canvas_points.nil?
  end
end

class Row < Sequel::Model
  many_to_one :bed
  one_to_many :slots
end

class Slot < Sequel::Model
  many_to_one :row
  one_to_many :plants
end

class Arch < Sequel::Model
  many_to_one :garden
end

class IndoorStation < Sequel::Model
  many_to_one :garden
end
