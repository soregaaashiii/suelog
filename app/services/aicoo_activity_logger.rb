# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "digest"

class AicooActivityLogger
  class DeliveryError < StandardError
    attr_reader :attempts

    def initialize(error, attempts)
      @attempts = attempts
      super("#{error.class}: #{error.message}")
    end
  end

  MAX_ATTEMPTS = 3
  RETRY_DELAYS = Rails.env.test? ? [ 0, 0 ].freeze : [ 0.25, 1.0 ].freeze
  RETRYABLE_STATUSES = [ 429, 500, 502, 503, 504 ].freeze
  RETRYABLE_ERRORS = [
    EOFError,
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::EHOSTUNREACH,
    Net::OpenTimeout,
    Net::ReadTimeout,
    SocketError,
    Timeout::Error
  ].freeze

  class << self
    def log(**attributes)
      new.log(**attributes)
    end

    def configuration
      new.configuration
    end
  end

  def log(**attributes)
    payload = build_payload(attributes)
    return finish(payload, attributes, disabled_result) if disabled?

    config_error = configuration_error
    return finish(payload, attributes, failure_result(config_error)) if config_error

    log_start(payload)
    response, attempts = post_with_retries(payload)
    response_body = response.body.to_s.truncate(500)
    Rails.logger.info(
      "[AicooActivityLogger] HTTP status=#{response.code} attempts=#{attempts} response body=#{response_body}"
    )
    result = response_result(response, attempts:, response_body:)
    return finish(payload, attributes, result) if result[:ok]

    Rails.logger.warn("[AicooActivityLogger] failed HTTP #{response.code}: #{response_body}")
    finish(payload, attributes, result)
  rescue StandardError => e
    Rails.logger.warn("[AicooActivityLogger] error class=#{e.class} message=#{e.message}")
    finish(
      payload || build_payload(attributes),
      attributes,
      failure_result(
        "delivery_exception",
        exception: "#{e.class}: #{e.message}",
        retry_count: e.respond_to?(:attempts) ? e.attempts - 1 : 0
      )
    )
  end

  def configuration
    {
      enabled: !disabled?,
      api_url: api_url,
      api_url_configured: api_url.present?,
      token_configured: api_token.present?,
      token_source: api_token_source,
      business_key: ENV.fetch("AICOO_BUSINESS_KEY", "suelog")
    }
  end

  private

  def disabled?
    ENV["AICOO_ACTIVITY_LOGGING_ENABLED"].to_s == "false"
  end

  def build_payload(attributes)
    attrs = attributes.symbolize_keys
    source_type = attrs[:source_type]
    source_id = attrs[:source_id]
    occurred_at = attrs[:occurred_at] || Time.current.iso8601
    {
      business_key: attrs[:business_key] || ENV.fetch("AICOO_BUSINESS_KEY", "suelog"),
      source_app: attrs[:source_app] || "suelog",
      activity_type: attrs[:activity_type],
      source_type:,
      source_id:,
      resource_type: attrs[:resource_type] || source_type.to_s.camelize,
      resource_id: attrs[:resource_id] || source_id,
      title: attrs[:title],
      summary: attrs[:summary],
      occurred_at:,
      changed_fields: attrs[:changed_fields] || {},
      metadata: attrs[:metadata] || {},
      idempotency_key: attrs[:idempotency_key] || idempotency_key_for(
        source_type:,
        source_id:,
        activity_type: attrs[:activity_type],
        occurred_at:
      )
    }.compact
  end

  def post_payload(payload)
    uri = URI.join(api_url, "/api/aicoo/activity_logs")
    Rails.logger.info("[AicooActivityLogger] POST先URL=#{uri}")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{api_token}"
    request.body = payload.to_json

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
  end

  def post_with_retries(payload)
    attempts = 0

    loop do
      attempts += 1
      response = post_payload(payload)
      return [ response, attempts ] unless retryable_status?(response.code.to_i) && attempts < MAX_ATTEMPTS

      sleep(RETRY_DELAYS.fetch(attempts - 1, RETRY_DELAYS.last))
    rescue *RETRYABLE_ERRORS => e
      raise DeliveryError.new(e, attempts) if attempts >= MAX_ATTEMPTS

      Rails.logger.warn(
        "[AicooActivityLogger] retry attempt=#{attempts} error=#{e.class}: #{e.message}"
      )
      sleep(RETRY_DELAYS.fetch(attempts - 1, RETRY_DELAYS.last))
    end
  end

  def log_start(payload)
    Rails.logger.info(
      "[AicooActivityLogger] start " \
      "AICOO_API_URL=#{ENV['AICOO_API_URL'].presence || '(blank)'} " \
      "business_key=#{payload[:business_key].presence || '(blank)'} " \
      "source_type=#{payload[:source_type].presence || '(blank)'} " \
      "source_id=#{payload[:source_id].presence || '(blank)'}"
    )
  end

  def finish(payload, attributes, result)
    diagnostic = {
      event_type: payload[:activity_type],
      model: attributes[:callback_model] || payload[:resource_type],
      source_id: payload[:source_id],
      record_saved: attributes.fetch(:record_saved, true),
      callback_registered: attributes[:callback_registered],
      callback_called: attributes.fetch(:callback_called, false),
      activity_api_client_called: !result[:skipped],
      request_created: result[:request_created],
      request_sent: result[:request_sent],
      response_status: result[:status],
      response_body: result[:response_body],
      retry_count: result[:retry_count].to_i,
      business_activity_log_created: result[:business_activity_log_created],
      business_activity_log_id: result[:business_activity_log_id],
      skip_reason: result[:reason],
      exception: result[:exception],
      ok: result[:ok]
    }.compact
    AicooActivityDeliveryDiagnostics.record(diagnostic)
    result
  rescue StandardError => e
    Rails.logger.warn(
      "[AicooActivityLogger] diagnostic record failed error=#{e.class}: #{e.message}"
    )
    result
  end

  def response_result(response, attempts:, response_body:)
    parsed_body = JSON.parse(response.body.to_s)
    ok = response.is_a?(Net::HTTPSuccess)
    {
      ok:,
      request_created: true,
      request_sent: true,
      status: response.code.to_i,
      response_body:,
      retry_count: attempts - 1,
      business_activity_log_created: ok && parsed_body["id"].present?,
      business_activity_log_id: parsed_body["id"],
      reason: ok ? nil : "http_#{response.code}",
      error: ok ? nil : "HTTP #{response.code}"
    }.compact
  rescue JSON::ParserError
    {
      ok: response.is_a?(Net::HTTPSuccess),
      request_created: true,
      request_sent: true,
      status: response.code.to_i,
      response_body:,
      retry_count: attempts - 1,
      business_activity_log_created: false,
      reason: response.is_a?(Net::HTTPSuccess) ? "response_id_missing" : "http_#{response.code}"
    }
  end

  def failure_result(reason, exception: nil, retry_count: 0)
    {
      ok: false,
      request_created: false,
      request_sent: false,
      retry_count:,
      business_activity_log_created: false,
      reason:,
      exception:,
      error: exception || reason
    }.compact
  end

  def disabled_result
    failure_result("disabled").merge(skipped: true)
  end

  def configuration_error
    return "missing_aicoo_api_url" if api_url.blank?
    return "missing_aicoo_activity_api_token" if api_token.blank?

    nil
  end

  def api_url
    ENV["AICOO_API_URL"].to_s.strip.presence
  end

  def api_token
    ENV["AICOO_ACTIVITY_API_TOKEN"].presence ||
      ENV["AICOO_ACTIVITY_API_KEY"].presence ||
      ENV["AICOO_API_KEY"].presence
  end

  def api_token_source
    return "AICOO_ACTIVITY_API_TOKEN" if ENV["AICOO_ACTIVITY_API_TOKEN"].present?
    return "AICOO_ACTIVITY_API_KEY" if ENV["AICOO_ACTIVITY_API_KEY"].present?
    return "AICOO_API_KEY" if ENV["AICOO_API_KEY"].present?

    nil
  end

  def retryable_status?(status)
    RETRYABLE_STATUSES.include?(status)
  end

  def idempotency_key_for(source_type:, source_id:, activity_type:, occurred_at:)
    Digest::SHA256.hexdigest(
      [ "suelog", source_type, source_id, activity_type, occurred_at ].join(":")
    )
  end
end
