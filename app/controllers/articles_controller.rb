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

  def track_shop_click
    article = Article.published.find_by!(slug: params[:id])
    shop = Shop.approved.find(params[:shop_id])

    shop.shop_clicks.create!(
      kind: "article_shop_click",
      article: article
    )

    redirect_to shop_path(shop)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[article_shop_click] validation failed: #{e.message}")
    redirect_to article_path(params[:id]), alert: "クリック記録に失敗しました"
  rescue StandardError => e
    Rails.logger.warn("[article_shop_click] #{e.class}: #{e.message}")
    redirect_to article_path(params[:id]), alert: "クリック記録に失敗しました"
  end
end