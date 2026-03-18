# frozen_string_literal: true

SitemapGenerator::Sitemap.default_host = ENV.fetch("APP_HOST", "https://your-app.onrender.com")
SitemapGenerator::Sitemap.public_path = "public/"
SitemapGenerator::Sitemap.compress = true

SitemapGenerator::Sitemap.create do
add root_path, changefreq: "daily", priority: 1.0
add map_path, changefreq: "weekly", priority: 0.7
add new_shop_path, changefreq: "monthly", priority: 0.5
add terms_path, changefreq: "yearly", priority: 0.2
add privacy_path, changefreq: "yearly", priority: 0.2

Shop.where(approved: true).find_each do |shop|
add shop_path(shop), lastmod: shop.updated_at, changefreq: "weekly", priority: 0.8
end
end