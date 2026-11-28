class AddKeywordSearchTextToShops < ActiveRecord::Migration[8.1]
  def up
    add_column :shops, :keyword_search_text, :text
    add_column :shops, :keyword_station_text, :text
    add_index :shops, :id, where: "keyword_search_text IS NULL OR keyword_station_text IS NULL", name: "index_shops_missing_keyword_search"
    record = Class.new(ActiveRecord::Base) { self.table_name = "shops" }
    record.reset_column_information
    say_with_time "Prepare normalized shop keyword text" do
      record.select(:id, *ShopKeywordSearch::FIELDS).find_in_batches(batch_size: 200) do |batch|
        cases = batch.map do |shop|
          text = ShopKeywordSearch.document(ShopKeywordSearch::FIELDS.map { |field| shop[field] })
          "WHEN #{shop.id.to_i} THEN #{connection.quote(text)}"
        end
        stations = batch.map { |shop| "WHEN #{shop.id.to_i} THEN #{connection.quote(ShopKeywordSearch.normalize(shop.nearest_station))}" }
        record.where(id: batch.map(&:id)).update_all("keyword_search_text = CASE id #{cases.join(' ')} END, keyword_station_text = CASE id #{stations.join(' ')} END")
      end
    end
  end

  def down
    remove_index :shops, name: "index_shops_missing_keyword_search"
    remove_column :shops, :keyword_station_text if column_exists?(:shops, :keyword_station_text)
    remove_column :shops, :keyword_search_text
  end
end
