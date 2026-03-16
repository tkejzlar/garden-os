Sequel.migration do
  change do
    create_table(:tasks) do
      primary_key :id
      String :title, null: false
      String :task_type, null: false
      Date :due_date
      String :conditions
      String :priority, default: "should"
      String :status, default: "upcoming"
      String :recurrence
      String :notes
      DateTime :completed_at
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
      index :status
      index :due_date
    end

    create_table(:tasks_plants) do
      foreign_key :task_id, :tasks, on_delete: :cascade
      foreign_key :plant_id, :plants, on_delete: :cascade
      primary_key [:task_id, :plant_id]
    end

    create_table(:tasks_beds) do
      foreign_key :task_id, :tasks, on_delete: :cascade
      foreign_key :bed_id, :beds, on_delete: :cascade
      primary_key [:task_id, :bed_id]
    end
  end
end
