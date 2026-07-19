# frozen_string_literal: true

class AicooActivityDeliveryDiagnostics
  CACHE_KEY = "aicoo/activity_delivery_diagnostics/v1"
  MAX_EVENTS = 200
  EXPIRES_IN = 30.days

  class << self
    def record(attributes)
      event = attributes.to_h.deep_stringify_keys.merge("recorded_at" => Time.current.iso8601)
      events = recent(limit: MAX_EVENTS - 1)
      Rails.cache.write(CACHE_KEY, [ event, *events ].first(MAX_EVENTS), expires_in: EXPIRES_IN)
      event
    rescue StandardError => e
      Rails.logger.warn(
        "[AicooActivityDeliveryDiagnostics] write failed error=#{e.class}: #{e.message}"
      )
      event
    end

    def recent(limit: MAX_EVENTS)
      Array(Rails.cache.read(CACHE_KEY)).first(limit).map(&:to_h)
    rescue StandardError => e
      Rails.logger.warn(
        "[AicooActivityDeliveryDiagnostics] read failed error=#{e.class}: #{e.message}"
      )
      []
    end
  end
end
