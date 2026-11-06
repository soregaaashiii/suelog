class HotpepperApiJob < ApplicationJob
  def perform(execution_id, token)
    execution = HotpepperApiExecution.find_by(id: execution_id, run_token: token)
    return unless execution && %w[queued running].include?(execution.state)
    if execution.kind == "match"
      HotpepperApi::Importer.new(execution.hotpepper_api_batch, execution, token).call
    else
      HotpepperApi::Operations.new(execution, token).call
    end
  rescue HotpepperApi::Importer::Superseded
    nil
  rescue StandardError => e
    message = (e.is_a?(HotpepperApi::Importer::InvalidSearch) || e.is_a?(RestaurantUrlSearch::SerpApi::Unavailable)) ? e.message : "処理が停止しました（#{e.class}）。実行履歴から再開できます。"
    changed = HotpepperApiExecution.where(id: execution_id, run_token: token).update_all(state: "failed", message: message, heartbeat_at: Time.current, updated_at: Time.current)
    if changed.positive? && execution&.kind == "match"
      HotpepperApiBatch.where(id: execution.hotpepper_api_batch_id).update_all(state: "failed", phase: "failed", message: message, updated_at: Time.current)
    end
    if changed.positive? && execution
      HotpepperApiEvent.create!(hotpepper_api_batch_id: execution.hotpepper_api_batch_id, hotpepper_api_execution_id: execution.id, action: "failed", payload: { kind: execution.kind, message: message })
    end
    Rails.logger.warn("[HotpepperApiJob] #{e.class}")
  end
end
