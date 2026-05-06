# frozen_string_literal: true

class Admin::AnalyticsController < Admin::BaseController
  def index
    # 全体
    @total_views = PageView.count

    # 店舗別（上位50）
    @by_shop = PageView
      .joins(:shop)
      .group("shops.id")
      .select("shops.id, shops.name, COUNT(page_views.id) AS views")
      .order(Arel.sql("views DESC"))
      .limit(50)

    # 直近7日（日別）
    @daily = PageView
      .where("created_at >= ?", 7.days.ago)
      .group("DATE(created_at)")
      .order(Arel.sql("DATE(created_at) ASC"))
      .count

    @article_click_sort = params[:article_click_sort].presence || "total"

    @article_shop_click_rankings =
      if defined?(ShopClick) && ShopClick.column_names.include?("article_id")
        base_scope = ShopClick
          .where(kind: "article_shop_click")
          .where.not(article_id: nil)

        ranking_scope =
          if @article_click_sort == "last_7_days"
            base_scope.where("shop_clicks.created_at >= ?", 7.days.ago)
          else
            base_scope
          end

        ranking_scope
          .joins(:article)
          .left_joins(:shop)
          .group("articles.id", "articles.title", "articles.slug")
          .select(
            "articles.id AS article_id",
            "articles.title AS article_title",
            "articles.slug AS article_slug",
            "COUNT(shop_clicks.id) AS clicks_count",
            "COUNT(DISTINCT shop_clicks.shop_id) AS shops_count"
          )
          .order(Arel.sql("clicks_count DESC"))
          .limit(30)
      else
        []
      end

    article_ids = Array(@article_shop_click_rankings).map { |row| row.article_id.to_i }.uniq

    @article_page_view_counts =
      if defined?(PageView) && article_ids.present? && PageView.column_names.include?("article_id")
        PageView
          .where(article_id: article_ids)
          .group(:article_id)
          .count
      else
        {}
      end

    @article_shop_click_rates =
      article_ids.each_with_object({}) do |article_id, hash|
        views = @article_page_view_counts[article_id].to_i
        clicks = Array(@article_shop_click_rankings).find { |row| row.article_id.to_i == article_id }&.clicks_count.to_i

        hash[article_id] =
          if views.positive?
            ((clicks.to_f / views) * 100).round(1)
          else
            0.0
          end
      end

    @article_shop_clicks_last_7_days =
      if defined?(ShopClick) && article_ids.present?
        ShopClick
          .where(kind: "article_shop_click", article_id: article_ids)
          .where("created_at >= ?", 7.days.ago)
          .group(:article_id)
          .count
      else
        {}
      end

    @article_shop_click_destinations =
      if defined?(ShopClick) && article_ids.present?
        rows = ShopClick
          .where(kind: "article_shop_click", article_id: article_ids)
          .where.not(shop_id: nil)
          .joins(:shop)
          .group("shop_clicks.article_id", "shops.id", "shops.name")
          .select(
            "shop_clicks.article_id AS article_id",
            "shops.id AS shop_id",
            "shops.name AS shop_name",
            "COUNT(shop_clicks.id) AS clicks_count"
          )
          .order(Arel.sql("clicks_count DESC"))

        rows.group_by { |row| row.article_id.to_i }
      else
        {}
      end

    destination_shop_ids =
      @article_shop_click_destinations
        .values
        .flatten
        .map { |row| row.shop_id.to_i }
        .uniq

    @destination_shop_action_counts =
      if defined?(ShopClick) && destination_shop_ids.present?
        raw_counts = ShopClick
          .where(shop_id: destination_shop_ids)
          .where(kind: %w[phone_click map_click affiliate_click])
          .group(:shop_id, :kind)
          .count

        destination_shop_ids.each_with_object({}) do |shop_id, hash|
          hash[shop_id] = {
            phone_click: raw_counts[[shop_id, "phone_click"]].to_i,
            map_click: raw_counts[[shop_id, "map_click"]].to_i,
            affiliate_click: raw_counts[[shop_id, "affiliate_click"]].to_i
          }
        end
      else
        {}
      end

    @article_affiliate_rates =
      article_ids.each_with_object({}) do |article_id, hash|
        destinations = (@article_shop_click_destinations || {})[article_id] || []
        article_shop_clicks = destinations.sum { |dest| dest.clicks_count.to_i }
        affiliate_clicks = destinations.sum do |dest|
          (@destination_shop_action_counts || {}).dig(dest.shop_id.to_i, :affiliate_click).to_i
        end

        hash[article_id] =
          if article_shop_clicks.positive?
            ((affiliate_clicks.to_f / article_shop_clicks) * 100).round(1)
          else
            0.0
          end
      end

    @improvement_candidate_articles =
      Array(@article_shop_click_rankings)
        .select do |row|
          article_id = row.article_id.to_i
          views = (@article_page_view_counts || {})[article_id].to_i
          rate = (@article_shop_click_rates || {})[article_id].to_f

          views >= 20 && rate < 3.0
        end
        .sort_by do |row|
          article_id = row.article_id.to_i

          [
            -(@article_page_view_counts || {})[article_id].to_i,
            (@article_shop_click_rates || {})[article_id].to_f
          ]
        end
        .first(10)
  end
end