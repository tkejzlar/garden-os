Sequel.migration do
  up do
    alter_table(:plants) do
      add_column :grid_x, Integer
      add_column :grid_y, Integer
      add_column :grid_w, Integer, default: 1
      add_column :grid_h, Integer, default: 1
      add_column :quantity, Integer, default: 1
      add_foreign_key :bed_id, :beds, on_delete: :set_null
    end

    self[:plants].update(slot_id: nil)

    alter_table(:plants) do
      drop_foreign_key :slot_id
    end
    drop_table(:slots)
    drop_table(:rows)
  end

  down do
    create_table(:rows) do
      primary_key :id
      foreign_key :bed_id, :beds, on_delete: :cascade
      String :name
      Integer :position, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:slots) do
      primary_key :id
      foreign_key :row_id, :rows, on_delete: :cascade
      String :name
      Integer :position, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    alter_table(:plants) do
      add_foreign_key :slot_id, :slots, on_delete: :set_null
      drop_foreign_key :bed_id
      drop_column :grid_x
      drop_column :grid_y
      drop_column :grid_w
      drop_column :grid_h
      drop_column :quantity
    end
  end
end
