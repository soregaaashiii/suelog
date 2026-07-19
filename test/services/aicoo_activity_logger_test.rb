require "test_helper"

class AicooActivityLoggerTest < ActiveSupport::TestCase
  setup do
    @previous_env = {
      "AICOO_API_URL" => ENV["AICOO_API_URL"],
      "AICOO_ACTIVITY_API_TOKEN" => ENV["AICOO_ACTIVITY_API_TOKEN"],
      "AICOO_ACTIVITY_API_KEY" => ENV["AICOO_ACTIVITY_API_KEY"],
      "AICOO_API_KEY" => ENV["AICOO_API_KEY"],
      "AICOO_ACTIVITY_LOGGING_ENABLED" => ENV["AICOO_ACTIVITY_LOGGING_ENABLED"]
    }
    ENV["AICOO_API_URL"] = "https://aicoo.example"
    ENV["AICOO_ACTIVITY_API_TOKEN"] = "token"
    ENV.delete("AICOO_ACTIVITY_API_KEY")
    ENV.delete("AICOO_API_KEY")
    ENV.delete("AICOO_ACTIVITY_LOGGING_ENABLED")
  end

  teardown do
    @previous_env.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  test "returns the created BusinessActivityLog from a successful delivery" do
    logger = AicooActivityLogger.new
    response = http_response(Net::HTTPCreated, 201, '{"ok":true,"id":123}')
    diagnostics = []

    with_replaced_method(AicooActivityDeliveryDiagnostics, :record, ->(attributes) { diagnostics << attributes }) do
      with_replaced_method(logger, :post_payload, ->(_payload) { response }) do
        result = logger.log(**activity_attributes)

        assert result[:ok]
        assert_equal 201, result[:status]
        assert result[:request_sent]
        assert result[:business_activity_log_created]
        assert_equal 123, result[:business_activity_log_id]
      end
    end

    assert_equal true, diagnostics.last[:callback_called]
    assert_equal true, diagnostics.last[:business_activity_log_created]
  end

  test "retries a retryable HTTP failure" do
    logger = AicooActivityLogger.new
    responses = [
      http_response(Net::HTTPServiceUnavailable, 503, '{"ok":false}'),
      http_response(Net::HTTPOK, 200, '{"ok":true,"id":456}')
    ]
    attempts = 0

    with_replaced_method(logger, :post_payload, ->(_payload) { attempts += 1; responses.shift }) do
      with_replaced_method(AicooActivityDeliveryDiagnostics, :record, ->(_attributes) { }) do
        result = logger.log(**activity_attributes)

        assert result[:ok]
        assert_equal 1, result[:retry_count]
      end
    end

    assert_equal 2, attempts
  end

  test "does not retry an authentication failure" do
    logger = AicooActivityLogger.new
    attempts = 0
    response = http_response(Net::HTTPUnauthorized, 401, '{"ok":false,"error":"unauthorized"}')

    with_replaced_method(logger, :post_payload, ->(_payload) { attempts += 1; response }) do
      with_replaced_method(AicooActivityDeliveryDiagnostics, :record, ->(_attributes) { }) do
        result = logger.log(**activity_attributes)

        assert_not result[:ok]
        assert_equal "http_401", result[:reason]
      end
    end

    assert_equal 1, attempts
  end

  test "records retries when a network failure exhausts delivery" do
    logger = AicooActivityLogger.new
    attempts = 0

    with_replaced_method(logger, :post_payload, lambda { |_payload|
      attempts += 1
      raise Net::ReadTimeout, "timeout"
    }) do
      with_replaced_method(AicooActivityDeliveryDiagnostics, :record, ->(_attributes) { }) do
        result = logger.log(**activity_attributes)

        assert_not result[:ok]
        assert_equal "delivery_exception", result[:reason]
        assert_equal 2, result[:retry_count]
      end
    end

    assert_equal 3, attempts
  end

  test "records missing configuration without attempting HTTP" do
    ENV.delete("AICOO_API_URL")
    logger = AicooActivityLogger.new
    diagnostics = []

    with_replaced_method(AicooActivityDeliveryDiagnostics, :record, ->(attributes) { diagnostics << attributes }) do
      result = logger.log(**activity_attributes)

      assert_not result[:ok]
      assert_equal "missing_aicoo_api_url", result[:reason]
      assert_not result[:request_sent]
    end

    assert_equal "missing_aicoo_api_url", diagnostics.last[:skip_reason]
  end

  test "uses the API key aliases accepted by AICOO" do
    ENV.delete("AICOO_ACTIVITY_API_TOKEN")
    ENV["AICOO_ACTIVITY_API_KEY"] = "fallback-token"

    configuration = AicooActivityLogger.configuration

    assert configuration[:token_configured]
    assert_equal "AICOO_ACTIVITY_API_KEY", configuration[:token_source]
  end

  private

  def activity_attributes
    {
      business_key: "suelog",
      activity_type: "data_added",
      source_type: "shop",
      source_id: 10,
      title: "店舗を追加",
      callback_model: "Shop",
      callback_registered: true,
      callback_called: true
    }
  end

  def http_response(klass, code, body)
    klass.new("1.1", code.to_s, "response").tap do |response|
      response.instance_variable_set(:@read, true)
      response.instance_variable_set(:@body, body)
    end
  end

  def with_replaced_method(target, name, replacement)
    original = target.method(name)
    target.define_singleton_method(name) do |*args, **kwargs|
      replacement.call(*args, **kwargs)
    end
    yield
  ensure
    target.define_singleton_method(name, original)
  end
end
