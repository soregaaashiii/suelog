class SubAdmin::BaseController < ApplicationController
  layout "application"

  before_action :require_sub_admin_login

  helper_method :current_sub_admin_user

  private

  def current_sub_admin_user
    @current_sub_admin_user ||= SubAdminUser.find_by(id: session[:sub_admin_user_id])
  end

  def require_sub_admin_login
    return if current_sub_admin_user&.active?

    redirect_to sub_admin_login_path, alert: "ログインしてください"
  end

  def require_permission!(permission_key)
    return if current_sub_admin_user&.can?(permission_key)

    redirect_to sub_admin_root_path, alert: "この操作を行う権限がありません"
  end
end