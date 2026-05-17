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

    ShopReport.transaction do
      rep.update!(status: :resolved)

      if rep.shop.present?
        report_summary =
          if rep.respond_to?(:reason)
            rep.reason
          elsif rep.respond_to?(:report_type)
            rep.report_type
          else
            nil
          end

        rep.shop.update!(
          approved: false,
          rejected: false,
          on_hold: true,
          hold_reason: "通報対応",
          hold_note: [
            rep.shop.hold_note.presence,
            "通報対応により保留へ移動: #{report_summary.presence || "詳細未指定"}"
          ].compact.join("\n")
        )
      end
    end

    redirect_back fallback_location: admin_shop_reports_path(status: "pending"), notice: "対応済みにして、店舗を保留に移動しました"
  end

  def reject
    rep = ShopReport.find(params[:id])
    rep.update!(status: :rejected)
    redirect_back fallback_location: admin_shop_reports_path(status: "pending"), alert: "却下しました"
  end
end

