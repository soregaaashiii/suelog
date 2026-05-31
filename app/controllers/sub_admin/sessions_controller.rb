class SubAdmin::SessionsController < ApplicationController
  def new
  end

  def create
    user = SubAdminUser.active.find_by(login_id: params[:login_id].to_s.strip)

    if user&.authenticate(params[:password])
      session[:sub_admin_user_id] = user.id
      user.update!(last_login_at: Time.current)
      redirect_to sub_admin_root_path, notice: "ログインしました"
    else
      flash.now[:alert] = "ログインIDまたはパスワードが違います"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:sub_admin_user_id)
    redirect_to sub_admin_login_path, notice: "ログアウトしました"
  end
end