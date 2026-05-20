# frozen_string_literal: true

class Admin::ShopImportsController < Admin::BaseController
  def new
    @raw_text = params[:raw_text].to_s
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
    @raw_text = params[:raw_text].to_s
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
    raw_text = params[:raw_text].to_s

    if raw_text.blank?
      redirect_to new_admin_shop_import_path,
                  flash: { admin_alert: "貼り付け本文を入力してください" }
      return
    end

    parsed_attrs = TabelogPasteParser.call(raw_text)
    shop = Shop.new(parsed_attrs)

    shop.last_confirmed_on ||= Date.current if shop.respond_to?(:last_confirmed_on)
    shop.smoking_unverified = true if shop.respond_to?(:smoking_unverified=)
    shop.approved = false if shop.respond_to?(:approved=)
    shop.rejected = false if shop.respond_to?(:rejected=)
    shop.on_hold = false if shop.respond_to?(:on_hold=)

    shop.save!

    redirect_to edit_admin_shop_path(shop),
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

  def duplicate_candidates_for(attrs)
    name = attrs[:name].to_s.strip
    address = attrs[:address].to_s.strip
    phone = attrs[:phone].to_s.gsub(/[^0-9]/, "")

    scope = Shop.all
    ids = []

    ids.concat(scope.where(normalized_phone: phone).limit(5).pluck(:id)) if phone.present?
    ids.concat(scope.where(name: name).limit(5).pluck(:id)) if name.present?
    ids.concat(scope.where(address: address).limit(5).pluck(:id)) if address.present?

    normalized_name = Shop.normalize_duplicate_text(name)
    normalized_address = Shop.normalize_duplicate_text(address)

    if normalized_name.present? || normalized_address.present?
      scope.order(created_at: :desc).limit(3000).pluck(:id, :name, :address).each do |id, candidate_name, candidate_address|
        c_name = Shop.normalize_duplicate_text(candidate_name)
        c_address = Shop.normalize_duplicate_text(candidate_address)

        name_match = normalized_name.present? && c_name.present? && normalized_name == c_name
        address_match =
          normalized_address.present? &&
          c_address.present? &&
          (
            normalized_address == c_address ||
            normalized_address.include?(c_address) ||
            c_address.include?(normalized_address)
          )

        ids << id if name_match || address_match
      end
    end

    Shop.where(id: ids.compact.uniq.first(10)).order(created_at: :desc)
  rescue StandardError => e
    Rails.logger.warn("[shop_import duplicate_candidates_for] #{e.class}: #{e.message}")
    []
  end
end