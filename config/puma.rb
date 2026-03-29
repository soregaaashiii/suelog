# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/config/puma.rb
# frozen_string_literal: true

max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
min_threads_count = ENV.fetch("RAILS_MIN_THREADS", max_threads_count).to_i
threads min_threads_count, max_threads_count

port ENV.fetch("PORT", 3000)

environment ENV.fetch("RAILS_ENV", "development")

pidfile ENV.fetch("PIDFILE", "tmp/pids/server.pid")

# Starter 環境での不安定化切り分けのため single mode に固定
workers 0

plugin :tmp_restart