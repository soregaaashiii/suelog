require "test_helper"

class AicooActivityDeliveryJobTest < ActiveJob::TestCase
  test "delivers the queued activity payload" do
    calls = []
    original = AicooActivityLogger.method(:log)
    AicooActivityLogger.define_singleton_method(:log) do |**attributes|
      calls << attributes
      { ok: true, status: 201, retry_count: 0 }
    end

    AicooActivityDeliveryJob.perform_now(
      "activity_type" => "data_added",
      "source_type" => "shop",
      "source_id" => 123
    )

    assert_equal 1, calls.size
    assert_equal "data_added", calls.first[:activity_type]
    assert_equal "shop", calls.first[:source_type]
    assert_equal 123, calls.first[:source_id]
  ensure
    AicooActivityLogger.define_singleton_method(:log, original)
  end
end
