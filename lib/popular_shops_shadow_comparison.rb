# frozen_string_literal: true

require "benchmark"

class PopularShopsShadowComparison
  Result = Data.define(
    :compared,
    :count_mismatches,
    :id_mismatches,
    :order_mismatches,
    :value_mismatches,
    :html_mismatches,
    :errors,
    :legacy_seconds,
    :optimized_seconds,
    :mismatch_details
  )

  def initialize(limit:, html_limit: 0, pause_seconds: 0.0, output: $stdout)
    @limit = limit.to_i
    @html_limit = html_limit.to_i
    @pause_seconds = pause_seconds.to_f
    @output = output
    @controller = ShopsController.new
  end

  def call
    counters = Hash.new(0)
    legacy_seconds = []
    optimized_seconds = []
    mismatch_details = []

    comparison_shop_ids.each_with_index do |shop_id, index|
      comparison = compare_shop(shop_id, compare_html: index < @html_limit)
      counters[:compared] += 1
      legacy_seconds << comparison.fetch(:legacy_seconds)
      optimized_seconds << comparison.fetch(:optimized_seconds)

      comparison.fetch(:mismatch_types).each do |type|
        counters[type] += 1
      end

      if comparison.fetch(:mismatch_types).any?
        mismatch_details << comparison.slice(
          :comparison,
          :shop_id,
          :legacy_count,
          :optimized_count,
          :legacy_ids,
          :optimized_ids,
          :mismatch_position,
          :mismatch_types
        ).merge(comparison: index + 1)
      end

      print_progress(index + 1, counters, legacy_seconds, optimized_seconds)
      sleep(@pause_seconds) if @pause_seconds.positive?
    rescue StandardError => error
      counters[:compared] += 1
      counters[:errors] += 1
      mismatch_details << {
        comparison: index + 1,
        shop_id:,
        mismatch_types: [ "error" ],
        error_class: error.class.name
      }
      print_progress(index + 1, counters, legacy_seconds, optimized_seconds)
    end

    Result.new(
      compared: counters[:compared],
      count_mismatches: counters["count_mismatch"],
      id_mismatches: counters["id_mismatch"],
      order_mismatches: counters["order_mismatch"],
      value_mismatches: counters["value_mismatch"],
      html_mismatches: counters["html_mismatch"],
      errors: counters[:errors],
      legacy_seconds: timing_summary(legacy_seconds),
      optimized_seconds: timing_summary(optimized_seconds),
      mismatch_details: mismatch_details.first(25)
    )
  end

  private

  def comparison_shop_ids
    batch_size = [ (@limit / 6.0).ceil, 1 ].max
    scopes = [
      Shop.order(id: :asc),
      Shop.order(id: :desc),
      Shop.where.not(latitude: nil, longitude: nil).order(id: :asc),
      Shop.where(latitude: nil).order(id: :asc),
      Shop.left_joins(:shop_clicks).where(shop_clicks: { id: nil }).order(id: :asc),
      Shop.where(last_confirmed_on: nil).order(id: :asc)
    ]

    selected = scopes.flat_map { |scope| scope.limit(batch_size).pluck(:id) }.uniq
    if selected.size < @limit
      selected.concat(Shop.where.not(id: selected).order(:id).limit(@limit - selected.size).pluck(:id))
    end
    selected.first(@limit)
  end

  def compare_shop(shop_id, compare_html:)
    result = nil

    Shop.transaction(**transaction_options) do
      set_transaction_read_only
      shop = Shop.find(shop_id)
      legacy = nil
      optimized = nil

      legacy_seconds = Benchmark.realtime do
        legacy = @controller.send(:legacy_popular_shops_for, shop)
      end
      optimized_seconds = Benchmark.realtime do
        optimized = @controller.send(:optimized_popular_shops_for, shop)
      end

      legacy_ids = legacy.map(&:id)
      optimized_ids = optimized.map(&:id)
      legacy_values = display_values(legacy)
      optimized_values = display_values(optimized)
      mismatch_types = []
      mismatch_types << "count_mismatch" unless legacy.size == optimized.size
      if legacy_ids.sort != optimized_ids.sort
        mismatch_types << "id_mismatch"
      elsif legacy_ids != optimized_ids
        mismatch_types << "order_mismatch"
      end
      mismatch_types << "value_mismatch" unless legacy_values == optimized_values

      if compare_html && render_shop_cards(legacy) != render_shop_cards(optimized)
        mismatch_types << "html_mismatch"
      end

      result = {
        shop_id:,
        legacy_count: legacy.size,
        optimized_count: optimized.size,
        legacy_ids:,
        optimized_ids:,
        mismatch_position: first_mismatch_position(legacy_ids, optimized_ids),
        mismatch_types:,
        legacy_seconds:,
        optimized_seconds:
      }
    end

    result
  end

  def transaction_options
    options = { requires_new: true }
    options[:isolation] = :repeatable_read if postgres?
    options
  end

  def set_transaction_read_only
    return unless postgres?

    ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
  end

  def postgres?
    ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
  end

  def display_values(shops)
    shops.map do |shop|
      {
        id: shop.id,
        clicks_count: shop.clicks_count.to_i,
        distance: shop.respond_to?(:distance) ? shop.distance&.to_f : nil,
        bearing: shop.respond_to?(:bearing) ? shop.bearing&.to_f : nil
      }
    end
  end

  def render_shop_cards(shops)
    ApplicationController.render(
      partial: "shared/shop_cards",
      locals: { shops: }
    )
  end

  def first_mismatch_position(legacy_ids, optimized_ids)
    length = [ legacy_ids.length, optimized_ids.length ].max
    length.times.find { |index| legacy_ids[index] != optimized_ids[index] }
  end

  def print_progress(current, counters, legacy_seconds, optimized_seconds)
    return unless (current % 100).zero? || current == @limit

    @output.puts({
      compared: current,
      mismatches: counters.values_at(
        "count_mismatch",
        "id_mismatch",
        "order_mismatch",
        "value_mismatch",
        "html_mismatch"
      ).sum,
      errors: counters[:errors],
      legacy_median_seconds: median(legacy_seconds).round(4),
      optimized_median_seconds: median(optimized_seconds).round(4)
    }.inspect)
  end

  def timing_summary(values)
    return { runs: 0, median: nil, maximum: nil, total: 0.0 } if values.empty?

    {
      runs: values.size,
      median: median(values).round(6),
      maximum: values.max.round(6),
      total: values.sum.round(6)
    }
  end

  def median(values)
    sorted = values.sort
    middle = sorted.length / 2
    sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end
end
