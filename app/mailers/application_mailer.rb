class ApplicationMailer < ActionMailer::Base
  # Use configured from address if available, otherwise fall back to ENV or a sensible default.
  default from: -> {
    Rails.configuration.x.order_export&.from_email.presence ||
      ENV.fetch('DEFAULT_FROM_EMAIL', 'no-reply@example.com')
  }
  layout "mailer"
end
