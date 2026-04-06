# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/config/routes.rb
Rails.application.routes.draw do
constraints(host: /(?:.+\.)?onrender\.com\z/) do
get "/", to: redirect("https://suelog.jp", status: 301)

match "*path",
to: redirect(status: 301) { |params, _req| "https://suelog.jp/#{params[:path]}" },
via: :all
end

root "home#index"

get "map", to: "maps#index"

# 固定ページ
get "terms", to: "static_pages#terms", as: :terms
get "privacy", to: "static_pages#privacy", as: :privacy

# お問い合わせ
get "contact", to: "contact_messages#new", as: :new_contact_message
post "contact", to: "contact_messages#create", as: :contact_messages
get "contact/done", to: "contact_messages#done", as: :done_contact_messages

# 記事
resources :articles, only: [:index, :show]

# Area landing / filtered pages
get "umeda",
to: "home#index",
as: :umeda,
defaults: { area: "umeda" }

get "umeda/smoking/:smoking_area",
to: "home#index",
as: :umeda_smoking,
defaults: { area: "umeda" }

get "umeda/genre/:genre",
to: "home#index",
as: :umeda_genre,
defaults: { area: "umeda" }

get "namba",
to: "home#index",
as: :namba,
defaults: { area: "namba" }

get "namba/smoking/:smoking_area",
to: "home#index",
as: :namba_smoking,
defaults: { area: "namba" }

get "namba/genre/:genre",
to: "home#index",
as: :namba_genre,
defaults: { area: "namba" }

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

# 口コミ本人編集用
resources :reviews, only: [:edit, :update]

# 口コミ通報用
resources :reviews, only: [] do
resources :review_reports, only: [:new, :create] do
collection do
get :done
end
end
end

namespace :admin do
get "analytics", to: "analytics#index", as: :analytics

resources :shops, only: [:index, :edit, :update] do
member do
patch :approve
patch :reject
end

collection do
patch :bulk_update
post :import
end
end

resources :reviews, only: [:index, :destroy] do
member do
patch :approve
patch :reject
end
end

resources :shop_edit_requests, only: [:index, :show] do
member do
patch :approve
patch :reject
end
end

resources :shop_reports, only: [:index] do
member do
patch :approve
patch :reject
end
end

resources :contact_messages, only: [:index, :show, :destroy]

# 記事管理
resources :articles
end
end