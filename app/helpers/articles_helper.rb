# /Users/kawamuratakuya/dev/suelog/app/helpers/articles_helper.rb
module ArticlesHelper
def render_article_body(body)
return "".html_safe if body.blank?

html =
begin
if defined?(ActionText::Content)
ActionText::Content.new(body.to_s).to_rendered_html_with_layout
else
body.to_s
end
rescue StandardError
body.to_s
end

html = html.gsub(/\[shop\s+id=(\d+)\]/i) do
shop = Shop.find_by(id: Regexp.last_match(1))

if shop
render(partial: "articles/shop_card", locals: { shop: shop })
else
%(<div style="margin:16px 0; padding:12px; border:1px solid #f1c7c7; border-radius:10px; color:#a33;">店舗が見つかりません</div>)
end
end

fragment = Nokogiri::HTML::DocumentFragment.parse(html)

fragment.css("figure").each do |figure|
img = figure.at_css("img")
next unless img

figure["style"] = [figure["style"], "margin:20px 0; text-align:center;"].compact.join(" ")
img["style"] = [img["style"], "max-width:560px; width:100%; height:auto; border-radius:12px; display:inline-block;"].compact.join(" ")
end

fragment.css("p, div").each do |node|
text = node.text.to_s.strip
if text.match?(/\A\[image.*\]\z/i) || text.match?(/\A\[image-row-start\]\z/i) || text.match?(/\A\[image-row-end\]\z/i)
node.remove
end
end

fragment.to_html.html_safe
end
end