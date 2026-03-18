Sequel.migration do
  change do
    alter_table(:beds) do
      add_column :position, Integer, default: 0
    end

    # Set initial positions from current order
    self[:beds].order(:id).each_with_index do |bed, i|
      self[:beds].where(id: bed[:id]).update(position: i)
    end
  end
end
