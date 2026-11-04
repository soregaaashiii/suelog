class BackfillShortGurunaviUrlKeys < ActiveRecord::Migration[8.1]
  def up
    model = Class.new(ActiveRecord::Base) { self.table_name = "shops" }
    provider = RestaurantUrlSearch::Provider.new("gurunavi")
    model.where(gurunavi_csv_url_key: nil).where.not(gurunavi_url: [ nil, "" ]).select(:id, :gurunavi_url).find_each do |shop|
      key = provider.canonical_url(shop.gurunavi_url)
      model.where(id: shop.id).update_all(gurunavi_csv_url_key: key) if key
    end
  end

  def down
    # Derived keys remain valid; no restaurant URL or affiliate value is changed.
  end
end
