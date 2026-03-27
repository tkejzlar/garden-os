Sequel.migration do
  up do
    # Double all plant grid positions/sizes (10cm cells → 5cm cells)
    self[:plants].all.each do |plant|
      self[:plants].where(id: plant[:id]).update(
        grid_x: (plant[:grid_x] || 0) * 2,
        grid_y: (plant[:grid_y] || 0) * 2,
        grid_w: (plant[:grid_w] || 1) * 2,
        grid_h: (plant[:grid_h] || 1) * 2
      )
    end

    # Double crop_defaults grid sizes
    self[:crop_defaults].all.each do |cd|
      self[:crop_defaults].where(id: cd[:id]).update(
        grid_w: cd[:grid_w] * 2,
        grid_h: cd[:grid_h] * 2
      )
    end
  end

  down do
    self[:plants].all.each do |plant|
      self[:plants].where(id: plant[:id]).update(
        grid_x: (plant[:grid_x] || 0) / 2,
        grid_y: (plant[:grid_y] || 0) / 2,
        grid_w: [plant[:grid_w].to_i / 2, 1].max,
        grid_h: [plant[:grid_h].to_i / 2, 1].max
      )
    end
    self[:crop_defaults].all.each do |cd|
      self[:crop_defaults].where(id: cd[:id]).update(
        grid_w: [cd[:grid_w] / 2, 1].max,
        grid_h: [cd[:grid_h] / 2, 1].max
      )
    end
  end
end
