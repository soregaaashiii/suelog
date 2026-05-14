# /Users/kawamuratakuya/dev/suelog/app/helpers/articles_helper.rb
module ArticlesHelper
  SHOP_SHORTCODE_REGEX = /\[shop\s+id=(\d+)\]/i.freeze
  SIDEBAR_SHORTCODE_REGEX = /\[sidebar\]/i.freeze
  ARTICLE_CTA_SHORTCODE_REGEX = /\[article-cta\]/i.freeze
  RELATED_ARTICLES_SHORTCODE_REGEX = /\[related-articles\s+([^\]]+)\]/i.freeze
  AD_LINK_SHORTCODE_REGEX = /\[ad\s+image=([^\]\s]+)\s+url=([^\s\]]+)\]/i.freeze
  AD_KEY_SHORTCODE_REGEX = /\[ad\s+key=([a-zA-Z0-9_-]+)\]/i.freeze
  IMAGE_MARKER_REGEX = /\A\[image.*\]\z/i.freeze
  IMAGE_ROW_START_REGEX = /\A\[image-row-start\]\z/i.freeze
  IMAGE_ROW_END_REGEX = /\A\[image-row-end\]\z/i.freeze

  def render_article_body(body, include_article_footer: true)
    return "".html_safe if body.blank?

    raw_body = body.to_s
    @sidebar_enabled = raw_body.match?(SIDEBAR_SHORTCODE_REGEX)
    article_cta_already_inserted = raw_body.match?(ARTICLE_CTA_SHORTCODE_REGEX)

    shortcode_replacements = {}

    processed_body = raw_body.gsub(SHOP_SHORTCODE_REGEX) do
      token = "__SUELOG_SHOP_SHORTCODE_#{shortcode_replacements.length}__"
      shop_id = Regexp.last_match(1).to_i
      shortcode_replacements[token] = render_shop_card_shortcode(shop_id)
      token
    end

    processed_body = processed_body.gsub(AD_KEY_SHORTCODE_REGEX) do
      token = "__SUELOG_AD_KEY_SHORTCODE_#{shortcode_replacements.length}__"
      key = Regexp.last_match(1).to_s.strip
      shortcode_replacements[token] = render_ad_key_shortcode(key)
      token
    end

    processed_body = processed_body.gsub(AD_LINK_SHORTCODE_REGEX) do
      token = "__SUELOG_AD_LINK_SHORTCODE_#{shortcode_replacements.length}__"
      image_path = Regexp.last_match(1).to_s.strip
      url = Regexp.last_match(2).to_s.strip
      shortcode_replacements[token] = render_ad_link_html(image_path: image_path, url: url)
      token
    end

    processed_body = processed_body.gsub(ARTICLE_CTA_SHORTCODE_REGEX) do
      token = "__SUELOG_ARTICLE_CTA_SHORTCODE_#{shortcode_replacements.length}__"
      shortcode_replacements[token] = render_article_cta_shortcode
      token
    end

    processed_body = processed_body.gsub(RELATED_ARTICLES_SHORTCODE_REGEX) do
      token = "__SUELOG_RELATED_ARTICLES_SHORTCODE_#{shortcode_replacements.length}__"
      shortcode_replacements[token] = render_related_articles_shortcode(Regexp.last_match(1).to_s)
      token
    end

    processed_body = replace_sidebar_shortcodes(processed_body)

    html =
      begin
        if defined?(ActionText::Content)
          rendered = ActionText::Content.new(processed_body).to_rendered_html_with_layout
          CGI.unescapeHTML(rendered)
        else
          processed_body
        end
      rescue StandardError
        processed_body
      end

    shortcode_replacements.each do |token, replacement_html|
      html = html.gsub(token, replacement_html.to_s)
    end

    fragment = Nokogiri::HTML::DocumentFragment.parse(html)

    style_article_figures!(fragment)
    remove_image_marker_nodes!(fragment)
    rewrite_article_shop_links!(fragment)

    if include_article_footer && !article_cta_already_inserted
      cta_fragment = Nokogiri::HTML::DocumentFragment.parse(render_article_cta_shortcode)
      fragment.add_child(cta_fragment)

      shops_html = render(
        partial: "shared/shop_cards",
        locals: { shops: popular_shops_for_article(limit: 3) }
      )

      shops_fragment = Nokogiri::HTML::DocumentFragment.parse(shops_html)

      fragment.add_child(Nokogiri::HTML::DocumentFragment.parse(%(
        <div style="margin:32px 0 8px;">
          <h2 style="font-size:18px; font-weight:900; margin-bottom:6px;">
            喫煙状況を確認してお店を選ぶ
          </h2>
          <p style="margin:0 0 12px; color:#666; font-size:13px; line-height:1.7;">
            気になるお店は、店舗ページで喫煙可否・営業時間・地図を確認できます。
          </p>
        </div>
      )))

      fragment.add_child(shops_fragment)
    end

    fragment.to_html.html_safe
  end

private

def rewrite_article_shop_links!(fragment)
  return if @article.blank?

  fragment.css("a[href]").each do |link|
    href = link["href"].to_s
    shop_id = href[%r{\A/shops/(\d+)(?:\z|[?#])}, 1]
    next if shop_id.blank?

    link["href"] = Rails.application.routes.url_helpers.track_shop_click_article_path(@article, shop_id: shop_id)
  end
end

def popular_shops_for_article(limit: 3)
  Shop.approved
      .left_joins(:shop_clicks)
      .select("shops.*, COUNT(shop_clicks.id) AS clicks_count")
      .group("shops.id")
      .order(Arel.sql("COUNT(shop_clicks.id) DESC, shops.last_confirmed_on DESC"))
      .limit(limit)
end

def render_related_articles_shortcode(attrs_text)
  slugs = attrs_text.to_s[/slugs=([^\s\]]+)/i, 1].to_s.split(",").map(&:strip).reject(&:blank?)
  urls = attrs_text.to_s[/urls=([^\s\]]+)/i, 1].to_s.split(",").map(&:strip).reject(&:blank?)

  url_slugs = urls.filter_map do |url|
    url.to_s.split("?").first.split("/articles/").last.presence
  end

  target_slugs = (slugs + url_slugs).uniq
  return "" if target_slugs.blank?

  articles = Article.published.where(slug: target_slugs).index_by(&:slug)
  ordered_articles = target_slugs.filter_map { |slug| articles[slug] }
  return "" if ordered_articles.blank?

  items_html = ordered_articles.map do |article|
    title = ERB::Util.html_escape(article.title.to_s)
    summary = ERB::Util.html_escape(article.summary.to_s.presence || "関連記事を見る")
    path = Rails.application.routes.url_helpers.article_path(article)

    image_html =
      if article.respond_to?(:eyecatch) && article.eyecatch.attached?
        image_path = Rails.application.routes.url_helpers.rails_blob_path(article.eyecatch, only_path: true)

        %(
          <div style="flex:0 0 92px; width:92px; height:68px; border-radius:10px; overflow:hidden; background:#f3f3f3;">
            <img src="#{ERB::Util.html_escape(image_path)}" alt="#{title}" loading="lazy" style="width:100%; height:100%; object-fit:cover; display:block;">
          </div>
        )
      else
        %(
          <div style="flex:0 0 92px; width:92px; height:68px; border-radius:10px; background:#f6edd7; display:flex; align-items:center; justify-content:center; color:#7a5a12; font-size:12px; font-weight:900;">
            関連記事
          </div>
        )
      end

    %(
      <a href="#{path}" style="display:flex; gap:12px; align-items:center; padding:12px 16px; border-top:1px solid #eee6d6; color:#111; text-decoration:none;">
        #{image_html}

        <div style="min-width:0; flex:1;">
          <div style="font-size:15px; font-weight:900; line-height:1.55;">
            #{title}
          </div>
          <div style="margin-top:3px; color:#666; font-size:12px; line-height:1.6;">
            #{summary}
          </div>
        </div>

        <div style="flex:0 0 auto; color:#c6a75e; font-size:20px; font-weight:900;">
          ›
        </div>
      </a>
    )
  end.join

   %(
    <div style="margin:0 0 -1px; padding:0; border:1px solid #e8e3d7; border-radius:0; background:#fffdf8;">
      <div style="margin:0; padding:0;">
        #{items_html}
      </div>
    </div>
  )
end

def replace_shop_shortcodes(text)
    text.to_s.gsub(SHOP_SHORTCODE_REGEX) do
      shop_id = Regexp.last_match(1).to_i
      render_shop_card_shortcode(shop_id)
    end
  end

  def replace_sidebar_shortcodes(text)
    text.to_s.gsub(SIDEBAR_SHORTCODE_REGEX, "")
  end
  def render_ad_key_shortcode(key)
    ad =
      begin
        AffiliateAd.find_by(key: key, active: true)
      rescue StandardError => e
        Rails.logger.error("[ArticlesHelper] affiliate ad lookup failed key=#{key}: #{e.class}: #{e.message}")
        nil
      end

    return "" if ad.blank?

    image_path =
      if ad.respond_to?(:image) && ad.image.attached?
        Rails.application.routes.url_helpers.rails_blob_path(ad.image, only_path: true)
      else
        ad.image_path.to_s
      end

    render_ad_link_html(image_path: image_path, url: ad.url.to_s)
  end

  def replace_ad_key_shortcodes(text)
    text.to_s.gsub(AD_KEY_SHORTCODE_REGEX) do
      key = Regexp.last_match(1).to_s.strip

      ad =
        begin
          AffiliateAd.find_by(key: key, active: true)
        rescue StandardError => e
          Rails.logger.error("[ArticlesHelper] affiliate ad lookup failed key=#{key}: #{e.class}: #{e.message}")
          nil
        end

      next "" if ad.blank?

      image_path =
        if ad.respond_to?(:image) && ad.image.attached?
          Rails.application.routes.url_helpers.rails_blob_path(ad.image, only_path: true)
        else
          ad.image_path.to_s
        end

      render_ad_link_html(image_path: image_path, url: ad.url.to_s)
    end
  end

  def replace_ad_link_shortcodes(text)
    text.to_s.gsub(AD_LINK_SHORTCODE_REGEX) do
      image_path = Regexp.last_match(1).to_s.strip
      url = Regexp.last_match(2).to_s.strip

      render_ad_link_html(image_path: image_path, url: url)
    end
  end

  def render_ad_link_html(image_path:, url:)
    return "" if image_path.blank? || url.blank?

    img_src =
      if image_path.start_with?("http://", "https://", "/rails/active_storage/")
        image_path
      else
        begin
          ActionController::Base.helpers.asset_path(image_path)
        rescue Propshaft::MissingAssetError, Sprockets::Rails::Helper::AssetNotFound, StandardError => e
          Rails.logger.warn("[ArticlesHelper] ad image asset not found image_path=#{image_path}: #{e.class}: #{e.message}")
          nil
        end
      end

    return "" if img_src.blank?

    %(<div style="margin:20px 0; text-align:center;">
        <a href="#{url}" target="_blank" rel="nofollow sponsored noopener" style="display:inline-block; max-width:100%;">
             <img src="#{ERB::Util.html_escape(img_src)}" alt="広告" style="max-width:100%; height:auto; display:block; margin:0 auto;">
        </a>
      </div>)
  end

  def render_article_cta_shortcode
    %(
      <div style="margin:24px 0; padding:14px; border:1px solid #e8e3d7; border-radius:10px; background:#fffdf8; box-shadow:0 6px 18px rgba(17,17,17,0.04);">
        <div style="font-size:20px; font-weight:900; color:#111; line-height:1.5; margin-bottom:8px;">
          今吸える店をすぐ確認する
        </div>

        <p style="margin:0 0 14px; color:#666; font-size:14px; line-height:1.8;">
          喫煙可否・営業時間・地図を見ながら、今行けるお店を探せます。
        </p>

        <div style="display:grid; gap:8px; max-width:420px; margin:0 auto;">
          <a href="/?open_now_only=1"
             style="display:flex; align-items:center; justify-content:center; min-height:38px; padding:0 12px; background:#2b2b2b; color:#fff; border:1px solid #2b2b2b; border-radius:12px; text-decoration:none; font-size:13px; font-weight:900;">
            今営業中の喫煙可を見る
          </a>

          <a href="/?smoking_area=all_smoking"
             style="display:flex; align-items:center; justify-content:center; min-height:38px; padding:0 12px; background:#fff; color:#111; border:1px solid #d8d2c3; border-radius:12px; text-decoration:none; font-size:13px; font-weight:900;">
            席で吸える店だけ見る
          </a>

          <a href="/map"
             style="display:flex; align-items:center; justify-content:center; min-height:38px; padding:0 12px; background:#fff; color:#111; border:1px solid #d8d2c3; border-radius:12px; text-decoration:none; font-size:13px; font-weight:900;">
            近くの店を地図で探す
          </a>
        </div>

        <p style="margin:12px 0 0; color:#777; font-size:12px; line-height:1.7;">
          ※営業時間や喫煙可否は変更される場合があります。来店前に店舗へご確認ください。
        </p>
      </div>
    )
  end

  def render_shop_card_shortcode(shop_id)
    shop = Shop.find_by(id: shop_id)

    return missing_shop_card_html(shop_id) if shop.blank?

    render(partial: "articles/shop_card", locals: { shop: shop })
  rescue StandardError => e
    Rails.logger.error("[ArticlesHelper] shop card render failed for shop_id=#{shop_id}: #{e.class}: #{e.message}")
    %(<div style="margin:16px 0; padding:12px; border:1px solid #f1c7c7; border-radius:10px; color:#a33;">店舗カードの表示に失敗しました（shop_id=#{shop_id}）</div>)
  end

  def missing_shop_card_html(shop_id)
    %(<div style="margin:16px 0; padding:12px; border:1px solid #f1c7c7; border-radius:10px; color:#a33;">店舗が見つかりません（shop_id=#{shop_id}）</div>)
  end

  def style_article_figures!(fragment)
    fragment.css("figure").each do |figure|
      img = figure.at_css("img")
      next unless img

      figure["style"] = [figure["style"], "margin:20px 0; text-align:center;"].compact.join(" ")
      img["style"] = [img["style"], "max-width:560px; width:100%; height:auto; border-radius:12px; display:inline-block;"].compact.join(" ")
    end
  end

  def remove_image_marker_nodes!(fragment)
    fragment.css("p, div").each do |node|
      text = node.text.to_s.strip

      if text.match?(IMAGE_MARKER_REGEX) ||
         text.match?(IMAGE_ROW_START_REGEX) ||
         text.match?(IMAGE_ROW_END_REGEX)
        node.remove
      end
    end
  end
end