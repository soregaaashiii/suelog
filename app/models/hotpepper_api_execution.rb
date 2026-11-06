class HotpepperApiExecution < ApplicationRecord
  belongs_to :hotpepper_api_batch
  serialize :selection, coder: JSON
  def restartable?
    state == "failed" || (%w[queued running].include?(state) && (heartbeat_at || updated_at) < 10.minutes.ago)
  end
end
