# frozen_string_literal: true

class SeoPageTaskEditor
  class Conflict < StandardError; end

  def initialize(path:, attributes:, expected_version:)
    @path, @attributes, @version = path, attributes, expected_version.to_s
  end

  def call
    task = SeoPageTask.find_or_initialize_by(path: @path)
    if task.persisted?
      task.with_lock do
        raise Conflict unless task.version_token == @version
        persist(task)
      end
    else
      raise Conflict unless @version == "new"
      SeoPageTask.transaction { persist(task) }
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::StaleObjectError
    raise Conflict
  end

  private

  def persist(task)
    task.assign_attributes(@attributes.slice(:status, :note, :handled_on))
    if task.status != "pending" && task.handled_on_before_type_cast.blank?
      task.handled_on = Date.current
    end
    task.validate!
    return false unless task.changes.except("path").any?
    task.save!
    true
  end
end
