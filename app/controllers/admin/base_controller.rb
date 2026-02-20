class Admin::BaseController < ApplicationController
  layout "admin"
  helper Admin::NavigationHelper
  http_basic_authenticate_with name: "admin", password: "password"
end
