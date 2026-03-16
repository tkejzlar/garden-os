Sequel.migration do
  change do
    create_table(:seed_catalog_entries) do
      primary_key :id
      String :variety_name, null: false
      String :variety_name_normalized, null: false  # lowercase, stripped accents for search
      String :crop_type, null: false                # tomato, pepper, etc.
      String :crop_subcategory                      # "flesh tomato", "cocktail tomato", etc.
      String :supplier, null: false                 # reinsaat, bingenheimer, sativa, magic_garden, loukykvet
      String :supplier_url                          # link to product page
      String :article_number                        # supplier's SKU
      String :latin_name                            # Solanum lycopersicum L.
      String :description, text: true               # scraped product description
      String :germination_temp                      # "20-24°C"
      String :spacing                               # "60×50cm"
      String :days_to_maturity                      # "65-75"
      String :sowing_info, text: true               # full sowing instructions
      TrueClass :frost_tender
      TrueClass :direct_sow
      DateTime :scraped_at
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index :variety_name_normalized
      index :crop_type
      index :supplier
    end
  end
end
