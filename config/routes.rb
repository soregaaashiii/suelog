# /Users/kawamuratakuya/dev/suelog/config/routes.rb
Rails.application.routes.draw do
# onrender.com で来たアクセスを独自ドメインへ恒久リダイレクト
constraints(host: /(?:.+\.)?onrender\.com\z/) do
match "*path",
to: redirect(status: 301) { |params, _req| "https://suelog.jp/#{params[:path]}" },
via: :all
end

root "home#index"

get "map", to: "maps#index"

resources :shops do
resources :reviews, only: [:create]

resources :shop_edit_requests, only: [:new, :create] do
collection do
get :done
end
end

resources :shop_reports, only: [:new, :create] do
collection do
get :done
end
end
end

resources :reviews, only: [] do
resources :review_reports, only: [:new, :create] do
collection do
get :done
end
end
end

namespace :admin do
resources :shops, only: [:index] do
member do
patch :approve
patch :reject
end

collection do
post :import_csv
end
end

resources :reviews, only: [:index] do
member do
patch :approve
patch :reject
end
end
end
end