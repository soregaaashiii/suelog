class Admin::SubAdminUsersController < Admin::BaseController
  before_action :set_sub_admin_user, only: %i[edit update destroy]

  def index
    @sub_admin_users = SubAdminUser.order(created_at: :desc)
  end

  def new
    @sub_admin_user = SubAdminUser.new(
      active: true,
      permissions: ["smoking_check"]
    )
  end

  def create
    @sub_admin_user = SubAdminUser.new(sub_admin_user_params)

    if @sub_admin_user.save
      redirect_to admin_sub_admin_users_path, notice: "サブ管理者を作成しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @sub_admin_user.permissions ||= []
  end

  def update
    attrs = sub_admin_user_params

    if attrs[:password].blank?
      attrs.delete(:password)
      attrs.delete(:password_confirmation)
    end

    if @sub_admin_user.update(attrs)
      redirect_to admin_sub_admin_users_path, notice: "サブ管理者を更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @sub_admin_user.update!(active: false)
    redirect_to admin_sub_admin_users_path, notice: "サブ管理者を停止しました"
  end

  private

  def set_sub_admin_user
    @sub_admin_user = SubAdminUser.find(params[:id])
  end

  def sub_admin_user_params
    permitted =
      params
        .require(:sub_admin_user)
        .permit(
          :name,
          :login_id,
          :password,
          :password_confirmation,
          :active,
          :memo,
          permissions: []
        )

    permitted[:permissions] ||= []
    permitted
  end
end