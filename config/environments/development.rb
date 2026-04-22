# /Users/kawamuratakuya/dev/suelog/config/environments/development.rb
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
  config.active_storage.service = :local

  # Use MiniMagick for Active Storage variants in development.
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

  # Bullet: N+1 / eager loading issues detection in development only.
  config.after_initialize do
    if defined?(Bullet)
      Bullet.enable = true
      Bullet.alert = true
      Bullet.bullet_logger = true
      Bullet.console = true
      Bullet.rails_logger = true

      # 必要ならあとで有効化
      Bullet.add_footer = false
    end
  end
end