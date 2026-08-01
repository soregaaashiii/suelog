# frozen_string_literal: true

class Admin::ShopImportsController < Admin::BaseController
  skip_forgery_protection only: :preview
  def new
    @raw_text = import_raw_text_param
    @parsed_attrs = {}
    @duplicate_candidates = []

    return if @raw_text.blank?

    @parsed_attrs = TabelogPasteParser.call(@raw_text)
    @duplicate_candidates = duplicate_candidates_for(@parsed_attrs)
  rescue StandardError => e
    flash.now[:admin_alert] = "解析に失敗しました：#{e.class} - #{e.message}"
    @parsed_attrs = {}
    @duplicate_candidates = []
  end

  def preview
    @raw_text = import_raw_text_param
    @parsed_attrs = {}
    @duplicate_candidates = []

    if @raw_text.blank?
      flash.now[:admin_alert] = "貼り付け本文を入力してください"
      render :new, status: :unprocessable_entity
      return
    end

    @parsed_attrs = TabelogPasteParser.call(@raw_text)
    @duplicate_candidates = duplicate_candidates_for(@parsed_attrs)

    render :new
  rescue StandardError => e
    @parsed_attrs = {}
    @duplicate_candidates = []
    flash.now[:admin_alert] = "解析に失敗しました：#{e.class} - #{e.message}"
    render :new, status: :unprocessable_entity
  end

  def create
    raw_text = import_raw_text_param

    if raw_text.blank?
      redirect_to new_admin_shop_import_path,
                  flash: { admin_alert: "貼り付け本文を入力してください" }
      return
    end

    parsed_attrs = TabelogPasteParser.call(raw_text)
    duplicate_candidates = duplicate_candidates_for(parsed_attrs)
    target_shop_id = params[:target_shop_id].to_i
    force_new = params[:force_new] == "1"

    if target_shop_id.positive?
      target_shop = duplicate_candidates.find { |shop| shop.id == target_shop_id } || Shop.find_by(id: target_shop_id)

      if target_shop.present?
        target_shop.defer_aicoo_activity_delivery = true
        merge_blank_fields_from_import!(target_shop, filter_shop_attrs(parsed_attrs))

        redirect_to edit_admin_shop_path(target_shop, from: "shop_import"),
                    flash: { admin_notice: "選択した既存店舗に未入力項目だけを追加しました。入力済み項目は変更していません。" }
        return
      end
    end

    if duplicate_candidates.present? && !force_new
      @raw_text = raw_text
      @parsed_attrs = parsed_attrs
      @duplicate_candidates = duplicate_candidates

      flash.now[:admin_alert] = "重複候補があります。既存店舗に追加するか、新規登録するか選択してください。"
      render :new, status: :unprocessable_entity
      return
    end

    shop = Shop.new(filter_shop_attrs(parsed_attrs))
    shop.defer_aicoo_activity_delivery = true

    shop.last_confirmed_on ||= Date.current if shop.respond_to?(:last_confirmed_on=)
    shop.smoking_unverified = true if shop.respond_to?(:smoking_unverified=)
    shop.approved = false if shop.respond_to?(:approved=)
    shop.rejected = false if shop.respond_to?(:rejected=)
    shop.on_hold = false if shop.respond_to?(:on_hold=)

    shop.save!

    redirect_to edit_admin_shop_path(shop, from: "shop_import"),
                flash: { admin_notice: "食べログ貼り付けから店舗を仮登録しました。内容を確認して保存してください。" }
  rescue ActiveRecord::RecordInvalid => e
    @raw_text = raw_text
    @parsed_attrs = parsed_attrs || {}
    @duplicate_candidates = duplicate_candidates_for(@parsed_attrs)

    flash.now[:admin_alert] = "登録に失敗しました：#{e.record.errors.full_messages.join(' / ')}"
    render :new, status: :unprocessable_entity
  rescue StandardError => e
    @raw_text = raw_text
    @parsed_attrs = {}
    @duplicate_candidates = []

    flash.now[:admin_alert] = "登録に失敗しました：#{e.class} - #{e.message}"
    render :new, status: :unprocessable_entity
  end

  private

  def import_raw_text_param
    raw_text = params[:raw_text].to_s
    source_url = params[:source_url].to_s.strip

    return raw_text if source_url.blank?
    return raw_text if raw_text.include?(source_url)

    [raw_text, "", "食べログURL", source_url].join("\n")
  end

  def filter_shop_attrs(attrs)
    attrs.to_h.select { |key, _| Shop.column_names.include?(key.to_s) }
  end

  def merge_blank_fields_from_import!(shop, parsed_attrs)
    attrs = {}

    fill_if_blank = lambda do |key|
      next unless shop.respond_to?(key) && shop.respond_to?("#{key}=")

      current_value = shop.public_send(key)
      new_value = parsed_attrs[key]

      next if new_value.blank?
      next unless import_blank_value?(current_value)

      attrs[key] = new_value
    end

    [
      :phone,
      :nearest_station,
      :genre,
      :genre_other,
      :opening_hours_text,
      :opening_hours_json,
      :holiday_hours_text,
      :closed_days_text,
      :special_hours_note,
      :budget_range,
      :last_order_text,
      :private_room_type,
      :seat_type_tags,
      :all_you_can_drink_type,
      :smoking_area,
      :smoking_type,
      :smoking_hours_text,
      :public_store_details
    ].each do |key|
      fill_if_blank.call(key)
    end

    # コピペ本文と解析結果は、重複時でも必ず保存する。
    attrs[:raw_import_text] = parsed_attrs[:raw_import_text] if shop.respond_to?(:raw_import_text=)
    attrs[:import_metadata] = parsed_attrs[:import_metadata] if shop.respond_to?(:import_metadata=)
    attrs[:import_source] = parsed_attrs[:import_source] if shop.respond_to?(:import_source=)
    attrs[:imported_at] = parsed_attrs[:imported_at] if shop.respond_to?(:imported_at=)

    shop.update!(attrs) if attrs.present?
  end

  def import_blank_value?(value)
    return true if value.blank?
    return true if value == {}
    return true if value == []
    return true if value.to_s == "unknown"

    false
  end

  def duplicate_candidates_for(attrs)
    name = attrs[:name].to_s.strip
    address = attrs[:address].to_s.strip
    phone = attrs[:phone].to_s.gsub(/[^0-9]/, "")

    scope = Shop.all
    ids = exact_duplicate_candidate_ids(scope:, phone:, name:, address:)

    ids.concat(
      Shop.normalized_duplicate_matches(
        scope: scope.order(created_at: :desc).limit(3000),
        name:,
        address:
      ).order(created_at: :desc).pluck(:id)
    )

    Shop.where(id: ids.compact.uniq.first(10))
        .where(approved: true)
        .where(rejected: false)
        .where(on_hold: false)
        .order(created_at: :desc)
  rescue StandardError => e
    Rails.logger.warn("[shop_import duplicate_candidates_for] #{e.class}: #{e.message}")
    []
  end

  def exact_duplicate_candidate_ids(scope:, phone:, name:, address:)
    relations = []
    relations << scope.where(normalized_phone: phone).limit(5) if phone.present?
    relations << scope.where(name: name).limit(5) if name.present?
    relations << scope.where(address: address).limit(5) if address.present?
    return [] if relations.empty?

    branches = relations.each_with_index.map do |relation, priority|
      <<~SQL.squish
        SELECT id, #{priority} AS match_priority, ROW_NUMBER() OVER () AS match_position
        FROM (#{relation.reselect(:id).to_sql}) AS exact_match_#{priority}
      SQL
    end

    Shop.connection.select_values(<<~SQL.squish)
      SELECT id
      FROM (#{branches.join(" UNION ALL ")}) AS exact_matches
      ORDER BY match_priority, match_position
    SQL
  end
end
