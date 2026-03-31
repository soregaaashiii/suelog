# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/config/sitemap.rb
# frozen_string_literal: true

SitemapGenerator::Sitemap.default_host = "https://suelog.jp"
SitemapGenerator::Sitemap.public_path = "public/"
SitemapGenerator::Sitemap.compress = false

SitemapGenerator::Sitemap.create do
# ===== 固定ページ =====
add root_path, changefreq: "daily", priority: 1.0
add map_path, changefreq: "weekly", priority: 0.7
add new_shop_path, changefreq: "monthly", priority: 0.5
add terms_path, changefreq: "yearly", priority: 0.2
add privacy_path, changefreq: "yearly", priority: 0.2
add new_contact_message_path, changefreq: "monthly", priority: 0.3 if defined?(new_contact_message_path)

# ===== 梅田 =====
add umeda_path, changefreq: "daily", priority: 0.9
add umeda_smoking_path("all_smoking"), changefreq: "daily", priority: 0.8
add umeda_smoking_path("separated"), changefreq: "daily", priority: 0.8
add umeda_genre_path("izakaya"), changefreq: "daily", priority: 0.8
add umeda_genre_path("bar"), changefreq: "weekly", priority: 0.7
add umeda_genre_path("cafe"), changefreq: "weekly", priority: 0.7
add umeda_genre_path("yakiniku"), changefreq: "weekly", priority: 0.7

# ===== 難波 =====
add namba_path, changefreq: "daily", priority: 0.9
add namba_smoking_path("all_smoking"), changefreq: "daily", priority: 0.8
add namba_smoking_path("separated"), changefreq: "daily", priority: 0.8
add namba_genre_path("izakaya"), changefreq: "daily", priority: 0.8
add namba_genre_path("bar"), changefreq: "weekly", priority: 0.7
add namba_genre_path("cafe"), changefreq: "weekly", priority: 0.7
add namba_genre_path("yakiniku"), changefreq: "weekly", priority: 0.7

# ===== 店舗 =====
Shop.where(approved: true).find_each do |shop|
add shop_path(shop),
lastmod: shop.updated_at,
changefreq: "weekly",
priority: 0.8
end
end