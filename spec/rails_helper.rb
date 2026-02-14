# frozen_string_literal: true

# spec/rails_helper.rb
#
# Loads the Rails environment and configures RSpec for Rails-specific helpers.
# This file is intended to be required by specs that need full Rails integration.
#
# Usage:
#   require 'rails_helper'  # from specs that need Rails (models/controllers/jobs/etc.)
#

ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../config/environment', __dir__)

# Prevent running specs if the Rails environment is production
abort("The Rails environment is running in production mode!") if defined?(Rails) && Rails.env.production?

require 'rspec/rails'

# Require supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
support_dir = File.expand_path('support', __dir__)
if Dir.exist?(support_dir)
  Dir[File.join(support_dir, '**', '*.rb')].sort.each { |f| require f }
end

# Ensure migrations are applied to the test database before running specs.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  warn e.message
  raise
end

RSpec.configure do |config|
  # Use the spec helper for base config (spec_helper.rb).
  # Infer spec type from file location (e.g., spec/models => :model)
  config.infer_spec_type_from_file_location!

  # If you're using fixtures, set the path here.
  config.fixture_path = "#{::Rails.root}/spec/fixtures" if defined?(Rails)

  # Use transactional fixtures by default for speed.
  # Tests that require non-transactional behavior (e.g., Capybara JS) can override this.
  config.use_transactional_fixtures = true if defined?(ActiveRecord::Base)

  # Filter Rails gems from backtraces to make failures easier to read.
  config.filter_rails_from_backtrace!

  # Allow focusing examples via `:focus` metadata.
  config.filter_run_when_matching :focus

  # Print the 10 slowest examples at the end of the run (helpful in CI/local dev).
  config.profile_examples = 10 if ENV['RSPEC_PROFILE']

  # Include ActiveSupport time helpers if available (useful in many specs).
  if defined?(ActiveSupport::Testing::TimeHelpers)
    config.include ActiveSupport::Testing::TimeHelpers
  end

  # Include Rails route helpers in request specs
  if defined?(Rails)
    config.include Rails.application.routes.url_helpers
  end

  # Include ActiveJob test helpers if present
  if defined?(ActiveJob::TestHelper)
    config.include ActiveJob::TestHelper
  end

  # Clean up and reset global state between examples
  config.after(:each) do
    # Reset Time.zone if examples changed it
    if defined?(Rails) && Rails.application.config.respond_to?(:time_zone)
      Time.zone = Rails.application.config.time_zone
    end
  end
end
