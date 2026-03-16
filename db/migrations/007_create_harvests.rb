Sequel.migration do
  change do
    create_table(:harvests) do
      primary_key :id
      foreign_key :plant_id, :plants, null: false, on_delete: :cascade
      Date :date, null: false, default: Sequel::CURRENT_DATE
      String :quantity, null: false   # enum: small | medium | large | huge
      String :notes
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      index :plant_id
    end
  end
end
