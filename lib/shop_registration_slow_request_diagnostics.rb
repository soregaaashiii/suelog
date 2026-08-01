# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "concurrent/scheduled_task"

module ShopRegistrationSlowRequestDiagnostics
  PREFIX = "[ShopRegistrationSlowRequest]"
  THREAD_KEY = :shop_registration_slow_request_tracker
  DEFAULT_THRESHOLD_MS = 3_000.0

  class << self
    attr_writer :logger, :postgres_snapshotter

    def install!
      return if @installed

      install_notification_subscribers
      install_connection_checkout_instrumentation
      install_net_http_instrumentation
      @installed = true
    end

    def current
      ActiveSupport::IsolatedExecutionState[THREAD_KEY]
    end

    def with_tracker(tracker)
      previous = current
      ActiveSupport::IsolatedExecutionState[THREAD_KEY] = tracker
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[THREAD_KEY] = previous
    end

    def measure(name)
      tracker = current
      return yield unless tracker

      tracker.measure(name) { yield }
    end

    def measure_db_checkout
      tracker = current
      return yield unless tracker

      tracker.measure_db_checkout { yield }
    end

    def measure_external_http(http)
      tracker = current
      return yield unless tracker

      tracker.measure_external_http(http) { yield }
    end

    def target_request?(env)
      method = env["REQUEST_METHOD"].to_s
      path = env["PATH_INFO"].to_s

      return true if method == "GET" && path == "/panel_8m4k/shop_import/new"
      return true if method == "POST" && path == "/panel_8m4k/shop_import/preview"
      return true if method == "POST" && path == "/panel_8m4k/shop_import"
      return true if method == "GET" && path.match?(%r{\A/panel_8m4k/shops/\d+/edit\z})

      %w[PATCH PUT].include?(method) && path.match?(%r{\A/panel_8m4k/shops/\d+\z})
    end

    def registration_flow_request?(env)
      path = env["PATH_INFO"].to_s
      return true if path.start_with?("/panel_8m4k/shop_import")

      request_parameters = env["action_dispatch.request.parameters"] || {}
      request_parameters["from"].to_s == "shop_import"
    end

    def normalized_path(path)
      path.to_s.gsub(%r{\A/panel_8m4k/shops/\d+}, "/panel_8m4k/shops/:id")
    end

    def logger
      @logger || Rails.logger
    end

    def postgres_snapshotter
      @postgres_snapshotter || PostgresSnapshot.method(:capture)
    end

    private

    def install_notification_subscribers
      ActiveSupport::Notifications.monotonic_subscribe("start_processing.action_controller") do |_name, _start, _finish, _id, payload|
        current&.controller_started(payload)
      end
      ActiveSupport::Notifications.monotonic_subscribe("process_action.action_controller") do |_name, start, finish, _id, payload|
        current&.controller_finished((finish - start) * 1_000, payload)
      end
      ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") do |_name, start, finish, _id, payload|
        current&.record_sql((finish - start) * 1_000, payload)
      end
      ActiveSupport::Notifications.monotonic_subscribe("instantiation.active_record") do |_name, _start, _finish, _id, payload|
        current&.record_instantiation(payload)
      end
      ActiveSupport::Notifications.monotonic_subscribe("render_partial.action_view") do
        current&.record_partial
      end
      ActiveSupport::Notifications.monotonic_subscribe("perform_start.active_job") do |_name, _start, _finish, _id, payload|
        ActiveJobs.started(payload[:job])
      end
      ActiveSupport::Notifications.monotonic_subscribe("perform.active_job") do |_name, _start, _finish, _id, payload|
        ActiveJobs.finished(payload[:job])
      end
    end

    def install_connection_checkout_instrumentation
      pool_class = ActiveRecord::ConnectionAdapters::ConnectionPool
      return if pool_class.ancestors.include?(ConnectionPoolInstrumentation)

      pool_class.prepend(ConnectionPoolInstrumentation)
    end

    def install_net_http_instrumentation
      return if Net::HTTP.ancestors.include?(NetHttpInstrumentation)

      Net::HTTP.prepend(NetHttpInstrumentation)
    end
  end

  module ConnectionPoolInstrumentation
    private

    def acquire_connection(checkout_timeout)
      ShopRegistrationSlowRequestDiagnostics.measure_db_checkout { super }
    end
  end

  module NetHttpInstrumentation
    def request(...)
      ShopRegistrationSlowRequestDiagnostics.measure_external_http(self) { super }
    end
  end

  module ActiveJobs
    class << self
      def started(job)
        return unless job

        mutex.synchronize { active[job.job_id.to_s] = job.class.name }
      end

      def finished(job)
        return unless job

        mutex.synchronize { active.delete(job.job_id.to_s) }
      end

      def snapshot
        mutex.synchronize do
          classes = active.values.tally.sort.to_h
          { active_count: active.size, classes: }
        end
      end

      private

      def active
        @active ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end

  class Tracker
    attr_reader :started_monotonic

    def initialize(env)
      @env = env
      @started_monotonic = monotonic
      @started_at = Time.now.utc
      @gc_started = gc_snapshot
      @rss_started_mb = current_rss_mb
      @phases = Hash.new { |hash, key| hash[key] = { count: 0, total_ms: 0.0 } }
      @sql_groups = {}
      @sql_total_ms = 0.0
      @sql_count = 0
      @checkout_count = 0
      @checkout_total_ms = 0.0
      @checkout_max_ms = 0.0
      @external_http_count = 0
      @external_http_total_ms = 0.0
      @external_http_groups = Hash.new { |hash, key| hash[key] = { count: 0, total_ms: 0.0 } }
      @instantiations = 0
      @partial_count = 0
      @controller_started_at = nil
      @runtime_snapshot_mutex = Mutex.new
      @runtime_snapshot = nil
      @runtime_start = runtime_state
    end

    def measure(name)
      started = monotonic
      yield
    ensure
      record_duration(@phases, name, elapsed_ms(started)) if started
    end

    def measure_db_checkout
      started = monotonic
      yield
    ensure
      if started
        duration = elapsed_ms(started)
        @checkout_count += 1
        @checkout_total_ms += duration
        @checkout_max_ms = [ @checkout_max_ms, duration ].max
      end
    end

    def measure_external_http(http)
      started = monotonic
      yield
    ensure
      if started
        duration = elapsed_ms(started)
        category = external_category(http)
        @external_http_count += 1
        @external_http_total_ms += duration
        record_duration(@external_http_groups, category, duration)
      end
    end

    def controller_started(payload)
      @controller_started_at ||= monotonic
      @controller = payload[:controller].to_s
      @action = payload[:action].to_s
    end

    def controller_finished(duration_ms, payload)
      @controller_ms = duration_ms
      @view_ms = payload[:view_runtime]&.to_f
      @status = payload[:status]
    end

    def record_sql(duration_ms, payload)
      return if payload[:name].to_s == "SCHEMA"

      sql = payload[:sql].to_s
      return if transaction_sql?(sql)

      @sql_count += 1
      @sql_total_ms += duration_ms
      key = [ sql_fingerprint(sql), sql_operation(sql), sql_category(sql), payload[:name].to_s ].join(":")
      row = (@sql_groups[key] ||= {
        fingerprint: sql_fingerprint(sql),
        operation: sql_operation(sql),
        category: sql_category(sql),
        query_name: payload[:name].to_s,
        count: 0,
        total_ms: 0.0,
        max_ms: 0.0
      })
      row[:count] += 1
      row[:total_ms] += duration_ms
      row[:max_ms] = [ row[:max_ms], duration_ms ].max
    end

    def record_instantiation(payload)
      @instantiations += payload[:record_count].to_i
    end

    def record_partial
      @partial_count += 1
    end

    def finish!(status:)
      @finished_monotonic = monotonic
      @status ||= status
      @snapshot_task&.cancel
      @gc_finished = gc_snapshot
      @rss_finished_mb = current_rss_mb
      @runtime_finish = runtime_state
      self
    end

    def slow?
      observed_request_ms >= threshold_ms
    end

    def start_slow_snapshot_timer!
      queue_ms = proxy_queue_ms.to_f
      if queue_ms >= threshold_ms
        capture_runtime_snapshot!("after_queue")
        return
      end

      delay_seconds = (threshold_ms - queue_ms) / 1_000.0
      @snapshot_task = Concurrent::ScheduledTask.execute(delay_seconds) do
        capture_runtime_snapshot!("threshold_reached") unless @finished_monotonic
      end
    end

    def runtime_snapshot
      @runtime_snapshot_mutex.synchronize { @runtime_snapshot }
    end

    def log!(postgres_snapshot:)
      payload = summary.merge(postgres: postgres_snapshot)
      ShopRegistrationSlowRequestDiagnostics.logger.info("#{PREFIX} #{payload.to_json}")
    rescue StandardError => error
      ShopRegistrationSlowRequestDiagnostics.logger.warn(
        "#{PREFIX} log_failed error_class=#{error.class.name}"
      )
    end

    def summary
      {
        timestamp: @started_at.iso8601(6),
        request_id: request_id,
        method: @env["REQUEST_METHOD"].to_s,
        path: ShopRegistrationSlowRequestDiagnostics.normalized_path(@env["PATH_INFO"]),
        status: @status,
        total_rack_ms: round(total_rack_ms),
        estimated_http_ms: round(total_rack_ms + proxy_queue_ms.to_f),
        proxy_queue_ms: proxy_queue_ms,
        rack_to_controller_ms: rack_to_controller_ms,
        controller_ms: round_or_nil(@controller_ms),
        view_ms: round_or_nil(@view_ms),
        active_record_ms: round(@sql_total_ms),
        sql_count: @sql_count,
        sql_top: sql_top,
        db_checkout_count: @checkout_count,
        db_checkout_total_ms: round(@checkout_total_ms),
        db_checkout_max_ms: round(@checkout_max_ms),
        gc_ms: gc_delta(:time),
        gc_count: gc_delta(:count),
        allocations: gc_delta(:total_allocated_objects),
        heap_live_slots_delta: gc_delta(:heap_live_slots),
        rss_start_mb: @rss_started_mb,
        rss_finish_mb: @rss_finished_mb,
        rss_delta_mb: rss_delta_mb,
        active_record_instantiations: @instantiations,
        partial_count: @partial_count,
        phases: duration_rows(@phases),
        external_http_count: @external_http_count,
        external_http_ms: round(@external_http_total_ms),
        external_http: duration_rows(@external_http_groups),
        runtime_start: @runtime_start,
        runtime_finish: @runtime_finish
      }
    end

    private

    def threshold_ms
      ENV.fetch("SHOP_REGISTRATION_SLOW_REQUEST_MS", DEFAULT_THRESHOLD_MS).to_f
    end

    def request_id
      @env["action_dispatch.request_id"].presence || @env["HTTP_X_REQUEST_ID"].presence
    end

    def proxy_queue_ms
      raw = @env["HTTP_X_REQUEST_START"].presence || @env["HTTP_X_QUEUE_START"].presence
      return if raw.blank?

      value = raw.to_s.sub(/\At=/, "").to_f
      started_ms = if value > 1_000_000_000_000_000
        value / 1_000
      elsif value > 1_000_000_000_000
        value
      else
        value * 1_000
      end
      result = (@started_at.to_f * 1_000) - started_ms
      result.negative? ? nil : round(result)
    rescue StandardError
      nil
    end

    def rack_to_controller_ms
      return unless @controller_started_at

      round((@controller_started_at - started_monotonic) * 1_000)
    end

    def sql_top
      @sql_groups.values.sort_by { |row| -row[:total_ms] }.first(10).map do |row|
        row.merge(
          total_ms: round(row[:total_ms]),
          average_ms: round(row[:total_ms] / row[:count]),
          max_ms: round(row[:max_ms])
        )
      end
    end

    def sql_fingerprint(sql)
      normalized = sql
        .gsub(%r{/\*.*?\*/}m, " ")
        .gsub(/'(?:''|[^'])*'/m, "?")
        .gsub(/\$\d+/, "?")
        .gsub(/\b\d+(?:\.\d+)?\b/, "?")
        .squish
      Digest::SHA256.hexdigest(normalized).first(16)
    end

    def sql_operation(sql)
      sql.lstrip[/\A(?:SELECT|INSERT|UPDATE|DELETE)/i].to_s.upcase.presence || "OTHER"
    end

    def sql_category(sql)
      return "popular_shops" if sql.match?(/shop_clicks/i) && sql.match?(/COUNT\s*\(/i)
      return "shop_registration_duplicates" if sql.match?(/duplicate_normalized_(?:name|address)/i)
      return "shops" if sql.match?(/\bshops\b/i)
      return "page_views" if sql.match?(/\bpage_views\b/i)
      return "solid_cache" if sql.match?(/\bsolid_cache_entries\b/i)
      return "active_storage" if sql.match?(/\bactive_storage_/i)
      return "reviews" if sql.match?(/\breviews\b/i)

      "other"
    end

    def transaction_sql?(sql)
      sql.match?(/\A\s*(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)\b/i)
    end

    def external_category(http)
      host = http.respond_to?(:address) ? http.address.to_s.downcase : ""
      return "google_geocoder" if host.include?("google")
      return "aicoo_activity" if host.include?("aicoo")

      "other"
    end

    def duration_rows(collection)
      collection.sort_by { |_name, row| -row[:total_ms] }.to_h do |name, row|
        [ name, { count: row[:count], total_ms: round(row[:total_ms]) } ]
      end
    end

    def record_duration(collection, name, duration)
      row = collection[name.to_s]
      row[:count] += 1
      row[:total_ms] += duration
    end

    def gc_snapshot
      GC.stat.slice(:time, :count, :total_allocated_objects, :heap_live_slots)
    rescue StandardError
      {}
    end

    def gc_delta(key)
      return unless @gc_started.key?(key) && @gc_finished&.key?(key)

      @gc_finished[key] - @gc_started[key]
    end

    def current_rss_mb
      return unless File.exist?("/proc/self/status")

      line = File.foreach("/proc/self/status").find { |entry| entry.start_with?("VmRSS:") }
      value = line.to_s[/\d+/]&.to_i
      round(value.to_f / 1_024) if value
    rescue StandardError
      nil
    end

    def rss_delta_mb
      return if @rss_started_mb.nil? || @rss_finished_mb.nil?

      round(@rss_finished_mb - @rss_started_mb)
    end

    def puma_stats
      return unless defined?(Puma) && Puma.respond_to?(:stats)

      raw = JSON.parse(Puma.stats.to_s)
      raw.slice("backlog", "running", "pool_capacity", "max_threads", "busy_threads", "requests_count")
    rescue StandardError
      nil
    end

    def db_pool_stats
      ActiveRecord::Base.connection_handler.connection_pool_list(:all).map do |pool|
        {
          role: pool.role,
          shard: pool.shard,
          config: pool.db_config.name,
          stats: pool.stat.slice(:size, :connections, :busy, :dead, :idle, :waiting, :checkout_timeout)
        }
      end
    rescue StandardError
      []
    end

    def background_job_stats
      {
        queue_adapter: ActiveJob::Base.queue_adapter.class.name,
        active: ActiveJobs.snapshot,
        solid_queue_in_puma: ENV["SOLID_QUEUE_IN_PUMA"].to_s == "true"
      }
    rescue StandardError
      nil
    end

    def total_rack_ms
      ((@finished_monotonic || monotonic) - started_monotonic) * 1_000
    end

    def observed_request_ms
      total_rack_ms + proxy_queue_ms.to_f
    end

    def runtime_state
      {
        puma: puma_stats,
        db_pools: db_pool_stats,
        background_jobs: background_job_stats
      }
    end

    def capture_runtime_snapshot!(trigger)
      snapshot = {
        trigger:,
        observed_request_ms: round(observed_request_ms),
        runtime: runtime_state,
        postgres: ShopRegistrationSlowRequestDiagnostics.postgres_snapshotter.call
      }
      @runtime_snapshot_mutex.synchronize { @runtime_snapshot ||= snapshot }
    rescue StandardError => error
      @runtime_snapshot_mutex.synchronize do
        @runtime_snapshot ||= { trigger:, error_class: error.class.name }
      end
    end

    def elapsed_ms(started)
      (monotonic - started) * 1_000
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def round(value)
      value.to_f.round(2)
    end

    def round_or_nil(value)
      value.nil? ? nil : round(value)
    end
  end

  module PostgresSnapshot
    class << self
      def capture
        pool = ActiveRecord::Base.connection_pool
        connection = pool.checkout(0.05)
        return { skipped: "non_postgresql" } unless connection.adapter_name.match?(/postgres/i)

        {
          captured_at: Time.now.utc.iso8601(6),
          activity: connection.select_all(activity_sql).to_a,
          blocking: connection.select_all(blocking_sql).to_a,
          autovacuum: connection.select_all(autovacuum_sql).to_a,
          table_health: connection.select_all(table_health_sql).to_a
        }
      rescue ActiveRecord::ConnectionTimeoutError
        { skipped: "primary_pool_busy" }
      rescue StandardError => error
        { skipped: "snapshot_failed", error_class: error.class.name }
      ensure
        pool&.checkin(connection) if connection
      end

      private

      def activity_sql
        <<~SQL.squish
          SELECT query_id,
                 application_name,
                 state,
                 wait_event_type,
                 wait_event,
                 query_start,
                 xact_start,
                 ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - query_start))::numeric, 3) AS query_seconds,
                 ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - xact_start))::numeric, 3) AS transaction_seconds,
                 CASE
                   WHEN query ILIKE '%shop_clicks%' AND query ILIKE '%COUNT(%' THEN 'popular_shops_group_count'
                   WHEN query ILIKE '%duplicate_normalized_name%' OR query ILIKE '%duplicate_normalized_address%' THEN 'shop_registration_duplicates'
                   WHEN query ILIKE '%shops%' THEN 'shops_other'
                   WHEN query ILIKE '%page_views%' THEN 'page_views'
                   WHEN query ILIKE '%solid_cache_entries%' THEN 'solid_cache'
                   WHEN query ILIKE '%autovacuum%' THEN 'autovacuum'
                   ELSE 'other'
                 END AS safe_category
          FROM pg_stat_activity
          WHERE datname = current_database()
            AND pid <> pg_backend_pid()
            AND state <> 'idle'
          ORDER BY query_start
        SQL
      end

      def blocking_sql
        <<~SQL.squish
          SELECT blocked.pid AS blocked_pid,
                 blocker.pid AS blocking_pid,
                 blocked.wait_event_type,
                 blocked.wait_event,
                 ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - blocked.query_start))::numeric, 3) AS blocked_seconds
          FROM pg_stat_activity blocked
          CROSS JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) blocking_pid
          JOIN pg_stat_activity blocker ON blocker.pid = blocking_pid
          WHERE blocked.datname = current_database()
        SQL
      end

      def autovacuum_sql
        <<~SQL.squish
          SELECT relid::regclass::text AS relation, phase
          FROM pg_stat_progress_vacuum
        SQL
      end

      def table_health_sql
        <<~SQL.squish
          SELECT relname,
                 n_live_tup,
                 n_dead_tup,
                 last_autovacuum,
                 last_autoanalyze
          FROM pg_stat_user_tables
          WHERE relname IN ('shops', 'shop_clicks', 'page_views')
          ORDER BY relname
        SQL
      end
    end
  end

  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless ShopRegistrationSlowRequestDiagnostics.target_request?(env)

      tracker = Tracker.new(env)
      tracker.start_slow_snapshot_timer!
      result = ShopRegistrationSlowRequestDiagnostics.with_tracker(tracker) { @app.call(env) }
      tracker.finish!(status: result.first)
      log_if_slow(tracker, env)
      result
    rescue Exception # rubocop:disable Lint/RescueException
      tracker&.finish!(status: 500)
      log_if_slow(tracker, env) if tracker
      raise
    end

    private

    def log_if_slow(tracker, env)
      return unless tracker.slow?
      return unless ShopRegistrationSlowRequestDiagnostics.registration_flow_request?(env)

      snapshot = tracker.runtime_snapshot || {
        trigger: "after_response",
        postgres: ShopRegistrationSlowRequestDiagnostics.postgres_snapshotter.call
      }
      tracker.log!(postgres_snapshot: snapshot)
    end
  end
end
