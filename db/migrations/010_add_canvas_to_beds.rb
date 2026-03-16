# db/migrations/010_add_canvas_to_beds.rb
Sequel.migration do
  change do
    alter_table(:beds) do
      add_column :canvas_x,      Float,  null: true
      add_column :canvas_y,      Float,  null: true
      add_column :canvas_width,  Float,  null: true
      add_column :canvas_height, Float,  null: true
      add_column :canvas_points, String, text: true, null: true  # JSON [[x,y],…], null = rectangle
      add_column :canvas_color,  String, null: true              # e.g. "#86efac", null = default
    end
  end
end
