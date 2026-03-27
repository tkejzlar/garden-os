Sequel.migration do
  up do
    create_table(:garden_logs) do
      primary_key :id
      foreign_key :garden_id, :gardens
      String :log_type, default: 'note'  # watered, fertilized, pest, weather, note
      String :note
      DateTime :created_at
    end
  end

  down do
    drop_table(:garden_logs)
  end
end
