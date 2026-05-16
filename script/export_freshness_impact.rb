# frozen_string_literal: true

require "csv"
require "fileutils"

output_dir = Rails.root.join("tmp/insights")
FileUtils.mkdir_p(output_dir)

summary_path = output_dir.join("freshness_impact_summary.csv")
detail_path = output_dir.join("freshness_impact_detail.csv")

def freshness_bucket(score)
  case score.to_i
  when 80..100
    "high"
  when 50..79
    "middle"
  when 1..49
    "low"
  else
    "unknown"
  end
end

def featured_shop_ids_from_articles
  ids = []

  Article.find_each do |article|
    body_text =
      if article.respond_to?(:body) && article.body.present?
        article.body.to_s
      else
        ""
      end

    body_text.scan(/\[shop\s+id=["']?(\d+)["']?\]/i).each do |match|
      ids << match.first.to_i
    end
  end

  ids.uniq
rescue StandardError => e
  Rails.logger.warn("[featured_shop_ids_from_articles] #{e.class}: #{e.message}")
  []
end

shops = Shop.approved.to_a
shop_ids = shops.map(&:id)
featured_shop_ids = featured_shop_ids_from_articles

click_counts =
  ShopClick
    .where(shop_id: shop_ids)
    .group(:shop_id, :kind)
    .count

recent_click_counts =
  ShopClick
    .where(shop_id: shop_ids)
    .where("created_at >= ?", 30.days.ago)
    .group(:shop_id, :kind)
    .count

rows = shops.map do |shop|
  featured_in_article = featured_shop_ids.include?(shop.id)

  phone_clicks = click_counts[[shop.id, "phone_click"]].to_i
  map_clicks = click_counts[[shop.id, "map_click"]].to_i
  affiliate_clicks = click_counts[[shop.id, "affiliate_click"]].to_i

  recent_phone_clicks = recent_click_counts[[shop.id, "phone_click"]].to_i
  recent_map_clicks = recent_click_counts[[shop.id, "map_click"]].to_i
  recent_affiliate_clicks = recent_click_counts[[shop.id, "affiliate_click"]].to_i

  total_clicks = phone_clicks + map_clicks + affiliate_clicks
  recent_total_clicks = recent_phone_clicks + recent_map_clicks + recent_affiliate_clicks

  {
    id: shop.id,
    featured_in_article: featured_in_article,
    name: shop.name,
    area: shop.area,
    genre: shop.display_genre,
    freshness_score: shop.freshness_score,
    freshness_label: shop.freshness_label,
    freshness_bucket: freshness_bucket(shop.freshness_score),
    last_confirmed_on: shop.last_confirmed_on,
    smoking_unverified: shop.smoking_unverified,
    total_clicks: total_clicks,
    phone_clicks: phone_clicks,
    map_clicks: map_clicks,
    affiliate_clicks: affiliate_clicks,
    recent_total_clicks: recent_total_clicks,
    recent_phone_clicks: recent_phone_clicks,
    recent_map_clicks: recent_map_clicks,
    recent_affiliate_clicks: recent_affiliate_clicks,
    updated_at: shop.updated_at
  }
end

CSV.open(detail_path, "w") do |csv|
  csv << rows.first.keys if rows.any?
  rows.each { |row| csv << row.values }
end

summary_rows =
  rows
    .group_by { |row| [row[:freshness_bucket], row[:featured_in_article]] }
    .map do |(bucket, featured), bucket_rows|
      shop_count = bucket_rows.size
      total_clicks = bucket_rows.sum { |row| row[:total_clicks].to_i }
      recent_total_clicks = bucket_rows.sum { |row| row[:recent_total_clicks].to_i }
      affiliate_clicks = bucket_rows.sum { |row| row[:affiliate_clicks].to_i }
      recent_affiliate_clicks = bucket_rows.sum { |row| row[:recent_affiliate_clicks].to_i }

      {
        freshness_bucket: bucket,
        featured_in_article: featured,
        shop_count: shop_count,
        avg_freshness_score: (bucket_rows.sum { |row| row[:freshness_score].to_i }.to_f / shop_count).round(1),
        total_clicks: total_clicks,
        clicks_per_shop: (total_clicks.to_f / shop_count).round(2),
        recent_total_clicks: recent_total_clicks,
        recent_clicks_per_shop: (recent_total_clicks.to_f / shop_count).round(2),
        affiliate_clicks: affiliate_clicks,
        affiliate_clicks_per_shop: (affiliate_clicks.to_f / shop_count).round(2),
        recent_affiliate_clicks: recent_affiliate_clicks,
        recent_affiliate_clicks_per_shop: (recent_affiliate_clicks.to_f / shop_count).round(2)
      }
    end
    .sort_by do |row|
      [
        { "high" => 0, "middle" => 1, "low" => 2, "unknown" => 3 }[row[:freshness_bucket]] || 9,
        row[:featured_in_article] ? 0 : 1
      ]
    end

CSV.open(summary_path, "w") do |csv|
  csv << summary_rows.first.keys if summary_rows.any?
  summary_rows.each { |row| csv << row.values }
end

puts "created: #{summary_path}"
puts "created: #{detail_path}"

puts
puts "=== Freshness impact summary ==="
summary_rows.each do |row|
  puts "#{row[:freshness_bucket]} / featured=#{row[:featured_in_article]} / shops=#{row[:shop_count]} / clicks_per_shop=#{row[:clicks_per_shop]} / recent_clicks_per_shop=#{row[:recent_clicks_per_shop]} / affiliate_per_shop=#{row[:affiliate_clicks_per_shop]}"
end