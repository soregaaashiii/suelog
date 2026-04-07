class Admin::BaseController < ApplicationController
  layout "admin"
  helper Admin::NavigationHelper
  http_basic_authenticate_with name: "kawa_admin_92", password: "X9f!pL3#sK"
end
