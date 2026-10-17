class Admin::BaseController < ApplicationController
  layout "admin"
  helper Admin::NavigationHelper
  http_basic_authenticate_with name: "kawa_admin_92", password: "X9f!pL3#sK"
  before_action :default_to_excluded_page_views

  private

  def default_to_excluded_page_views
    return if cookies.signed[:exclude_page_views].present?

    cookies.permanent.signed[:exclude_page_views] = {
      value: "1", httponly: true, same_site: :lax
    }
  end

end
