# /Users/kawamuratakuya/dev/suelog/app/helpers/articles_helper.rb
module ArticlesHelper
  SHOP_SHORTCODE_REGEX = /\[shop\s+id=(\d+)\]/i.freeze
  IMAGE_MARKER_REGEX = /\A\[image.*\]\z/i.freeze
  IMAGE_ROW_START_REGEX = /\A\[image-row-start\]\z/i.freeze
  IMAGE_ROW_END_REGEX = /\A\[image-row-end\]\z/i.freeze

  def render_article_body(body)
    return "".html_safe if body.blank?

    raw_body = body.to_s

    html =
      begin
        if defined?(ActionText::Content)
          ActionText::Content.new(raw_body).to_rendered_html_with_layout
        else
          raw_body
        end
      rescue StandardError
        raw_body
      end

    html = replace_shop_shortcodes(html)
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