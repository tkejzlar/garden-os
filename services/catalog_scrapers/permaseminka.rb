module CatalogScrapers
  class Permaseminka
    BASE = "https://permaseminka.cz"

    # Categories with their crop_type mapping
    # Czech site — variety names may be in Czech or international names
    CATEGORIES = {
      "12-rajcata"          => "tomato",
      "23-papriky-a-chilli" => "pepper",
      "14-okurky"           => "cucumber",
      "21-fazole"           => "bean",
      "49-korenova-zelenina" => "root",
      "18-listova-zelenina" => "lettuce",
      "75-cibulova-zelenina" => "onion",
      "59-jedle-kvety"      => "flower",
      "29-jedle-trvalky"    => "herb",
      "33-samovysevne"      => "flower",
    }.freeze

    def self.scrape
      entries = []

      CATEGORIES.each do |slug, crop_type|
        page = 1
        loop do
          sleep 1
          url = "#{BASE}/#{slug}"
          url += "?p=#{page}" if page > 1
          doc = CatalogScraper.fetch_page(url)
          break unless doc

          products_found = 0
          # PrestaShop product links — look for links ending in .html within the category
          doc.css("a[href*='.html']").each do |link|
            href = link["href"].to_s
            next unless href.include?(slug.split("-", 2).last) || href.match?(/\/\d+-[a-z]/)
            next if href.include?("?")

            name = link.text.strip
            # Skip navigation/menu items
            next if name.empty? || name.length > 100 || name.length < 2
            # Skip common non-product link text
            next if name.match?(/košík|přidat|detail|více|home|obchod|kontakt/i)

            full_url = href.start_with?("http") ? href : "#{BASE}#{href}"

            entries << {
              variety_name:     name,
              crop_type:        crop_type,
              crop_subcategory: nil,
              url:              full_url,
              article_number:   nil,
              latin_name:       nil,
              description:      nil,
              germination_temp: nil,
              spacing:          nil,
              days_to_maturity: nil,
              sowing_info:      nil,
              frost_tender:     nil,
              direct_sow:       nil,
            }
            products_found += 1
          end

          puts "  #{slug} page #{page}: #{products_found} products"
          # Check for next page link
          break if products_found == 0
          break unless doc.css("a[rel='next'], a.next, .pagination a").any? { |a| a.text.include?("›") || a.text.include?("»") || a.text.strip == (page + 1).to_s }
          page += 1
          break if page > 20 # safety limit
        end
      end

      # Deduplicate by URL
      entries.uniq { |e| e[:url] }
    end
  end
end
