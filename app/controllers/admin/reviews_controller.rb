# app/controllers/admin/reviews_controller.rb
class Admin::ReviewsController < Admin::BaseController
before_action :set_review, only: [:show, :approve, :reject, :edit, :update, :destroy]
before_action :set_shop_and_reports, only: [:show, :edit, :update]

def index
@filter = params[:filter] # "reported" or nil
@status = params[:status] # "pending" or nil

scope = Review.includes(:shop).order(created_at: :desc)
scope = scope.reported if @filter == "reported"
scope = scope.where(approved: false) if @status == "pending"

@reviews = scope
end

def show
# set_review / set_shop_and_reports で準備済み
end

def approve
@review.update!(approved: true)

redirect_back(
fallback_location: admin_reviews_path(filter: params[:filter], status: params[:status]),
notice: "承認しました"
)
end

def reject
@review.destroy!

redirect_back(
fallback_location: admin_reviews_path(filter: params[:filter], status: params[:status]),
alert: "却下しました"
)
end

def destroy
@review.destroy!

redirect_back(
fallback_location: admin_reviews_path(filter: params[:filter], status: params[:status]),
alert: "口コミを削除しました"
)
end

def edit
# set_review / set_shop_and_reports で準備済み
end

def update
if @review.update(review_params)
redirect_to admin_reviews_path(filter: params[:filter], status: params[:status]),
notice: "口コミを更新しました"
else
render :edit, status: :unprocessable_entity
end
end

private

def set_review
@review = Review.includes(:shop, :review_reports).find(params[:id])
end

def set_shop_and_reports
@shop = @review.shop

@pending_reports = @review.review_reports.pending.order(created_at: :desc)
@all_reports = @review.review_reports.order(created_at: :desc)

@pending_reports_count = @pending_reports.size
@all_reports_count = @all_reports.size

@reports = @all_reports # edit画面で使う想定
end

def review_params
params.require(:review).permit(:rating, :comment, :author_name, :approved)
end
end