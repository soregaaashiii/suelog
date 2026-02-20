# config/environments/development.rb
require "active_support/core_ext/integer/time"

Rails.application.configure do
# Code is reloaded on every request.
config.enable_reloading = true

# Do not eager load code on boot.
config.eager_load = false

# Show full error reports.
config.consider_all_requests_local = true

# Enable server timing
config.server_timing = true

# Caching
if Rails.root.join("tmp/caching-dev.txt").exist?
config.action_controller.perform_caching = true
config.action_controller.enable_fragment_cache_logging = true
config.cache_store = :memory_store
config.public_file_server.headers = {
"Cache-Control" => "public, max-age=#{2.days.to_i}"
}
else
config.action_controller.perform_caching = false
config.cache_store = :null_store
end

# Store uploaded files on the local file system (see config/storage.yml for options).
# ✅ ここが重要：development は local を使う
config.active_storage.service = :local

# ✅ variant 生成をするなら、mini_magick or vips が必要
# 画像変換が入ってない環境で落ちるのを避けたいなら、ひとまず :mini_magick 推奨
config.active_storage.variant_processor = :mini_magick

# Mailer
config.action_mailer.raise_delivery_errors = false
config.action_mailer.perform_caching = false

# Deprecation
config.active_support.deprecation = :log
config.active_support.disallowed_deprecation = :raise
config.active_support.disallowed_deprecation_warnings = []

# Raises error for missing translations.
# config.i18n.raise_on_missing_translations = true

# Annotate rendered view with file names.
# config.action_view.annotate_rendered_view_with_filenames = true
end