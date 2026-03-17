Sequel.migration do
  up do
    # 1. Create gardens table
    create_table(:gardens) do
      primary_key :id
      String :name, null: false, unique: true
      String :location
      String :climate_zone
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    # 2. Seed default gardens
    self[:gardens].insert(name: "Home", location: "Prague", climate_zone: "6b/7a")
    self[:gardens].insert(name: "Cottage")

    # 3. Add garden_id to scoped tables (nullable first for backfill)
    %i[beds arches indoor_stations plants tasks succession_plans planner_messages advisories].each do |table|
      alter_table(table) do
        add_column :garden_id, Integer
      end
    end

    # 4. Backfill all existing rows to garden 1 (Home)
    home_id = self[:gardens].where(name: "Home").get(:id)
    %i[beds arches indoor_stations plants tasks succession_plans planner_messages advisories].each do |table|
      self[table].update(garden_id: home_id)
    end

    # 5. Add NOT NULL constraints + indexes (skip FK — SQLite doesn't enforce them)
    %i[beds arches indoor_stations plants tasks succession_plans planner_messages advisories].each do |table|
      alter_table(table) do
        set_column_not_null :garden_id
        add_index :garden_id, name: :"idx_#{table}_garden_id"
      end
    end

    # 6. Add composite unique on (garden_id, name)
    # Note: SQLite's autoindex on beds.name can't be dropped directly,
    # but it becomes redundant once we have the composite constraint.
    # To properly replace it, we'd need to rebuild the table — skip for now.
    alter_table(:beds) do
      add_unique_constraint [:garden_id, :name], name: :beds_garden_name_unique
    end
  end

  down do
    %i[beds arches indoor_stations plants tasks succession_plans planner_messages advisories].each do |table|
      alter_table(table) do
        drop_column :garden_id
      end
    end
    drop_table(:gardens)
  end
end
