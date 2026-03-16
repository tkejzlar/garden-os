Sequel.migration do
  change do
    create_table(:succession_plans) do
      primary_key :id
      String :crop, null: false
      String :varieties
      Integer :interval_days, null: false
      Date :season_start
      Date :season_end
      String :target_beds
      Integer :total_planned_sowings
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
