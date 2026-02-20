class ShopReportsController < ApplicationController
  def new
    @shop = Shop.find(params[:shop_id])
    @report = ShopReport.new
  end

  def create
    @shop = Shop.find(params[:shop_id])
    @report = @shop.shop_reports.build(report_params)
    @report.status = :pending

    if @report.save
      redirect_to shop_path(@shop), notice: "通報を送信しました（確認後に対応されます）"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def report_params
    params.require(:shop_report).permit(:reporter_name, :reason, :detail)
  end
end
