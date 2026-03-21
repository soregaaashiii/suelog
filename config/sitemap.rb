# frozen_string_literal: true

SitemapGenerator::Sitemap.default_host = "https://suelog.onrender.com"
SitemapGenerator::Sitemap.public_path = "public/"
SitemapGenerator::Sitemap.compress = false

SitemapGenerator::Sitemap.create do
add "/", changefreq: "daily", priority: 1.0
add "/map", changefreq: "weekly", priority: 0.7
add "/shops/new", changefreq: "monthly", priority: 0.5
add "/terms", changefreq: "yearly", priority: 0.2
add "/privacy", changefreq: "yearly", priority: 0.2

add "/umeda", changefreq: "daily", priority: 0.9
add "/umeda/all_smoking", changefreq: "daily", priority: 0.8
add "/umeda/separated", changefreq: "daily", priority: 0.8
add "/umeda/genre/izakaya", changefreq: "daily", priority: 0.8
add "/umeda/genre/bar", changefreq: "weekly", priority: 0.7
add "/umeda/genre/cafe", changefreq: "weekly", priority: 0.7
add "/umeda/genre/yakiniku", changefreq: "weekly", priority: 0.7

add "/namba", changefreq: "daily", priority: 0.9
add "/namba/all_smoking", changefreq: "daily", priority: 0.8
add "/namba/separated", changefreq: "daily", priority: 0.8
add "/namba/genre/izakaya", changefreq: "daily", priority: 0.8
add "/namba/genre/bar", changefreq: "weekly", priority: 0.7
add "/namba/genre/cafe", changefreq: "weekly", priority: 0.7
add "/namba/genre/yakiniku", changefreq: "weekly", priority: 0.7

Shop.where(approved: true).find_each do |shop|
add "/shops/#{shop.id}", lastmod: shop.updated_at, changefreq: "weekly", priority: 0.8
end
end