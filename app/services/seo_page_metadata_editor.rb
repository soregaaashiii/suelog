# frozen_string_literal: true

class SeoPageMetadataEditor
  class Conflict < StandardError; end
  Result = Struct.new(:setting, :changed, keyword_init: true)

  def initialize(path:, attributes:, expected_version:, defaults:, change_note: nil)
    @path, @attributes, @expected_version, @defaults = path, attributes, expected_version.to_s, defaults
    @change_note = change_note.to_s.strip.presence
  end

  def call
    setting = SeoPageSetting.find_or_initialize_by(path: @path)
    if setting.persisted?
      setting.with_lock do
        raise Conflict unless @expected_version == setting.version_token
        persist(setting)
      end
    else
      raise Conflict unless @expected_version == "new"
      SeoPageSetting.transaction { persist(setting) }
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::StaleObjectError
    raise Conflict
  end

  private

  def persist(setting)
    before_values = setting.snapshot(@defaults)
    setting.assign_attributes(@attributes.slice(:title, :description))
    setting.valid?
    setting.errors.add(:base, "変更メモは500文字以内で入力してください。") if @change_note && @change_note.length > 500
    raise ActiveRecord::RecordInvalid, setting if setting.errors.any?
    changed = setting.will_save_change_to_title? || setting.will_save_change_to_description?
    return Result.new(setting: setting, changed: false) unless changed

    setting.save!
    setting.revisions.create!(before_values: before_values, after_values: setting.snapshot(@defaults), change_note: @change_note)
    Result.new(setting: setting, changed: true)
  end
end
