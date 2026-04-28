class ArticlesController < ApplicationController
  def index
    @q = params[:q].to_s.strip

    @articles = Article.published.left_joins(:rich_text_body)

    if @q.present?
      @articles = @articles.where(
        "articles.title LIKE :q OR articles.summary LIKE :q OR action_text_rich_texts.body LIKE :q",
        q: "%#{@q}%"
      )
    end
  end

  def show
    @article = Article.published.find_by!(slug: params[:id])
  end
end