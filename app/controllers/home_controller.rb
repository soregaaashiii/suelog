# /app/controllers/home_controller.rb
class HomeController < ApplicationController
def index
track_page_view

# アクセス解析（失敗しても画面は落とさない）
begin
PageView.create!(path: request.path)
rescue => e
Rails.logger.warn "PageView error: #{e.message}"
end

# ===========
# ホーム = 検索＋一覧（承認済みのみ）
# 評価は rating 一本化（avg_rating）
# ページネーション対応
# ===========

@per = params[:per].to_i
@per = 30 unless [30, 50, 100].include?(@per)

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

# --- 検索（ジャンル×喫煙×エリア/駅＋キーワード） ---
genre_q = params[:genre].to_s.strip
area_q = params[:area].to_s.strip
station_q = params[:station].to_s.strip
smoking_area = params[:smoking_area].to_s.strip
smoking_type = params[:smoking_type].to_s.strip
keyword_q = params[:q].to_s.strip

# 旧値/揺れを吸収（smoking_allowed → all_smoking）
smoking_area = "all_smoking" if smoking_area == "smoking_allowed"

if genre_q.present?
base = base.merge(Shop.genre_like(genre_q))
count_scope = count_scope.merge(Shop.genre_like(genre_q))
end

if area_q.present?
base = base.merge(Shop.text_like("area", area_q))
count_scope = count_scope.merge(Shop.text_like("area", area_q))
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

# キーワード（どの項目でもヒット）
if keyword_q.present?
like = "%#{keyword_q}%"

base = base.where(
<<~SQL.squish, like: like
shops.name LIKE :like
OR shops.address LIKE :like
OR shops.area LIKE :like
OR shops.nearest_station LIKE :like
OR shops.phone LIKE :like
OR shops.note LIKE :like
OR shops.genre LIKE :like
OR shops.genre_other LIKE :like
OR shops.opening_hours LIKE :like
SQL
)

count_scope = count_scope.where(
<<~SQL.squish, like: like
shops.name LIKE :like
OR shops.address LIKE :like
OR shops.area LIKE :like
OR shops.nearest_station LIKE :like
OR shops.phone LIKE :like
OR shops.note LIKE :like
OR shops.genre LIKE :like
OR shops.genre_other LIKE :like
OR shops.opening_hours LIKE :like
SQL
)
end

# 最終確認日が古い店だけ（任意）
if params[:needs_review].present?
cutoff = 2.years.ago.to_date
base = base.where("shops.last_confirmed_on IS NULL OR shops.last_confirmed_on < ?", cutoff)
count_scope = count_scope.where("last_confirmed_on IS NULL OR last_confirmed_on < ?", cutoff)
end

# --- 並び替え ---
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
end