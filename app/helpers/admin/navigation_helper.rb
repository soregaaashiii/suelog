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
return 0 unless defined?(Review)
return 0 unless Review.column_names.include?("status")

Review.where(status: 0).count
rescue
0
end

# 店舗：approved:false AND rejected:false/nil
def pending_shops_count
return 0 unless defined?(Shop)
return 0 unless Shop.column_names.include?("approved")

scope = Shop.where(approved: false)
scope = scope.where(rejected: [false, nil]) if Shop.column_names.include?("rejected")
scope.count
rescue
0
end

# 編集依頼：status:0
def pending_edit_requests_count
return 0 unless defined?(ShopEditRequest)
return 0 unless ShopEditRequest.column_names.include?("status")

ShopEditRequest.where(status: 0).count
rescue
0
end

# 通報：ShopReport + ReviewReport を合算（どっちか無くても落ちない）
def pending_reports_count
total = 0

if defined?(ShopReport) && ShopReport.column_names.include?("status")
total += ShopReport.where(status: 0).count
end

if defined?(ReviewReport) && ReviewReport.column_names.include?("status")
total += ReviewReport.where(status: 0).count
end

total
rescue
0
end
end