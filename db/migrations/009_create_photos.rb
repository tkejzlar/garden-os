Sequel.migration do
  change do
    create_table(:photos) do
      primary_key :id
      foreign_key :plant_id, :plants, on_delete: :set_null
      foreign_key :bed_id, :beds, on_delete: :set_null
      String :lifecycle_stage
      String :filename, null: false
      Text   :caption
      DateTime :taken_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      index :plant_id
      index :bed_id
    end
  end
end
