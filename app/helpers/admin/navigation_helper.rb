# app/helpers/admin/navigation_helper.rb
module Admin::NavigationHelper
# badge:
# - nil => バッジ自体を出さない
# - 数値 => 0でも表示する
def admin_nav_link(name, path, badge: nil)
active = current_page?(path)

classes = ["admin-nav__link"]
classes << "is-active" if active

badge_tag =
if badge.nil?
nil
else
b = badge.to_i
content_tag(:span, b, class: ["admin-badge", ("is-zero" if b == 0)].compact.join(" "))
end

label = safe_join([
content_tag(:span, name, class: "admin-nav__text"),
badge_tag
].compact)

link_to label, path,
class: classes.join(" "),
aria: (active ? { current: "page" } : {})
end

# -------------------------
# ✅ バッジ用カウント
# -------------------------

# 口コミ：status:0 を「承認待ち」としてカウント
def pending_reviews_count
pending_navigation_counts[:reviews]
end

# 店舗：approved:false AND rejected:false/nil
def pending_shops_count
pending_navigation_counts[:shops]
end

# 編集依頼：status:0
def pending_edit_requests_count
pending_navigation_counts[:edit_requests]
end

# 通報：ShopReport + ReviewReport を合算（どっちか無くても落ちない）
def pending_reports_count
pending_navigation_counts[:reports]
end

private

def pending_navigation_counts
@pending_navigation_counts ||= begin
return fallback_pending_navigation_counts unless pending_navigation_models_ready?

row = ActiveRecord::Base.connection.select_one(<<~SQL.squish)
SELECT
  (#{Review.where(status: 0).reselect("COUNT(*)").to_sql}) AS pending_reviews,
  (#{pending_shops_scope.reselect("COUNT(*)").to_sql}) AS pending_shops,
  (#{ShopEditRequest.where(status: 0).reselect("COUNT(*)").to_sql}) AS pending_edit_requests,
  (#{ShopReport.where(status: 0).reselect("COUNT(*)").to_sql}) +
    (#{ReviewReport.where(status: 0).reselect("COUNT(*)").to_sql}) AS pending_reports
SQL

{
reviews: row["pending_reviews"].to_i,
shops: row["pending_shops"].to_i,
edit_requests: row["pending_edit_requests"].to_i,
reports: row["pending_reports"].to_i
}
rescue StandardError
fallback_pending_navigation_counts
end
end

def pending_navigation_models_ready?
defined?(Review) && Review.column_names.include?("status") &&
defined?(Shop) && Shop.column_names.include?("approved") && Shop.column_names.include?("rejected") &&
defined?(ShopEditRequest) && ShopEditRequest.column_names.include?("status") &&
defined?(ShopReport) && ShopReport.column_names.include?("status") &&
defined?(ReviewReport) && ReviewReport.column_names.include?("status")
end

def pending_shops_scope
Shop.where(approved: false).where(rejected: [false, nil])
end

def fallback_pending_navigation_counts
{
reviews: defined?(Review) && Review.column_names.include?("status") ? Review.where(status: 0).count : 0,
shops: defined?(Shop) && Shop.column_names.include?("approved") ? fallback_pending_shops_count : 0,
edit_requests: defined?(ShopEditRequest) && ShopEditRequest.column_names.include?("status") ? ShopEditRequest.where(status: 0).count : 0,
reports: fallback_pending_reports_count
}
end

def fallback_pending_shops_count
scope = Shop.where(approved: false)
scope = scope.where(rejected: [false, nil]) if Shop.column_names.include?("rejected")
scope.count
end

def fallback_pending_reports_count
total = 0
total += ShopReport.where(status: 0).count if defined?(ShopReport) && ShopReport.column_names.include?("status")
total += ReviewReport.where(status: 0).count if defined?(ReviewReport) && ReviewReport.column_names.include?("status")
total
rescue StandardError
0
end
end
