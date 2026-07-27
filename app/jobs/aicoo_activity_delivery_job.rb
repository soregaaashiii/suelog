class AicooActivityDeliveryJob < ApplicationJob
  queue_as :default
  self.log_arguments = false

  def perform(attributes)
    attrs = attributes.to_h.deep_symbolize_keys
    result = AicooActivityLogger.log(**attrs)
    level = result[:ok] ? :info : :warn

    Rails.logger.public_send(
      level,
      "[AICOO Activity] deferred delivery " \
      "action=#{attrs[:activity_type]} source_type=#{attrs[:source_type]} " \
      "source_id=#{attrs[:source_id]} ok=#{result[:ok]} " \
      "status=#{result[:status].presence || '(none)'} " \
      "retry_count=#{result[:retry_count].to_i} reason=#{result[:reason].presence || '(none)'}"
    )
  end
end
