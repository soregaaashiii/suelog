# frozen_string_literal: true

# Index stored editorial references, never auto-generated footer recommendations.
class ArticlePageLinks
  def initialize(directory = GeographicDirectory.new)
    @directory = directory
    @facets = GeographicFacets.new(directory)
  end

  def for_shop(shop, limit: 3)
    ids = references.filter_map { |id, refs| id if refs[:shops].include?(shop.id) }
    articles(ids, limit: limit)
  end

  def for_page(entry, facet: nil, limit: 3)
    data = facet ? @facets.stats(entry, facet) : @directory.stats(entry)
    path = facet ? @facets.path(entry, facet) : @directory.path(entry)
    active_ids = Shop.approved.where(id: data.fetch("ids")).pluck(:id)
    ids = references.filter_map do |id, refs|
      page_match = refs[:pages].any? { |target| target == path || (!facet && target.start_with?("#{path}/")) }
      id if page_match || (refs[:shops] & active_ids).any?
    end
    articles(ids, limit: limit)
  end

  def for_article(article, limit: 6)
    refs = extract(article.body.to_s)
    # Current approval state is rechecked independently of the directory cache.
    shop_ids = Shop.approved.where(id: refs[:shops]).pluck(:id)
    entries = %w[region station].flat_map { |kind| @directory.published(kind) }
    links = entries.filter_map do |entry|
      matches = (@directory.stats(entry).fetch("ids") & shop_ids).size
      path = @directory.path(entry)
      next unless matches.positive?
      next if refs[:pages].include?(path)
      { path: path, label: "#{entry.fetch('label')}の店舗一覧", matches: matches }
    end
    links.uniq { |link| link[:path] }.sort_by { |link| [-link[:matches], link[:path]] }.first(limit)
  end

  private

  def articles(ids, limit:)
    Article.published.where(id: ids).reorder(published_at: :desc, created_at: :desc, id: :desc).limit(limit).to_a
  end

  def references
    @references ||= begin
      bodies = ActionText::RichText.where(record_type: "Article", name: "body")
      version = [Article.count, Article.maximum(:updated_at)&.utc&.iso8601(6), bodies.maximum(:updated_at)&.utc&.iso8601(6)]
      Rails.cache.fetch(["article-page-links/v1", *version], expires_in: 5.minutes) do
        Article.published.left_joins(:rich_text_body).pluck("articles.id", "action_text_rich_texts.body").to_h do |id, body|
          [id, extract(body)]
        end
      end
    end
  end

  def extract(body)
    fragment = Nokogiri::HTML.fragment(body.to_s)
    fragment.css("action-text-attachment[content]").each { |node| node.replace(Nokogiri::HTML.fragment(node["content"].to_s)) }
    fragment.css("script, style").remove
    shops = fragment.text.scan(/\[shop\s+id=(\d+)\]/i).flatten.map(&:to_i)
    pages = []
    fragment.css("a[href]").each do |link|
      path = local_path(link["href"])
      next unless path
      if (match = path.match(%r{\A/shops/(\d+)\z}))
        shops << match[1].to_i
      elsif path.match?(%r{\A/(areas|stations)/[a-z0-9-]+(?:/(genre|smoking)/[a-z0-9-]+)?\z})
        pages << path
      end
    end
    { shops: shops.uniq, pages: pages.uniq }
  end

  def local_path(value)
    uri = URI.parse(value.to_s.strip)
    return if uri.userinfo || (uri.host && (uri.host != "suelog.jp" || uri.scheme != "https" || uri.port != 443))
    return if uri.scheme && !uri.host
    uri.path if uri.path&.start_with?("/") && !value.to_s.strip.start_with?("//")
  rescue URI::InvalidURIError
    nil
  end
end
