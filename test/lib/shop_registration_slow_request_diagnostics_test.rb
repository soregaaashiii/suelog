require "test_helper"

class ShopRegistrationSlowRequestDiagnosticsTest < ActiveSupport::TestCase
  class MemoryLogger
    attr_reader :info_lines, :warn_lines

    def initialize
      @info_lines = []
      @warn_lines = []
    end

    def info(message)
      @info_lines << message
    end

    def warn(message)
      @warn_lines << message
    end
  end

  setup do
    @logger = MemoryLogger.new
    ShopRegistrationSlowRequestDiagnostics.logger = @logger
    ShopRegistrationSlowRequestDiagnostics.postgres_snapshotter = -> { { skipped: "test" } }
  end

  teardown do
    ShopRegistrationSlowRequestDiagnostics.logger = Rails.logger
    ShopRegistrationSlowRequestDiagnostics.postgres_snapshotter = nil
    ENV.delete("SHOP_REGISTRATION_SLOW_REQUEST_MS")
  end

  test "targets only the shop import flow and normalizes record ids" do
    assert ShopRegistrationSlowRequestDiagnostics.target_request?(rack_env("POST", "/panel_8m4k/shop_import"))
    assert ShopRegistrationSlowRequestDiagnostics.target_request?(rack_env("POST", "/panel_8m4k/shop_import/preview"))
    assert ShopRegistrationSlowRequestDiagnostics.target_request?(rack_env("GET", "/panel_8m4k/shop_import/new"))
    assert ShopRegistrationSlowRequestDiagnostics.target_request?(rack_env("PATCH", "/panel_8m4k/shops/123"))
    refute ShopRegistrationSlowRequestDiagnostics.target_request?(rack_env("GET", "/shops/123"))
    assert_equal "/panel_8m4k/shops/:id/edit",
                 ShopRegistrationSlowRequestDiagnostics.normalized_path("/panel_8m4k/shops/123/edit")
  end

  test "does not log a request below the slow threshold" do
    ENV["SHOP_REGISTRATION_SLOW_REQUEST_MS"] = "60000"
    response = middleware.call(rack_env("GET", "/panel_8m4k/shop_import/new"))

    assert_equal 200, response.first
    assert_empty @logger.info_lines
  end

  test "logs only safe diagnostics for a slow request" do
    ENV["SHOP_REGISTRATION_SLOW_REQUEST_MS"] = "0"
    secret = "private-shop-and-phone-09012345678"
    app = lambda do |_env|
      ActiveSupport::Notifications.instrument(
        "sql.active_record",
        name: "Shop Load",
        sql: "SELECT * FROM shops WHERE phone = '#{secret}'",
        cached: false
      )
      [ 200, { "content-type" => "text/plain" }, [ "ok" ] ]
    end

    response = ShopRegistrationSlowRequestDiagnostics::Middleware.new(app).call(
      rack_env("POST", "/panel_8m4k/shop_import")
    )

    assert_equal 200, response.first
    assert_equal 1, @logger.info_lines.size
    refute_includes @logger.info_lines.first, secret

    payload = JSON.parse(@logger.info_lines.first.delete_prefix("#{ShopRegistrationSlowRequestDiagnostics::PREFIX} "))
    assert_equal "/panel_8m4k/shop_import", payload.fetch("path")
    assert_equal 1, payload.fetch("sql_count")
    assert_equal "shops", payload.fetch("sql_top").first.fetch("category")
    assert_equal({ "skipped" => "test" }, payload.dig("postgres", "postgres"))
  end

  test "does not treat an unrelated admin shop update as the import flow" do
    ENV["SHOP_REGISTRATION_SLOW_REQUEST_MS"] = "0"
    env = rack_env("PATCH", "/panel_8m4k/shops/123")
    env["action_dispatch.request.parameters"] = { "from" => "admin" }

    middleware.call(env)

    assert_empty @logger.info_lines
  end

  test "includes proxy queue time in the slow request threshold" do
    ENV["SHOP_REGISTRATION_SLOW_REQUEST_MS"] = "3000"
    env = rack_env("GET", "/panel_8m4k/shop_import/new")
    env["HTTP_X_REQUEST_START"] = "t=#{Time.now.to_f - 4}"

    middleware.call(env)

    assert_equal 1, @logger.info_lines.size
    payload = JSON.parse(@logger.info_lines.first.delete_prefix("#{ShopRegistrationSlowRequestDiagnostics::PREFIX} "))
    assert_operator payload.fetch("proxy_queue_ms"), :>=, 3_000
    assert_equal "after_queue", payload.dig("postgres", "trigger")
  end

  test "labels recommendation candidate SQL separately from shops other" do
    ENV["SHOP_REGISTRATION_SLOW_REQUEST_MS"] = "0"
    app = lambda do |_env|
      ActiveSupport::Notifications.instrument(
        "sql.active_record",
        name: "Shop Load",
        sql: "SELECT shops.id FROM shops /* shop_recommendations_base_candidates */",
        cached: false
      )
      [ 200, { "content-type" => "text/plain" }, [ "ok" ] ]
    end

    ShopRegistrationSlowRequestDiagnostics::Middleware.new(app).call(
      rack_env("GET", "/panel_8m4k/shop_import/new")
    )

    payload = JSON.parse(@logger.info_lines.first.delete_prefix("#{ShopRegistrationSlowRequestDiagnostics::PREFIX} "))
    assert_equal "recommendation_base_candidates", payload.fetch("sql_top").first.fetch("category")
  end

  private

  def middleware
    @middleware ||= ShopRegistrationSlowRequestDiagnostics::Middleware.new(
      ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] }
    )
  end

  def rack_env(method, path)
    {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "QUERY_STRING" => "",
      "action_dispatch.request_id" => "test-request-id"
    }
  end
end
