# frozen_string_literal: true

# IDs define stable partitions: adding a shop does not move every following URL.
class PublicSitemap
  include Rails.application.routes.url_helpers

  HOST = "https://suelog.jp"
  NAMESPACE = "http://www.sitemaps.org/schemas/sitemap/0.9"
  BUCKET_SIZE = 1_000
  CACHE_TTL = 5.minutes

  def index
    cached("index") do
      paths = ["/sitemaps/pages.xml"]
      { "shops" => Shop.public_listing, "articles" => Article.published }.each do |kind, scope|
        scope.reorder(nil).pluck(:id).map { |id| id / BUCKET_SIZE }.uniq.sort.each do |bucket|
          paths << "/sitemaps/#{kind}/#{bucket}.xml"
        end
      end
      Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.sitemapindex(xmlns: NAMESPACE) do
          paths.each { |path| xml.sitemap { xml.loc HOST + path } }
        end
      end.to_xml
    end
  end

  def pages
    cached("pages") do
      paths = [root_path, map_path, articles_path, terms_path, privacy_path]
      %w[umeda namba].each do |area|
        paths << public_send("#{area}_path")
        %w[all_smoking separated].each { |kind| paths << public_send("#{area}_smoking_path", kind) }
        %w[izakaya bar cafe yakiniku].each { |genre| paths << public_send("#{area}_genre_path", genre) }
      end
      directory = GeographicDirectory.new
      paths << geographic_directory_path
      %w[region station].each do |kind|
        paths.concat(directory.published(kind).map { |entry| directory.path(entry) })
      end
      urlset(paths.uniq.map { |path| [path, nil] })
    end
  end

  def records(kind, bucket)
    raise ArgumentError, "unsupported sitemap" unless %w[shops articles].include?(kind)

    cached("#{kind}/#{bucket}") do
      scope = kind == "shops" ? Shop.public_listing : Article.published
      range = (bucket * BUCKET_SIZE)...((bucket + 1) * BUCKET_SIZE)
      columns = kind == "shops" ? %i[id updated_at] : %i[slug updated_at]
      entries = scope.where(id: range).reorder(:id).pluck(*columns).map do |identifier, updated_at|
        path = kind == "shops" ? shop_path(identifier) : article_path(identifier)
        [path, updated_at]
      end
      entries.empty? ? nil : urlset(entries)
    end
  end

  private

  def cached(key, &block)
    Rails.cache.fetch("public-sitemap/v2/#{key}", expires_in: CACHE_TTL, skip_nil: true, &block)
  end

  def urlset(entries)
    Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.urlset(xmlns: NAMESPACE) do
        entries.each do |path, updated_at|
          xml.url do
            xml.loc HOST + path
            xml.lastmod updated_at.iso8601 if updated_at
          end
        end
      end
    end.to_xml
  end
end
