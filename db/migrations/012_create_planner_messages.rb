Sequel.migration do
  change do
    create_table(:planner_messages) do
      primary_key :id
      String :role, null: false         # "user", "assistant", "system"
      String :content, text: true, null: false
      String :draft_payload, text: true  # JSON, nullable
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
