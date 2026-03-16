Sequel.migration do
  change do
    create_table(:stage_histories) do
      primary_key :id
      foreign_key :plant_id, :plants, null: false, on_delete: :cascade
      String :from_stage
      String :to_stage, null: false
      String :note
      DateTime :changed_at, default: Sequel::CURRENT_TIMESTAMP
      index :plant_id
    end
  end
end
