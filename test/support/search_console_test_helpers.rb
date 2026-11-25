require "tempfile"

module SearchConsoleTestHelpers
  def gsc_attributes(comparison: false)
    attributes = { period_start: (Date.current - 28).iso8601, period_end: (Date.current - 1).iso8601,
      search_context: "ウェブ、国・デバイス指定なし、ページ別" }
    attributes.merge!(previous_start: (Date.current - 56).iso8601, previous_end: (Date.current - 29).iso8601) if comparison
    attributes
  end

  def gsc_upload(content, filename: "Pages.csv")
    file = Tempfile.new(["search-console", ".csv"])
    file.binmode
    file.write(content)
    file.rewind
    (@gsc_tempfiles ||= []) << file
    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", true, original_filename: filename)
    @gsc_tempfiles << upload.tempfile
    upload
  end

  def gsc_csv(*rows, japanese: false)
    require "csv"
    CSV.generate do |csv|
      csv << (japanese ? ["上位のページ", "クリック数", "表示回数", "CTR", "掲載順位"] : ["Top pages", "Clicks", "Impressions", "CTR", "Position"])
      rows.each { |row| csv << row }
    end
  end

  def seed_gsc_catalog
    Shop.update_all(approved: false, on_hold: false)
    Rails.cache.clear
    now = Time.current
    Shop.insert_all!(Array.new(20) do |i|
      { name: "実績テスト#{i}", address: "大阪府吹田市江坂町1-1", nearest_station: "江坂駅から100m",
        genre: i < 12 ? "居酒屋" : "カフェ", approved: true, on_hold: false, smoking_unverified: false,
        smoking_area: i < 15 ? 1 : 0, smoking_type: 0, last_confirmed_on: Date.current, created_at: now, updated_at: now }
    end)
  end

  def close_gsc_files
    (@gsc_tempfiles || []).each(&:close!)
  end
end
