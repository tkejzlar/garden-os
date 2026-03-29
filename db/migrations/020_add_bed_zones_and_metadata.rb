Sequel.migration do
  change do
    alter_table(:beds) do
      add_column :sun_exposure, String
      add_column :wind_exposure, String
      add_column :irrigation, String
      add_column :front_edge, String
    end

    create_table(:bed_zones) do
      primary_key :id
      foreign_key :bed_id, :beds, on_delete: :cascade, null: false
      String :name, null: false
      Integer :from_x, null: false
      Integer :from_y, null: false
      Integer :to_x, null: false
      Integer :to_y, null: false
      String :purpose
      String :notes
      DateTime :created_at
    end
  end
end
