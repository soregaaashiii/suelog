# /Users/kawamuratakuya/dev/suelog/app/helpers/articles_helper.rb
module ArticlesHelper
  SHOP_SHORTCODE_REGEX = /\[shop\s+id=(\d+)\]/i.freeze
  SIDEBAR_SHORTCODE_REGEX = /\[sidebar\]/i.freeze
  AD_LINK_SHORTCODE_REGEX = /\[ad\s+image=([^\]\s]+)\s+url=([^\s\]]+)\]/i.freeze
  AD_KEY_SHORTCODE_REGEX = /\[ad\s+key=([a-zA-Z0-9_-]+)\]/i.freeze
  IMAGE_MARKER_REGEX = /\A\[image.*\]\z/i.freeze
  IMAGE_ROW_START_REGEX = /\A\[image-row-start\]\z/i.freeze
  IMAGE_ROW_END_REGEX = /\A\[image-row-end\]\z/i.freeze

  def render_article_body(body)
    return "".html_safe if body.blank?

    raw_body = body.to_s
    @sidebar_enabled = raw_body.match?(SIDEBAR_SHORTCODE_REGEX)

    processed_body = raw_body
    processed_body = replace_shop_shortcodes(processed_body)
    processed_body = replace_ad_key_shortcodes(processed_body)
    processed_body = replace_ad_link_shortcodes(processed_body)
    processed_body = replace_sidebar_shortcodes(processed_body)

    html =
      begin
        if defined?(ActionText::Content)
          ActionText::Content.new(processed_body).to_rendered_html_with_layout
        else
          processed_body
        end
      rescue StandardError
        processed_body
      end

    fragment = Nokogiri::HTML::DocumentFragment.parse(html)

    style_article_figures!(fragment)
    remove_image_marker_nodes!(fragment)

    fragment.to_html.html_safe
  end

  private

  def replace_shop_shortcodes(text)
    text.to_s.gsub(SHOP_SHORTCODE_REGEX) do
      shop_id = Regexp.last_match(1).to_i
      render_shop_card_shortcode(shop_id)
    end
  end

  def replace_sidebar_shortcodes(text)
    text.to_s.gsub(SIDEBAR_SHORTCODE_REGEX, "")
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
        ActionController::Base.helpers.asset_path(image_path)
      end

    %(<div style="margin:20px 0; text-align:center;">
        <a href="#{url}" target="_blank" rel="nofollow sponsored noopener" style="display:inline-block; max-width:100%;">
             <img src="#{ERB::Util.html_escape(img_src)}" alt="広告" style="max-width:100%; height:auto; display:block; margin:0 auto;">
        </a>
      </div>)
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