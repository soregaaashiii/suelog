# frozen_string_literal: true

module Aicoo
  class SuelogActivityApiDiagnostic
    CALLBACKS = {
      "Shop" => %w[log_aicoo_shop_created log_aicoo_shop_updated log_aicoo_shop_destroyed],
      "Article" => %w[log_aicoo_article_created log_aicoo_article_updated log_aicoo_article_destroyed]
    }.freeze

    def self.call(send_probe: false, io: $stdout)
      new(send_probe:, io:).call
    end

    def initialize(send_probe:, io:)
      @send_probe = send_probe
      @io = io
    end

    def call
      configuration = AicooActivityLogger.configuration
      callback_status = build_callback_status
      events = AicooActivityDeliveryDiagnostics.recent
      probe_result = send_probe ? run_probe : nil
      events = AicooActivityDeliveryDiagnostics.recent if send_probe
      summary = build_summary(configuration, callback_status, events, probe_result)

      print_configuration(configuration)
      print_callbacks(callback_status)
      print_events(events)
      print_probe(probe_result) if probe_result
      print_summary(summary)

      summary.merge(
        configuration:,
        callbacks: callback_status,
        events:,
        probe: probe_result
      )
    end

    private

    attr_reader :send_probe, :io

    def build_callback_status
      CALLBACKS.each_with_object({}) do |(model_name, expected), result|
        model = model_name.constantize
        registered = model._commit_callbacks.map(&:filter).map(&:to_s)
        result[model_name] = {
          expected:,
          registered: expected.select { |callback| registered.include?(callback) },
          missing: expected.reject { |callback| registered.include?(callback) }
        }
      end
    end

    def run_probe
      AicooActivityLogger.log(
        business_key: "suelog",
        source_app: "suelog",
        activity_type: "activity_api_diagnostic",
        source_type: "diagnostic",
        source_id: "suelog-#{Time.current.to_i}",
        resource_type: "Diagnostic",
        title: "吸えログActivity API E2E診断",
        summary: "吸えログからAICOOへのread-safe接続診断",
        occurred_at: Time.current.iso8601,
        callback_model: "Diagnostic",
        callback_registered: false,
        callback_called: false,
        record_saved: false,
        metadata: {
          diagnostic: true,
          source: "aicoo:diagnose_suelog_activity_api"
        }
      )
    end

    def build_summary(configuration, callback_status, events, probe_result)
      reasons = events.filter_map { |event| event["skip_reason"].presence }.tally
      {
        shop_record_count: Shop.count,
        article_record_count: Article.count,
        callback_registered_count: callback_status.values.sum { |status| status[:registered].size },
        callback_missing_count: callback_status.values.sum { |status| status[:missing].size },
        callback_called_count: events.count { |event| event["callback_called"] },
        activity_api_client_called_count: events.count { |event| event["activity_api_client_called"] },
        request_sent_count: events.count { |event| event["request_sent"] },
        http_success_count: events.count { |event| event["ok"] },
        http_failure_count: events.count { |event| event["request_sent"] && !event["ok"] },
        business_activity_log_created_count: events.count { |event| event["business_activity_log_created"] },
        reason_counts: reasons,
        api_url_configured: configuration[:api_url_configured],
        token_configured: configuration[:token_configured],
        logging_enabled: configuration[:enabled],
        probe_ok: probe_result&.dig(:ok)
      }
    end

    def print_configuration(configuration)
      io.puts "mode=#{send_probe ? 'send_probe' : 'diagnostic'}"
      io.puts "activity_logging_enabled=#{configuration[:enabled]}"
      io.puts "aicoo_api_url=#{configuration[:api_url].presence || '(blank)'}"
      io.puts "aicoo_api_url_configured=#{configuration[:api_url_configured]}"
      io.puts "aicoo_activity_api_token_configured=#{configuration[:token_configured]}"
      io.puts "aicoo_activity_api_token_source=#{configuration[:token_source].presence || '(none)'}"
      io.puts "business_key=#{configuration[:business_key]}"
    end

    def print_callbacks(callback_status)
      callback_status.each do |model, status|
        io.puts(
          "model=#{model} callback_registered=#{status[:missing].empty?} " \
          "registered_callbacks=#{status[:registered].join(',')} " \
          "missing_callbacks=#{status[:missing].join(',')}"
        )
      end
    end

    def print_events(events)
      events.each do |event|
        io.puts [
          "event_type=#{display(event['event_type'])}",
          "model=#{display(event['model'])}",
          "source_id=#{display(event['source_id'])}",
          "record_saved=#{display(event['record_saved'])}",
          "callback_registered=#{display(event['callback_registered'])}",
          "callback_called=#{display(event['callback_called'])}",
          "activity_api_client_called=#{display(event['activity_api_client_called'])}",
          "request_created=#{display(event['request_created'])}",
          "request_sent=#{display(event['request_sent'])}",
          "response_status=#{display(event['response_status'])}",
          "response_body=#{display(event['response_body'])}",
          "retry_count=#{display(event['retry_count'])}",
          "business_activity_log_created=#{display(event['business_activity_log_created'])}",
          "skip_reason=#{display(event['skip_reason'])}",
          "exception=#{display(event['exception'])}"
        ].join(" ")
      end
    end

    def print_probe(probe_result)
      io.puts "probe_request_sent=#{probe_result[:request_sent]}"
      io.puts "probe_response_status=#{display(probe_result[:status])}"
      io.puts "probe_response_body=#{display(probe_result[:response_body])}"
      io.puts "probe_business_activity_log_created=#{probe_result[:business_activity_log_created]}"
      io.puts "probe_business_activity_log_id=#{display(probe_result[:business_activity_log_id])}"
      io.puts "probe_skip_reason=#{display(probe_result[:reason])}"
    end

    def print_summary(summary)
      summary.each do |key, value|
        rendered = value.is_a?(Hash) ? value.map { |reason, count| "#{reason}:#{count}" }.join(",") : value
        io.puts "#{key}=#{rendered}"
      end
    end

    def display(value)
      value.nil? || value == "" ? "(none)" : value.to_s.gsub(/\s+/, " ").truncate(500)
    end
  end
end
