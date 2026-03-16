Sequel.migration do
  change do
    create_table(:seed_packets) do
      primary_key :id
      String :variety_name, null: false
      String :crop_type, null: false
      String :source
      Integer :quantity_remaining
      Date :sow_by_date
      Date :purchase_date
      String :url
      String :notes, text: true
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
      index :crop_type
    end
  end
end
