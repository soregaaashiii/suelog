# /Users/kawamuratakuya/dev/suelog/app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  def index
    @articles = Article.published
  end

  def show
    @article = Article.published.find_by!(slug: params[:id])
  end
end