
Clio::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb

  # less logging
  config.log_level = :warn

  config.cache_classes = true

  # Log error messages when you accidentally call methods on nil.
  config.whiny_nils = true

  # Show full error reports and disable caching
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Don't care if the mailer can't send
  config.action_mailer.raise_delivery_errors = true
  config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect'

config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  :address => "localhost",
  :domain => "rossini.cc.columbia.edu",
  :port => "25"
}

  # Print deprecation notices to the Rails logger
  config.active_support.deprecation = :log
  config.assets.precompile += %w{flot/excanvas.min.js}

  config.assets.compress = true
  config.assets.compile = false
  config.assets.digest = true
  # Only use best-standards-support built into browsers
  config.action_dispatch.best_standards_support = :builtin
end


Clio::Application.config.middleware.use ExceptionNotifier,
   :email_prefix => "[Clio Test] ",
   :sender_address => %{"notifier" <spectrum@libraries.cul.columbia.edu>},
   :exception_recipients => %w{marquis@columbia.edu},
   :ignore_crawlers => %w{Googlebot bingbot}
