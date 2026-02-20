class ReviewReportsController < ApplicationController
  def new
    @review = Review.find(params[:review_id])
    @shop = @review.shop
    @report = @review.review_reports.build
  end

  def create
    @review = Review.find(params[:review_id])
    @shop = @review.shop
    @report = @review.review_reports.build(report_params)
    @report.status = :pending

    if @report.save
      redirect_to done_review_review_reports_path(@review), notice: "通報が完了しました。"
      return
    else
      render :new, status: :unprocessable_entity
      return
    end
  end

  def done
    @review = Review.find(params[:review_id])
    @shop = @review.shop
  end

  private

  def report_params
    params.require(:review_report).permit(:reporter_name, :reason, :comment)
  end
end
