# config/routes.rb
Rails.application.routes.draw do
# ✅ ホーム（= 一覧）に統一
root "home#index"

# ✅ map は ShopsController#map を使う
get "map", to: "shops#map"

resources :shops do
# ✅ 電話重複の疑いページ（電話番号で検索して表示）
collection do
get :possible_duplicates
end

# ✅ 口コミは「投稿(create)だけ」店舗配下にする
resources :reviews, only: [:create]

resources :shop_edit_requests, only: [:new, :create] do
collection { get :done }
end

resources :shop_reports, only: [:new, :create] do
collection { get :done }
end
end

# ✅ 口コミの編集/更新は単独URL（/reviews/:id/edit）
resources :reviews, only: [:edit, :update] do
resources :review_reports, only: [:new, :create] do
collection { get :done }
end
end

# ✅ お問い合わせ（公開側）
resources :contact_messages, only: [:new, :create] do
collection { get :done }
end

# --- Static Pages ---
get "terms", to: "static_pages#terms"
get "privacy", to: "static_pages#privacy"

# ✅ 管理画面
namespace :admin do
get "analytics", to: "analytics#index"

# ✅ お問い合わせ（管理側）
resources :contact_messages, only: [:index, :show, :destroy]

resources :shops, only: [:index] do
member do
patch :approve
patch :reject
end
end

resources :reviews, only: [:index, :show, :edit, :update] do
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

resources :shop_reports, only: [:index, :show] do
member do
patch :resolve
patch :reject
end
end

resources :review_reports, only: [:index, :show] do
member do
patch :resolve
patch :reject
end
end
end
end