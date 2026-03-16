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
