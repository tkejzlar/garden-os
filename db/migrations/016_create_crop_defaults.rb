Sequel.migration do
  up do
    create_table(:crop_defaults) do
      primary_key :id
      String :name, null: false        # e.g. "tomato", "basil"
      Integer :grid_w, null: false, default: 2
      Integer :grid_h, null: false, default: 2
      String :notes                     # e.g. "staked, single stem"
      DateTime :created_at
      DateTime :updated_at
      unique :name
    end

    # Seed with intensive raised-bed spacing defaults
    {
      "tomato"    => [3, 3, "staked, single stem"],
      "pepper"    => [3, 3, nil],
      "eggplant"  => [3, 3, nil],
      "lettuce"   => [2, 2, nil],
      "spinach"   => [1, 2, "narrow rows"],
      "chard"     => [2, 3, nil],
      "kale"      => [3, 3, nil],
      "herb"      => [2, 2, nil],
      "basil"     => [2, 2, nil],
      "cucumber"  => [3, 3, "trellised vertically"],
      "squash"    => [4, 4, "sprawling"],
      "zucchini"  => [3, 4, nil],
      "melon"     => [4, 4, "sprawling"],
      "flower"    => [2, 2, nil],
      "radish"    => [1, 1, "dense"],
      "carrot"    => [1, 1, "dense"],
      "onion"     => [1, 1, "dense"],
      "bean"      => [2, 2, "pole, trellised"],
      "pea"       => [1, 2, "trellised"],
    }.each do |name, (w, h, notes)|
      self[:crop_defaults].insert(name: name, grid_w: w, grid_h: h, notes: notes, created_at: Time.now, updated_at: Time.now)
    end
  end

  down do
    drop_table(:crop_defaults)
  end
end
