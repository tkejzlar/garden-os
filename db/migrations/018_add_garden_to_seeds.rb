Sequel.migration do
  up do
    alter_table(:seed_packets) { add_foreign_key :garden_id, :gardens }
    first_garden = self[:gardens].first
    if first_garden
      self[:seed_packets].update(garden_id: first_garden[:id])
    end
  end
  down do
    alter_table(:seed_packets) { drop_column :garden_id }
  end
end
