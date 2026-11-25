# Sitemaps are served from live public data by SitemapsController/PublicSitemap.
# Keep legacy `rails sitemap:refresh` from writing a stale public/sitemap.xml,
# which would take precedence over the dynamic route in the static file server.
raise "Static sitemap generation is retired. Use https://suelog.jp/sitemap.xml (automatically refreshed every 5 minutes)."
