Sequel.migration do
  change do
    create_table(:plants) do
      primary_key :id
      String :variety_name, null: false
      String :crop_type, null: false
      String :source
      foreign_key :slot_id, :slots, on_delete: :set_null
      foreign_key :indoor_station_id, :indoor_stations, on_delete: :set_null
      String :lifecycle_stage, null: false, default: "seed_packet"
      Date :sow_date
      Date :germination_date
      Date :transplant_date
      Integer :succession_group_id
      String :notes
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
      index :lifecycle_stage
      index :crop_type
    end
  end
end
