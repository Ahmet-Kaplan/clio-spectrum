
Clio::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb

  # less logging
  config.log_level = :warn

  config.cache_classes = true

  # # deprecated in rails 4
  # # Log error messages when you accidentally call methods on nil.
  # config.whiny_nils = true

  # if we consider them "local" we spew errors to the browser
  config.consider_all_requests_local       = false

  # Do we want caching (page-, action-, fragment-) in this environment?
  config.action_controller.perform_caching = true

  # Cache store details - disk or memory?  How big?  (50MB?)
  # config.cache_store = :memory_store, { size: 50_000_000 }
  # Or... use redis?
  # config.cache_store = :redis_store, APP_CONFIG['redis_url']
  # Oops - can't use APP_CONFIG within environment files
  # Cheat - redundantly read app_config right here...
  ENV_CONFIG = YAML.load_file(File.expand_path('../../app_config.yml', __FILE__))[Rails.env]
  if ENV_CONFIG && ENV_CONFIG['redis_url'].present?
    config.cache_store = :redis_store, ENV_CONFIG['redis_url']
  else
    config.cache_store = :memory_store, { size: 50_000_000 }
  end

  # Don't care if the mailer can't send
  config.action_mailer.raise_delivery_errors = true
  config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect'

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: 'smtp.library.columbia.edu',
    domain: 'library.columbia.edu',
    port: '25'
  }

  # Print deprecation notices to the Rails logger
  config.active_support.deprecation = :log

  # Wait... the compress introduces Chrome Javascript-parsing error?!?!
  #   Uncaught ReferenceError: Invalid left-hand side expression in prefix operation
  # 7/29 - Chrome updated, will this work now?
  # No, not yet, leave compressed = false
  # config.assets.compress = false
  # Aha, found it!  Wrong comments in coffeescript, tripping up only Chrome.
  # Fixed.
  # config.assets.compress = true
  config.assets.compile = false
  config.assets.digest = true
  # turn off all asset logging - match CLIO Test to CLIO Prod
  config.assets.logger = nil

  # Rails 4 - these are split out
  # config.assets.css_compressor = :yui
  # This is available from sass-rails gem
  config.assets.css_compressor = :sass
  config.assets.js_compressor = :uglifier

  # turn off logging of view/parital rendering
  # - match CLIO Test to CLIO Prod
  config.action_view.logger = nil

  # Only use best-standards-support built into browsers
  config.action_dispatch.best_standards_support = :builtin

  # rails 4
  config.eager_load = true

end

# Exception Notifier - Upgrading to 4.x version
#   https://github.com/smartinez87/exception_notification/blob/master/README.md
# Clio::Application.config.middleware.use ExceptionNotifier,
#    :email_prefix => "[Clio Test] ",
#    :sender_address => %{"notifier" <spectrum-tech@libraries.cul.columbia.edu>},
#    :exception_recipients => %w{spectrum-tech@libraries.cul.columbia.edu},
#    :ignore_crawlers => %w{Googlebot bingbot}

Clio::Application.config.middleware.use ExceptionNotification::Rack,
  ignore_exceptions: ['Errno::EHOSTUNREACH'] + ExceptionNotifier.ignored_exceptions,
  ignore_crawlers: %w(Googlebot bingbot archive.org_bot),
  email: {
    email_prefix: '[Clio Test] ',
    sender_address: %("notifier" <spectrum-tech@libraries.cul.columbia.edu>),
    exception_recipients: %w(spectrum-tech@libraries.cul.columbia.edu)
  }
