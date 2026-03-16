Sequel.migration do
  change do
    create_table(:advisories) do
      primary_key :id
      Date :date, null: false
      String :advisory_type
      String :content, text: true, null: false
      Integer :plant_id
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      index :date
    end
  end
end
