class HotpepperApiExecution < ApplicationRecord
  belongs_to :hotpepper_api_batch
  serialize :selection, coder: JSON
  def restartable?
    state == "failed" || (kind == "match" && %w[queued running].include?(state)) || (%w[queued running].include?(state) && (heartbeat_at || updated_at) < 10.minutes.ago)
  end
end
