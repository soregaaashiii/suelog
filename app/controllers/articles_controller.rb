class ArticlesController < ApplicationController
  def index
    @q = params[:q].to_s.strip

    @articles = Article.published

    if @q.present?
      @articles = @articles.where(
  "title LIKE :q OR summary LIKE :q",
  q: "%#{@q}%"
)
    end
  end

  def show
    @article = Article.published.find_by!(slug: params[:id])
  end
end