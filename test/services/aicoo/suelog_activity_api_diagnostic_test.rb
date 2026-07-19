require "test_helper"
require "stringio"

module Aicoo
  class SuelogActivityApiDiagnosticTest < ActiveSupport::TestCase
    test "reports registered callbacks and recent delivery outcomes" do
      output = StringIO.new
      events = [
        {
          "event_type" => "data_added",
          "model" => "Shop",
          "callback_called" => true,
          "activity_api_client_called" => true,
          "request_sent" => true,
          "response_status" => 201,
          "ok" => true,
          "business_activity_log_created" => true
        }
      ]
      configuration = {
        enabled: true,
        api_url: "https://aicoo.example",
        api_url_configured: true,
        token_configured: true,
        token_source: "AICOO_ACTIVITY_API_TOKEN",
        business_key: "suelog"
      }

      with_replaced_method(AicooActivityLogger, :configuration, -> { configuration }) do
        with_replaced_method(AicooActivityDeliveryDiagnostics, :recent, ->(limit: nil) { events.first(limit || events.size) }) do
          result = SuelogActivityApiDiagnostic.call(io: output)

          assert_equal 0, result[:callback_missing_count]
          assert_equal 1, result[:request_sent_count]
          assert_equal 1, result[:business_activity_log_created_count]
        end
      end

      assert_includes output.string, "model=Shop callback_registered=true"
      assert_includes output.string, "model=Article callback_registered=true"
      assert_includes output.string, "response_status=201"
    end

    private

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
end
