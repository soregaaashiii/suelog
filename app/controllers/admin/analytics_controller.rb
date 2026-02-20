class Admin::AnalyticsController < Admin::BaseController
  def index
    # 全体
    @total_views = PageView.count

    # 店舗別（上位50）
    @by_shop = PageView
      .joins(:shop)
      .group("shops.id")
      .select("shops.id, shops.name, COUNT(page_views.id) AS views")
      .order(Arel.sql("views DESC"))
      .limit(50)

    # 直近7日（日別）
    @daily = PageView
      .where("created_at >= ?", 7.days.ago)
      .group("date(created_at)")
      .order(Arel.sql("date(created_at) ASC"))
      .count
  end
end
