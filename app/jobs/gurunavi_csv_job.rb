class GurunaviCsvJob < ApplicationJob
  def perform(execution_id, token)
    execution = GurunaviCsvExecution.find_by(id: execution_id, run_token: token)
    return unless execution && %w[queued running].include?(execution.state)
    if execution.kind == "match"
      GurunaviCsv::Importer.new(execution.gurunavi_csv_batch, execution, token).call
    elsif %w[confidence expand].include?(execution.kind)
      GurunaviCsv::RefreshCandidates.new(execution, token).call
    else
      GurunaviCsv::Operations.new(execution, token).call
    end
  rescue GurunaviCsv::Importer::Superseded
    nil
  rescue StandardError => e
    message = e.is_a?(GurunaviCsv::Importer::InvalidCsv) ? e.message : "処理が停止しました（#{e.class}）。実行履歴から再開できます。"
    changed = GurunaviCsvExecution.where(id: execution_id, run_token: token).update_all(state: "failed", message: message, heartbeat_at: Time.current, updated_at: Time.current)
    if changed.positive? && execution&.kind == "match"
      GurunaviCsvBatch.where(id: execution.gurunavi_csv_batch_id).update_all(state: "failed", phase: "failed", message: message, updated_at: Time.current)
    end
    if changed.positive? && execution
      GurunaviCsvEvent.create!(gurunavi_csv_batch_id: execution.gurunavi_csv_batch_id, gurunavi_csv_execution_id: execution.id, action: "failed", payload: { kind: execution.kind, message: message })
    end
    Rails.logger.warn("[GurunaviCsvJob] #{e.class}")
  end
end
