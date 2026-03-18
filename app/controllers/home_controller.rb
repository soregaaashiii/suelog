# frozen_string_literal: true

class HomeController < ApplicationController
UMEDA_GENRE_MAP = {
"izakaya" => "居酒屋",
"bar" => "バー / パブ",
"cafe" => "喫茶店 / カフェ",
"yakiniku" => "焼肉"
}.freeze

def index
track_page_view
create_page_view_safely

@search_form_url = root_path
@page_title = "吸えログ in大阪｜喫煙できる飲食店を探せる"
@page_description = "大阪で喫煙できる飲食店を探せる吸えログ。席で喫煙可・喫煙所あり・加熱式のみなどの情報を掲載しています。"
@page_heading = "掲載店舗"
@page_subtitle = "大阪の喫煙可能店舗を一覧で確認できます"
@area_intro_title = nil
@area_intro_text = nil
@canonical_url = root_url
@is_area_page = false
@area_nav_links = []

build_listing!
render :index
end

def umeda
track_page_view
create_page_view_safely

@forced_area_keyword = "梅田"
@forced_genre = nil
@is_area_page = true
@search_form_url = umeda_path
@area_nav_links = umeda_nav_links

smoking_area = normalized_smoking_area_param

case smoking_area
when "all_smoking"
@page_title = "梅田で席で喫煙可の店一覧｜吸えログ in大阪"
@page_description = "梅田で席で喫煙可の飲食店を掲載。紙・加熱式の喫煙タイプや最寄駅、営業時間を確認できます。"
@page_heading = "梅田で席で喫煙可の店"
@page_subtitle = "梅田エリアで席で喫煙できる店舗を一覧で確認できます"
@area_intro_title = "梅田で席で喫煙可の店を探す"
@area_intro_text = "梅田エリアで席で喫煙できる飲食店をまとめています。仕事帰りや飲み会で、すぐ吸える店を探したい人向けの一覧です。"
@canonical_url = umeda_smoking_url("all_smoking")
when "separated"
@page_title = "梅田で喫煙所ありの店一覧｜吸えログ in大阪"
@page_description = "梅田で喫煙所ありの飲食店を掲載。喫煙エリアや喫煙タイプ、最寄駅、営業時間を確認できます。"
@page_heading = "梅田で喫煙所ありの店"
@page_subtitle = "梅田エリアで喫煙所ありの店舗を一覧で確認できます"
@area_intro_title = "梅田で喫煙所ありの店を探す"
@area_intro_text = "梅田エリアで喫煙所ありの飲食店をまとめています。完全禁煙では困るけど、分かりやすく吸える場所がある店を探したい人向けです。"
@canonical_url = umeda_smoking_url("separated")
else
@page_title = "梅田で喫煙できる店一覧｜吸えログ in大阪"
@page_description = "梅田で喫煙できる飲食店を掲載。席で喫煙可・喫煙所あり・加熱式のみなど、梅田の喫煙可能店を探せます。"
@page_heading = "梅田で喫煙できる店"
@page_subtitle = "梅田エリアの喫煙可能店舗を一覧で確認できます"
@area_intro_title = "梅田で喫煙できる店を探す"
@area_intro_text = "梅田エリアで喫煙できる飲食店をまとめています。席で喫煙可の店、喫煙所ありの店、加熱式のみ対応の店などを探せます。"
@canonical_url = umeda_url
end

build_listing!
render :index
end

def umeda_genre
track_page_view
create_page_view_safely

genre_label = UMEDA_GENRE_MAP[params[:genre_slug].to_s]
raise ActionController::RoutingError, "Not Found" if genre_label.blank?

@forced_area_keyword = "梅田"
@forced_genre = genre_label
@is_area_page = true
@search_form_url = umeda_genre_path(params[:genre_slug])
@area_nav_links = umeda_nav_links

@page_title = "梅田で喫煙できる#{genre_label}一覧｜吸えログ in大阪"
@page_description = "梅田で喫煙できる#{genre_label}を掲載。喫煙エリア、喫煙タイプ、最寄駅、営業時間を確認できます。"
@page_heading = "梅田で喫煙できる#{genre_label}"
@page_subtitle = "梅田エリアの喫煙可能な#{genre_label}を一覧で確認できます"
@area_intro_title = "梅田で喫煙できる#{genre_label}を探す"
@area_intro_text = "梅田エリアで喫煙できる#{genre_label}をまとめています。飲み会、仕事帰り、1人飲みなどで使いやすい店探しの入口ページです。"
@canonical_url = umeda_genre_url(params[:genre_slug])

build_listing!
render :index
end

private

def create_page_view_safely
PageView.create!(path: request.path)
rescue => e
Rails.logger.warn "PageView error: #{e.message}"
end

def build_listing!
@per = params[:per].to_i
@per = 30 unless [30, 50, 100].include?(@per)

genre_q = effective_genre_param
station_q = params[:station].to_s.strip
smoking_area = normalized_smoking_area_param
smoking_type = params[:smoking_type].to_s.strip
keyword_q = params[:q].to_s.strip

base = Shop
.approved
.left_joins(:reviews)
.select(
"shops.*",
"COALESCE(AVG(CASE WHEN reviews.approved THEN reviews.rating END), 0) AS avg_rating",
"COALESCE(SUM(CASE WHEN reviews.approved THEN 1 ELSE 0 END), 0) AS reviews_count",
"MAX(CASE WHEN reviews.approved THEN reviews.created_at END) AS latest_review_at"
)
.group("shops.id")

count_scope = Shop.approved

if @forced_area_keyword.present?
like = "%#{@forced_area_keyword}%"
area_sql = <<~SQL.squish
shops.area LIKE :like
OR shops.address LIKE :like
OR shops.nearest_station LIKE :like
SQL

base = base.where(area_sql, like: like)
count_scope = count_scope.where(area_sql, like: like)
end

if genre_q.present?
base = base.merge(Shop.genre_like(genre_q))
count_scope = count_scope.merge(Shop.genre_like(genre_q))
end

if station_q.present?
base = base.merge(Shop.text_like("nearest_station", station_q))
count_scope = count_scope.merge(Shop.text_like("nearest_station", station_q))
end

if smoking_area.present?
base = base.where("shops.smoking_area = ?", smoking_area)
count_scope = count_scope.where(smoking_area: smoking_area)
end

if smoking_type.present?
base = base.where("shops.smoking_type = ?", smoking_type)
count_scope = count_scope.where(smoking_type: smoking_type)
end

if keyword_q.present?
base = base.merge(Shop.keyword(keyword_q))
count_scope = count_scope.merge(Shop.keyword(keyword_q))
end

if params[:needs_review].present?
cutoff = 2.years.ago.to_date
base = base.where("shops.last_confirmed_on IS NULL OR shops.last_confirmed_on < ?", cutoff)
count_scope = count_scope.where("last_confirmed_on IS NULL OR last_confirmed_on < ?", cutoff)
end

sorted =
case params[:sort]
when "latest_review"
base.order(Arel.sql("latest_review_at IS NULL, latest_review_at DESC"))
when "rating"
base.order(Arel.sql("avg_rating DESC"))
when "reviews_count"
base.order(Arel.sql("reviews_count DESC"))
else
base.order(Arel.sql("shops.last_confirmed_on IS NULL, shops.last_confirmed_on DESC, shops.created_at DESC"))
end

@shops_count = count_scope.count
@shops = sorted.page(params[:page]).per(@per)
end

def effective_genre_param
@forced_genre.presence || params[:genre].to_s.strip
end

def normalized_smoking_area_param
value = params[:smoking_area].to_s.strip
return "all_smoking" if value == "smoking_allowed"
value
end

def umeda_nav_links
[
{ label: "梅田すべて", path: umeda_path },
{ label: "梅田で席で喫煙可", path: umeda_smoking_path("all_smoking") },
{ label: "梅田で喫煙所あり", path: umeda_smoking_path("separated") },
{ label: "梅田の居酒屋", path: umeda_genre_path("izakaya") },
{ label: "梅田のバー", path: umeda_genre_path("bar") },
{ label: "梅田のカフェ", path: umeda_genre_path("cafe") },
{ label: "梅田の焼肉", path: umeda_genre_path("yakiniku") }
]
end
end