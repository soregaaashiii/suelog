class SubAdmin::SmokingChecksController < SubAdmin::BaseController
  before_action -> { require_permission!("smoking_check") }
  before_action :set_submission, only: %i[edit update]

  def index
    submitted_shop_ids =
      ShopVerificationSubmission
        .where(status: "pending")
        .select(:shop_id)

    @open_now = params[:open_now] == "1"

    scope =
      Shop
        .where(approved: true)
        .where(smoking_unverified: true)
        .where(phone_check_on_hold: [false, nil])
        .where.not(id: submitted_shop_ids)

    if @open_now
      open_shop_ids =
        scope
          .to_a
          .select { |shop| shop.respond_to?(:open_now?) && shop.open_now? }
          .map(&:id)

      scope = Shop.where(id: open_shop_ids)
    end

    @shop_click_counts =
      if defined?(ShopClick)
        ShopClick
          .where(shop_id: scope.select(:id))
          .group(:shop_id)
          .count
      else
        {}
      end

    @shops =
      scope
        .left_joins(:shop_clicks)
        .group("shops.id")
        .order(Arel.sql("COUNT(shop_clicks.id) DESC, shops.created_at DESC"))
        .limit(100)
  end

  def submissions
    @submissions =
      ShopVerificationSubmission
        .includes(:shop)
        .where(sub_admin_user: current_sub_admin_user)
        .order(created_at: :desc)
        .limit(100)
  end

  def edit
    unless editable_submission?(@submission)
      redirect_to sub_admin_smoking_check_submissions_path,
                  alert: "この確認結果は編集できません"
    end
  end

  def create
    shop = Shop.find(params[:shop_id])

    ShopVerificationSubmission.create!(
      shop: shop,
      sub_admin_user: current_sub_admin_user,
      result: params[:smoking_location],
      smoking_location: params[:smoking_location],
      tobacco_type: params[:tobacco_type],
      memo: params[:memo].to_s.strip,
      status: "pending"
    )

    redirect_to sub_admin_root_path, notice: "確認結果を送信しました"
  end

  def update
    unless editable_submission?(@submission)
      redirect_to sub_admin_smoking_check_submissions_path,
                  alert: "この確認結果は編集できません"
      return
    end

    @submission.update!(
      result: params[:smoking_location],
      smoking_location: params[:smoking_location],
      tobacco_type: params[:tobacco_type],
      memo: params[:memo].to_s.strip,
      status: "pending"
    )

    redirect_to sub_admin_smoking_check_submissions_path,
                notice: "確認結果を更新しました"
  end

  private

  def set_submission
    @submission =
      ShopVerificationSubmission
        .where(sub_admin_user: current_sub_admin_user)
        .find(params[:id])
  end

  def editable_submission?(submission)
    submission.status.in?(%w[pending returned])
  end
end