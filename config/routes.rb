# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/config/routes.rb
# frozen_string_literal: true

Rails.application.routes.draw do
root "home#index"

get "map", to: "shops#map"

resources :shops do
collection do
get :possible_duplicates
end

resources :reviews, only: [:create]

resources :shop_edit_requests, only: [:new, :create] do
collection { get :done }
end

resources :shop_reports, only: [:new, :create] do
collection { get :done }
end
end

resources :reviews, only: [:edit, :update] do
resources :review_reports, only: [:new, :create] do
collection { get :done }
end
end

resources :contact_messages, only: [:new, :create] do
collection { get :done }
end

get "terms", to: "static_pages#terms"
get "privacy", to: "static_pages#privacy"

namespace :admin do
get "analytics", to: "analytics#index"
resources :contact_messages, only: [:index, :show, :destroy]

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