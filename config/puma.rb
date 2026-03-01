# frozen_string_literal: true

threads_count = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
threads threads_count, threads_count

port ENV.fetch("PORT", 3000)

environment ENV.fetch("RAILS_ENV", "development")

pidfile ENV.fetch("PIDFILE", "tmp/pids/server.pid")

# developmentは必ず single mode
if ENV.fetch("RAILS_ENV", "development") == "development"
workers 0
else
workers ENV.fetch("WEB_CONCURRENCY", 1).to_i
preload_app!
end

plugin :tmp_restart
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]



