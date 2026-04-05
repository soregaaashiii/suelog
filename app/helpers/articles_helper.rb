# /Users/kawamuratakuya/dev/suelog/app/helpers/articles_helper.rb
module ArticlesHelper
def render_article_body(body)
return "".html_safe if body.blank?

content = body.to_s

rendered = content.gsub(/\[shop\s+id\s*=\s*(\d+)\]/) do
shop = Shop.find_by(id: Regexp.last_match(1))

if shop
render(partial: "articles/shop_card", locals: { shop: shop })
else
%(<div style="margin:16px 0; padding:12px; border:1px solid #f1c7c7; border-radius:10px; color:#a33;">店舗が見つかりません</div>)
end
end

rendered.html_safe
end
end