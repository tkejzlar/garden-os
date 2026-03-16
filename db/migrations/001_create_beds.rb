Sequel.migration do
  change do
    create_table(:beds) do
      primary_key :id
      String :name, null: false, unique: true
      String :bed_type, default: "raised"
      Float :length
      Float :width
      String :orientation
      String :wall_type
      String :notes
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:rows) do
      primary_key :id
      foreign_key :bed_id, :beds, null: false, on_delete: :cascade
      String :name, null: false
      Integer :position
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:slots) do
      primary_key :id
      foreign_key :row_id, :rows, null: false, on_delete: :cascade
      String :name, null: false
      Integer :position
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:arches) do
      primary_key :id
      String :name, null: false, unique: true
      String :between_beds
      Float :gap_width
      String :spring_crop
      String :summer_crop
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:indoor_stations) do
      primary_key :id
      String :name, null: false, unique: true
      String :station_type
      Float :target_temp
      String :notes
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
