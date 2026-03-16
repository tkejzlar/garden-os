# Seed Catalog Scraper Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scrape seed varieties from 5 European organic suppliers into a local database, then use fuzzy matching to auto-fill seed packet details — replacing the unreliable LLM-based lookup.

**Architecture:** A Rake task scrapes supplier category and product pages using `Net::HTTP` + Nokogiri, storing results in a `seed_catalog` table. The seed form searches this table with SQLite `LIKE` for instant fuzzy matching. LLM lookup is demoted to fallback-only when no catalog match is found.

**Tech Stack:** Nokogiri (HTML parsing), Net::HTTP (fetching), SQLite FTS or LIKE (search)

---

## Supplier Analysis

| Supplier | Base URL | Category pattern | Product pattern | Language |
|----------|----------|-----------------|-----------------|----------|
| Reinsaat | reinsaat.at/shop/EN/ | `/shop/EN/tomatoes/` | `/shop/EN/tomatoes/raf/` | EN |
| Bingenheimer | bingenheimersaatgut.de/en/ | `/en/organic-seeds/vegetables/` | `/en/organic-seeds/.../tanja-g174` | EN |
| Sativa | sativa.bio/en/ | `/en/vegetables/tomatoes` | `/en/[name]-[code]` | EN |
| Magic Garden | magicgardenseeds.com | `/Vegetable-Seeds` | `/[product-slug]` | EN |
| Loukykvět | loukykvet.cz | `/obchod/semena` | `/obchod/[id]-[slug]` | CZ |

---

## File Structure

```
New/Modified:
├── db/migrations/011_create_seed_catalog.rb     # NEW — catalog table
├── models/seed_catalog_entry.rb                  # NEW — model
├── services/catalog_scraper.rb                   # NEW — scraping logic
├── services/catalog_scrapers/                    # NEW — one file per supplier
│   ├── reinsaat.rb
│   ├── bingenheimer.rb
│   ├── sativa.rb
│   ├── magic_garden.rb
│   └── loukykvet.rb
├── services/variety_lookup_service.rb            # MODIFY — search catalog first, AI fallback
├── routes/seeds.rb                               # MODIFY — update lookup endpoint
├── views/seeds/show.erb                          # MODIFY — show catalog match vs AI result
├── Gemfile                                       # MODIFY — add nokogiri
├── Rakefile                                      # MODIFY — add scrape tasks
├── test/services/test_catalog_scraper.rb         # NEW
├── test/models/test_seed_catalog_entry.rb        # NEW
```

---

### Task 1: Migration + Model for Seed Catalog

**Files:**
- Create: `db/migrations/011_create_seed_catalog.rb`
- Create: `models/seed_catalog_entry.rb`
- Create: `test/models/test_seed_catalog_entry.rb`

- [ ] **Step 1: Create migration**

```ruby
# db/migrations/011_create_seed_catalog.rb
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
```

- [ ] **Step 2: Create model**

```ruby
# models/seed_catalog_entry.rb
require_relative "../config/database"

class SeedCatalogEntry < Sequel::Model
  # Fuzzy search by variety name — case-insensitive, partial match
  def self.search(query)
    return [] if query.nil? || query.strip.empty?
    normalized = normalize(query)
    where(Sequel.like(:variety_name_normalized, "%#{normalized}%"))
      .order(:variety_name)
      .limit(10)
      .all
  end

  # Normalize a string for matching: lowercase, strip accents, collapse whitespace
  def self.normalize(str)
    str.to_s.downcase
       .tr("áàâäãåčçďéèêëěíìîïňóòôöõřšťúùûüůýžñ",
           "aaaaaaccdeeeeeiiiinooooorstuuuuuyznc")
       .gsub(/[^a-z0-9\s]/, "")
       .gsub(/\s+/, " ")
       .strip
  end

  def notes_summary
    parts = [
      crop_subcategory,
      description&.slice(0, 200),
      days_to_maturity ? "#{days_to_maturity} days" : nil,
      germination_temp ? "Germ: #{germination_temp}" : nil,
      spacing ? "Spacing: #{spacing}" : nil,
      frost_tender ? "Frost tender" : (frost_tender == false ? "Frost hardy" : nil),
      sowing_info&.slice(0, 150)
    ].compact
    parts.join(". ")
  end
end
```

- [ ] **Step 3: Write test**

```ruby
# test/models/test_seed_catalog_entry.rb
require_relative "../test_helper"
require_relative "../../models/seed_catalog_entry"

class TestSeedCatalogEntry < GardenTest
  def test_normalize_strips_accents
    assert_equal "loukykvet", SeedCatalogEntry.normalize("Loukykvět")
    assert_equal "ochsenherz", SeedCatalogEntry.normalize("Öchsenherz")
  end

  def test_search_finds_partial_match
    SeedCatalogEntry.create(
      variety_name: "Raf", variety_name_normalized: "raf",
      crop_type: "tomato", supplier: "reinsaat", scraped_at: Time.now
    )
    results = SeedCatalogEntry.search("raf")
    assert_equal 1, results.length
    assert_equal "tomato", results.first.crop_type
  end

  def test_search_case_insensitive
    SeedCatalogEntry.create(
      variety_name: "Roviga", variety_name_normalized: "roviga",
      crop_type: "pepper", supplier: "reinsaat", scraped_at: Time.now
    )
    results = SeedCatalogEntry.search("ROVIGA")
    assert_equal 1, results.length
  end

  def test_search_empty_returns_empty
    assert_equal [], SeedCatalogEntry.search("")
    assert_equal [], SeedCatalogEntry.search(nil)
  end
end
```

- [ ] **Step 4: Run tests**

Run: `rm -f db/garden_os_test.db && ruby test/models/test_seed_catalog_entry.rb`
Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add db/migrations/011_create_seed_catalog.rb models/seed_catalog_entry.rb test/models/test_seed_catalog_entry.rb
git commit -m "feat: seed catalog table and model with fuzzy search"
```

---

### Task 2: Add Nokogiri + Rake Tasks

**Files:**
- Modify: `Gemfile` — add `gem "nokogiri"`
- Modify: `Rakefile` — add `catalog:scrape` tasks

- [ ] **Step 1: Add nokogiri to Gemfile**

Add after the `ruby_llm` line:
```ruby
gem "nokogiri", "~> 1.16"
```

Run: `bundle install`

- [ ] **Step 2: Add Rake tasks to Rakefile**

```ruby
namespace :catalog do
  desc "Scrape all seed suppliers"
  task :scrape do
    require_relative "config/database"
    require_relative "models/seed_catalog_entry"
    require_relative "services/catalog_scraper"

    Sequel::Migrator.run(DB, "db/migrations")
    CatalogScraper.scrape_all!
  end

  desc "Scrape a single supplier (e.g. rake catalog:scrape_one[reinsaat])"
  task :scrape_one, [:supplier] do |t, args|
    require_relative "config/database"
    require_relative "models/seed_catalog_entry"
    require_relative "services/catalog_scraper"

    Sequel::Migrator.run(DB, "db/migrations")
    CatalogScraper.scrape_supplier!(args[:supplier])
  end

  desc "Show catalog stats"
  task :stats do
    require_relative "config/database"
    require_relative "models/seed_catalog_entry"

    Sequel::Migrator.run(DB, "db/migrations")
    total = SeedCatalogEntry.count
    by_supplier = SeedCatalogEntry.group_and_count(:supplier).all
    puts "Seed catalog: #{total} varieties"
    by_supplier.each { |r| puts "  #{r[:supplier]}: #{r[:count]}" }
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock Rakefile
git commit -m "feat: add nokogiri + catalog scrape rake tasks"
```

---

### Task 3: Catalog Scraper — Core + Reinsaat

**Files:**
- Create: `services/catalog_scraper.rb`
- Create: `services/catalog_scrapers/reinsaat.rb`
- Create: `test/services/test_catalog_scraper.rb`

- [ ] **Step 1: Create the core scraper orchestrator**

```ruby
# services/catalog_scraper.rb
require "net/http"
require "nokogiri"
require "uri"
require_relative "../models/seed_catalog_entry"

class CatalogScraper
  SCRAPERS = %w[reinsaat bingenheimer sativa magic_garden loukykvet].freeze

  def self.scrape_all!
    SCRAPERS.each { |s| scrape_supplier!(s) }
  end

  def self.scrape_supplier!(name)
    require_relative "catalog_scrapers/#{name}"
    klass = Object.const_get("CatalogScrapers::#{name.split('_').map(&:capitalize).join}")
    puts "Scraping #{name}..."

    # Clear old entries for this supplier before re-scraping
    SeedCatalogEntry.where(supplier: name).delete

    entries = klass.scrape
    entries.each do |entry|
      SeedCatalogEntry.create(
        variety_name:            entry[:variety_name],
        variety_name_normalized: SeedCatalogEntry.normalize(entry[:variety_name]),
        crop_type:               entry[:crop_type],
        crop_subcategory:        entry[:crop_subcategory],
        supplier:                name,
        supplier_url:            entry[:url],
        article_number:          entry[:article_number],
        latin_name:              entry[:latin_name],
        description:             entry[:description],
        germination_temp:        entry[:germination_temp],
        spacing:                 entry[:spacing],
        days_to_maturity:        entry[:days_to_maturity],
        sowing_info:             entry[:sowing_info],
        frost_tender:            entry[:frost_tender],
        direct_sow:              entry[:direct_sow],
        scraped_at:              Time.now
      )
    end
    puts "  #{entries.length} varieties saved."
  end

  # Shared HTTP fetch helper with retries and polite delays
  def self.fetch_page(url, retries: 2)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                open_timeout: 10, read_timeout: 15) do |http|
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = "GardenOS Seed Catalog Scraper/1.0"
      http.request(req)
    end

    return Nokogiri::HTML(response.body) if response.code == "200"

    if retries > 0
      sleep 2
      return fetch_page(url, retries: retries - 1)
    end

    warn "  Failed to fetch #{url}: HTTP #{response.code}"
    nil
  rescue => e
    warn "  Error fetching #{url}: #{e.message}"
    nil
  end
end
```

- [ ] **Step 2: Create Reinsaat scraper**

```ruby
# services/catalog_scrapers/reinsaat.rb
module CatalogScrapers
  class Reinsaat
    BASE = "https://www.reinsaat.at/shop/EN"

    # Categories to scrape with their crop_type mapping
    CATEGORIES = {
      "beans"           => "bean",
      "peas"            => "pea",
      "cucumbers"       => "cucumber",
      "brassica"        => "brassica",
      "pumpkins_squash" => "squash",
      "swiss_chard"     => "herb",
      "aubergine"       => "other",
      "melons"          => "other",
      "carrots"         => "root",
      "sweet_pepper"    => "pepper",
      "chilli_peppers"  => "pepper",
      "radish"          => "radish",
      "beetroot"        => "root",
      "lettuce"         => "lettuce",
      "celery"          => "herb",
      "spinach"         => "other",
      "tomatoes"        => "tomato",
      "zucchini"        => "squash",
      "onion_garlic"    => "onion",
      "florence_fennel" => "herb",
      "leeks"           => "onion",
      "parsley"         => "herb",
      "parsnips"        => "root",
      "corn"            => "other",
    }.freeze

    def self.scrape
      entries = []

      CATEGORIES.each do |category_slug, crop_type|
        sleep 1 # Be polite
        doc = CatalogScraper.fetch_page("#{BASE}/#{category_slug}/")
        next unless doc

        # Extract product links from category page
        doc.css("a[href*='/shop/EN/#{category_slug}/']").each do |link|
          href = link["href"]
          next if href.nil? || href == "/shop/EN/#{category_slug}/"
          next if href.include?("?") # skip filter/sort links

          name = link.text.strip
          next if name.empty? || name.length > 100

          url = href.start_with?("http") ? href : "https://www.reinsaat.at#{href}"

          entries << {
            variety_name:    name,
            crop_type:       crop_type,
            crop_subcategory: nil,  # Could be enriched by scraping detail pages
            url:             url,
            article_number:  nil,
            latin_name:      nil,
            description:     nil,
            germination_temp: nil,
            spacing:         nil,
            days_to_maturity: nil,
            sowing_info:     nil,
            frost_tender:    nil,
            direct_sow:      nil,
          }
        end

        puts "  #{category_slug}: found #{entries.length} total so far"
      end

      # Deduplicate by URL
      entries.uniq { |e| e[:url] }
    end
  end
end
```

Note: This scrapes category pages only (variety names + crop types). Product detail pages could be scraped for descriptions/germination info but that's 1000+ requests — save for a follow-up enhancement.

- [ ] **Step 3: Write test**

```ruby
# test/services/test_catalog_scraper.rb
require_relative "../test_helper"
require_relative "../../services/catalog_scraper"

class TestCatalogScraper < GardenTest
  def test_fetch_page_returns_nokogiri_doc
    # Skip if no network (CI)
    skip "Network required" unless system("ping -c 1 -t 2 reinsaat.at > /dev/null 2>&1")
    doc = CatalogScraper.fetch_page("https://www.reinsaat.at/shop/EN/tomatoes/")
    refute_nil doc
    assert_kind_of Nokogiri::HTML::Document, doc
  end
end
```

- [ ] **Step 4: Run test**

Run: `rm -f db/garden_os_test.db && ruby test/services/test_catalog_scraper.rb`

- [ ] **Step 5: Test the actual scrape**

Run: `rake catalog:scrape_one[reinsaat]`
Expected: Prints category counts, saves varieties to DB.

Run: `rake catalog:stats`
Expected: Shows count of scraped varieties.

- [ ] **Step 6: Commit**

```bash
git add services/catalog_scraper.rb services/catalog_scrapers/reinsaat.rb test/services/test_catalog_scraper.rb
git commit -m "feat: catalog scraper core + Reinsaat scraper"
```

---

### Task 4: Remaining Supplier Scrapers

**Files:**
- Create: `services/catalog_scrapers/bingenheimer.rb`
- Create: `services/catalog_scrapers/sativa.rb`
- Create: `services/catalog_scrapers/magic_garden.rb`
- Create: `services/catalog_scrapers/loukykvet.rb`

Each scraper follows the same pattern as Reinsaat: fetch category pages, extract variety names + crop types + URLs. The details vary per site's HTML structure.

- [ ] **Step 1: Create Bingenheimer scraper**

Scrape `https://www.bingenheimersaatgut.de/en/organic-seeds/vegetables/` and its subcategory pages. Extract variety names from product listing cards.

- [ ] **Step 2: Create Sativa scraper**

Scrape `https://www.sativa.bio/en/vegetables/[subcategory]` pages. Extract variety names from product cards.

- [ ] **Step 3: Create Magic Garden scraper**

Scrape `https://www.magicgardenseeds.com/Vegetable-Seeds` with pagination (`_s1`, `_s2`, etc.). Extract variety names.

- [ ] **Step 4: Create Loukykvět scraper**

Scrape `https://www.loukykvet.cz/obchod/semena` and its subcategories. Note: Czech language — variety names may need to map to international names. Crop types may need translation.

- [ ] **Step 5: Test full scrape**

Run: `rake catalog:scrape`
Run: `rake catalog:stats`
Expected: 1000+ varieties across 5 suppliers.

- [ ] **Step 6: Commit**

```bash
git add services/catalog_scrapers/
git commit -m "feat: scrapers for Bingenheimer, Sativa, Magic Garden, Loukykvět"
```

---

### Task 5: Rewire Lookup to Use Catalog First

**Files:**
- Modify: `services/variety_lookup_service.rb`
- Modify: `routes/seeds.rb`
- Modify: `views/seeds/show.erb`

- [ ] **Step 1: Update VarietyLookupService**

Add a `catalog_search` method that queries the local DB first:

```ruby
  def self.catalog_search(variety_name, source: nil)
    require_relative "../models/seed_catalog_entry"

    results = SeedCatalogEntry.search(variety_name)

    # If source is specified, prefer matches from that supplier
    if source && !source.empty?
      supplier_key = normalize_supplier(source)
      supplier_matches = results.select { |r| r.supplier == supplier_key }
      results = supplier_matches unless supplier_matches.empty?
    end

    return nil if results.empty?

    # Return the best match
    best = results.first
    {
      crop_type: best.crop_type,
      notes: best.notes_summary,
      source: "catalog",
      supplier: best.supplier,
      supplier_url: best.supplier_url,
      matches: results.map { |r| { name: r.variety_name, supplier: r.supplier, crop_type: r.crop_type } }
    }
  end

  def self.normalize_supplier(source)
    s = source.to_s.downcase
    return "reinsaat"     if s.include?("reinsaat")
    return "bingenheimer" if s.include?("bingen")
    return "sativa"       if s.include?("sativa")
    return "magic_garden" if s.include?("magic")
    return "loukykvet"    if s.include?("louky") || s.include?("loukykv")
    nil
  end
```

Update `lookup` to try catalog first:

```ruby
  def self.lookup(variety_name, source: nil)
    # 1. Try local catalog first (instant, accurate)
    catalog_result = catalog_search(variety_name, source: source)
    return catalog_result if catalog_result

    # 2. Fall back to AI (slow, less reliable)
    ai_lookup(variety_name, source: source)
  end
```

- [ ] **Step 2: Update the API response in routes/seeds.rb**

The response now includes a `source` field ("catalog" or "ai") so the UI can show which method was used.

- [ ] **Step 3: Update the form UI**

Show "Found in [supplier] catalog" when source is "catalog", or "AI suggestion — verify before saving" when source is "ai". Show multiple matches if available.

- [ ] **Step 4: Run full test suite**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`

- [ ] **Step 5: Commit**

```bash
git add services/variety_lookup_service.rb routes/seeds.rb views/seeds/show.erb
git commit -m "feat: lookup uses scraped catalog first, AI as fallback"
```

---

## Summary

| Task | What | Complexity |
|------|------|-----------|
| 1 | Migration + model + search | Small |
| 2 | Nokogiri + Rake tasks | Small |
| 3 | Core scraper + Reinsaat | Medium |
| 4 | 4 more supplier scrapers | Medium (repetitive) |
| 5 | Rewire lookup: catalog first, AI fallback | Small |

**After completion:**
1. Run `rake catalog:scrape` once to populate the database (~1000+ varieties)
2. Go to Seeds → "+ Add" → type "Raf" → instant match: "Raf — tomato (Reinsaat)"
3. If no match: falls back to AI lookup (existing behavior)
4. Re-scrape periodically with `rake catalog:scrape` to catch new varieties

**Future enhancements (not in this plan):**
- Scrape product detail pages for germination temp, spacing, sowing instructions
- Auto-scrape on a cron schedule
- Import product images as reference photos
