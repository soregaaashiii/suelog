# frozen_string_literal: true

require "net/http"
require "uri"

class AicooActivityLogger
  class << self
    def log(**attributes)
      new.log(**attributes)
    end
  end

  def log(**attributes)
    return { ok: true, skipped: true, reason: "disabled" } if disabled?

    payload = build_payload(attributes)
    response = post_payload(payload)
    return { ok: true, status: response.code.to_i } if response.is_a?(Net::HTTPSuccess)

    Rails.logger.warn("[AicooActivityLogger] failed HTTP #{response.code}: #{response.body}")
    { ok: false, error: "HTTP #{response.code}" }
  rescue StandardError => e
    Rails.logger.warn("[AicooActivityLogger] failed #{e.class}: #{e.message}")
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  private

  def disabled?
    ENV["AICOO_ACTIVITY_LOGGING_ENABLED"].to_s == "false"
  end

  def build_payload(attributes)
    attrs = attributes.symbolize_keys
    {
      business_key: attrs[:business_key] || ENV.fetch("AICOO_BUSINESS_KEY", "suelog"),
      activity_type: attrs[:activity_type],
      source_type: attrs[:source_type],
      source_id: attrs[:source_id],
      title: attrs[:title],
      summary: attrs[:summary],
      occurred_at: attrs[:occurred_at] || Time.current.iso8601,
      metadata: attrs[:metadata] || {}
    }.compact
  end

  def post_payload(payload)
    uri = URI.join(ENV.fetch("AICOO_API_URL"), "/api/aicoo/activity_logs")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{ENV.fetch("AICOO_ACTIVITY_API_TOKEN")}"
    request.body = payload.to_json

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
  end
end
