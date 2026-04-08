# /Users/kawamuratakuya/dev/suelog/app/controllers/admin/page_view_settings_controller.rb
class Admin::PageViewSettingsController < Admin::BaseController
  def exclude
    cookies.permanent.signed[:exclude_page_views] = {
      value: "1",
      httponly: true,
      same_site: :lax
    }

    redirect_back fallback_location: admin_analytics_path,
                  notice: "この端末のアクセスは集計から除外しました"
  end

  def include
    cookies.delete(:exclude_page_views)

    redirect_back fallback_location: admin_analytics_path,
                  notice: "この端末のアクセスを集計対象に戻しました"
  end
end