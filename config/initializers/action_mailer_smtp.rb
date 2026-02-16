# frozen_string_literal: true
#
# ActionMailer SMTP configuration initializer
#
# Purpose:
# - Configure ActionMailer to send email via SMTP using environment variables.
# - Avoid committing any sensitive credentials to source control; use env vars,
#   Docker secrets, or your orchestration provider's secret management.
#
# Recommended environment variables (examples):
# - SMTP_ADDRESS=smtp.gmail.com
# - SMTP_PORT=587
# - SMTP_DOMAIN=yourdomain.com
# - SMTP_USER=your@yourdomain.com
# - SMTP_PASSWORD=<app-password-or-smtp-password-or-api-key>
# - SMTP_AUTHENTICATION=plain          # usually 'plain' or 'login'
# - SMTP_ENABLE_STARTTLS_AUTO=true
# - SMTP_OPENSSL_VERIFY_MODE=''        # e.g. '', or 'none' (avoid in prod unless necessary)
# - SMTP_ENABLED=true                  # set to 'false' to disable actual delivery (useful in CI)
# - DEFAULT_FROM_EMAIL=no-reply@yourdomain.com
# - MAIL_DELIVERY_METHOD=smtp         # override if you want :sendmail, :test, etc.
# - USE_LETTER_OPENER=true            # in development, set to open mails in the browser (optional)
#
# Notes:
# - For Google Workspace accounts, prefer creating an App Password (if 2FA enabled)
#   or configure the SMTP relay in the Google Admin console (recommended for servers).
# - Do NOT store credentials in the repo. Use environment variables or secrets.
# - If you wish to use a transactional provider (SendGrid/Postmark/Mailgun) you can
#   point these SMTP settings to the provider's SMTP host or switch to an API-based
#   integration instead.
#
Rails.application.configure do
  # Allow overriding delivery method via env (useful for tests or special setups)
  delivery_method = ENV.fetch('MAIL_DELIVERY_METHOD', 'smtp').to_sym

  # Support toggling real delivery (useful for CI/test environments)
  smtp_enabled = ENV.fetch('SMTP_ENABLED', 'true').downcase != 'false'

  # Helper to parse boolean-ish env vars
  env_true = ->(val) do
    case val.to_s.strip.downcase
    when '1', 'true', 'yes', 'on' then true
    else false
    end
  end

  # In development you might want to use letter_opener; respect an env toggle.
  use_letter_opener = env_true.call(ENV['USE_LETTER_OPENER']) && Rails.env.development?

  if use_letter_opener
    # If you want to use letter_opener in development, set USE_LETTER_OPENER=true.
    # Note: this initializer does not add the gem for you; ensure letter_opener is in your Gemfile in :development.
    config.action_mailer.delivery_method = :letter_opener
    config.action_mailer.perform_deliveries = true
  else
    config.action_mailer.delivery_method = delivery_method
    config.action_mailer.perform_deliveries = smtp_enabled
  end

  # Default from address: prefer explicit ENV, fallback to OrderExport config if present, then a safe default.
  default_from = if ENV['DEFAULT_FROM_EMAIL'].present?
                   ENV['DEFAULT_FROM_EMAIL']
                 elsif defined?(OrderExport) && defined?(OrderExport::Config) && OrderExport::Config.respond_to?(:from_email)
                   OrderExport::Config.from_email
                 else
                   'no-reply@example.com'
                 end

  # Configure SMTP settings only when using SMTP delivery.
  if config.action_mailer.delivery_method == :smtp
    smtp_address = ENV.fetch('SMTP_ADDRESS', 'smtp.gmail.com')
    smtp_port    = ENV.fetch('SMTP_PORT', '587').to_i
    smtp_domain  = ENV.fetch('SMTP_DOMAIN') { ENV['MAIL_DOMAIN'] || smtp_address }
    smtp_user    = ENV['SMTP_USER']
    smtp_pass    = ENV['SMTP_PASSWORD']
    smtp_auth    = ENV.fetch('SMTP_AUTHENTICATION', 'plain').to_sym
    starttls     = env_true.call(ENV.fetch('SMTP_ENABLE_STARTTLS_AUTO', 'true'))
    openssl_mode = ENV['SMTP_OPENSSL_VERIFY_MODE'].presence

    config.action_mailer.smtp_settings = {
      address:              smtp_address,
      port:                 smtp_port,
      domain:               smtp_domain,
      user_name:            smtp_user,
      password:             smtp_pass,
      authentication:       smtp_auth,
      enable_starttls_auto: starttls
    }.tap do |h|
      # Only include openssl_verify_mode when explicitly set (avoid insecure defaults)
      h[:openssl_verify_mode] = openssl_mode if openssl_mode.present?
    end

    # In production, it's helpful to log when SMTP credentials are missing (but don't log secrets).
    if Rails.env.production?
      if smtp_user.blank? || smtp_pass.blank?
        Rails.logger.warn("[action_mailer_smtp] SMTP_USER or SMTP_PASSWORD not configured; emails may not be delivered in production.")
      end
    end
  end

  # Apply default "from" for mailers
  config.action_mailer.default_options = {
    from: default_from
  }

  # Useful defaults for email URLs in mailers (host must be configured in env)
  # Example: MAILER_HOST=app.example.com
  mailer_host = ENV['MAILER_HOST'] || ENV['HOST'] || "localhost:#{ENV.fetch('PORT', 3000)}"
  config.action_mailer.default_url_options ||= {}
  config.action_mailer.default_url_options[:host] = mailer_host
  config.action_mailer.default_url_options[:protocol] = ENV.fetch('MAILER_PROTOCOL', Rails.env.production? ? 'https' : 'http')

  # A small helper method exposed via Rails logger to view effective SMTP status (no secrets)
  Rails.logger.info("[action_mailer_smtp] delivery_method=#{config.action_mailer.delivery_method}; perform_deliveries=#{config.action_mailer.perform_deliveries}; mailer_host=#{mailer_host}")
  if config.action_mailer.delivery_method == :smtp
    Rails.logger.info("[action_mailer_smtp] smtp.address=#{ENV['SMTP_ADDRESS'] || 'not-set'} smtp.port=#{ENV['SMTP_PORT'] || 'not-set'} smtp.domain=#{ENV['SMTP_DOMAIN'] || 'not-set'} smtp.user_present=#{ENV['SMTP_USER'].present?}")
  end
end

# Guidance for local development/testing:
#
# - Do NOT create a checked-in .env file with secrets. Your repository already ignores /.env* per .gitignore and .dockerignore.
# - For local development, create a `.env` or `.env.local` (kept out of git) with the keys above, or export env vars in your shell.
# - Example `.env` (DO NOT COMMIT):
#   SMTP_ADDRESS=smtp.gmail.com
#   SMTP_PORT=587
#   SMTP_DOMAIN=yourdomain.com
#   SMTP_USER=you@yourdomain.com
#   SMTP_PASSWORD=very-secret-app-password
#   DEFAULT_FROM_EMAIL=reports@yourdomain.com
#   ORDER_EXPORT_RECIPIENT=reports@yourdomain.com
#
# - If using Docker Compose, prefer Docker secrets or environment variables passed through your orchestrator rather than embedding credentials in checked-in files.
#
# - To test sending a real email from a console:
#   Admin::OrderExportMailer.export_email(
#     recipient: ENV['ORDER_EXPORT_RECIPIENT'] || 'you@example.com',
#     file_path: Rails.root.join('tmp','dummy.xlsx').to_s,
#     filename: 'test.xlsx',
#     scheduled_for: Time.current.utc,
#     exported_count: 1
#   ).deliver_now
#
# - For Google Workspace:
#   - If your account uses 2FA, create an App Password for "Mail" and use that as SMTP_PASSWORD.
#   - Alternatively, configure SMTP relay in Google Admin and set SMTP_ADDRESS to smtp-relay.gmail.com.
#
# - If you prefer to use a transactional provider (SendGrid, Postmark, etc.), you can set
#   SMTP_ADDRESS/SMTP_PORT and SMTP_USER/SMTP_PASSWORD per their docs, or adopt their API gem.
