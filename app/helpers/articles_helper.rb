# /Users/kawamuratakuya/dev/suelog/app/helpers/articles_helper.rb
module ArticlesHelper
def render_article_body(body)
return "".html_safe if body.blank?

raw_content = body.to_s

# ActionText/Trix の添付画像を正しく表示できるように、
# 使える場合は ActionText の描画を通す
rendered_content =
begin
if defined?(ActionText::Content)
ActionText::Content.new(raw_content).to_rendered_html_with_layout
else
raw_content
end
rescue StandardError
raw_content
end

content_with_shop_cards = rendered_content.gsub(/\[shop\s+id\s*=\s*(\d+)\]/) do
shop = Shop.find_by(id: Regexp.last_match(1))

if shop
render(partial: "articles/shop_card", locals: { shop: shop })
else
%(<div style="margin:16px 0; padding:12px; border:1px solid #f1c7c7; border-radius:10px; color:#a33;">店舗が見つかりません</div>)
end
end

content_with_shop_cards.html_safe
end
end