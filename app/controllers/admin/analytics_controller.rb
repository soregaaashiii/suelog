# /Users/kawamuratakuya/dev/suelog/app/controllers/admin/articles_controller.rb
# frozen_string_literal: true

class Admin::ArticlesController < Admin::BaseController
before_action :set_article, only: [:show, :edit, :update, :destroy]

def index
@articles = Article.order(created_at: :desc)
end

def show
end

def new
@article = Article.new(published: false)
end

def create
@article = Article.new(article_params)

if @article.save
redirect_to admin_articles_path, notice: "記事を作成しました"
else
render :new, status: :unprocessable_entity
end
end

def edit
end

def update
if @article.update(article_params)
redirect_to admin_articles_path, notice: "記事を更新しました"
else
render :edit, status: :unprocessable_entity
end
end

def destroy
@article.destroy!
redirect_to admin_articles_path, notice: "記事を削除しました"
end

private

def set_article
@article =
Article.find_by(slug: params[:id]) ||
Article.find_by(id: params[:id])

raise ActiveRecord::RecordNotFound, "Article not found" unless @article
end

def article_params
params.require(:article).permit(
:title,
:slug,
:summary,
:published,
:published_at,
:admin_note,
:seo_title,
:meta_description,
:eyecatch,
:body
)
end
end