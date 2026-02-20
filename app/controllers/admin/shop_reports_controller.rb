class Admin::ShopReportsController < Admin::BaseController
  def index
    @reports =
      if params[:status] == "pending"
        ShopReport.where(status: 0).order(created_at: :desc)
      else
        ShopReport.order(created_at: :desc)
      end
  end

  def show
    @report = ShopReport.find(params[:id])
    @shop = @report.shop
  end

  def resolve
    rep = ShopReport.find(params[:id])
    rep.update!(status: :resolved)
    redirect_back fallback_location: admin_shop_reports_path(status: "pending"), notice: "対応済みにしました"
  end

  def reject
    rep = ShopReport.find(params[:id])
    rep.update!(status: :rejected)
    redirect_back fallback_location: admin_shop_reports_path(status: "pending"), alert: "却下しました"
  end
end

