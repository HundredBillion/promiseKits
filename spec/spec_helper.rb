# frozen_string_literal: true
#
# This file was generated to provide a minimal, Rails-friendly RSpec configuration.
# It mirrors the style produced by `rails generate rspec:install` while remaining
# compact and safe to include in projects that may not have all optional gems.
#
# Typical usage:
#  - require 'spec_helper' from unit-level specs
#  - require 'rails_helper' from specs that need Rails integration (controllers/models/jobs/etc.)
#
# Note: If you enable coverage by setting ENV['COVERAGE'] = '1', this loader will
# attempt to require SimpleCov. If SimpleCov is not present, it will continue quietly.
begin
  if ENV['COVERAGE'].to_s.strip != '' && ENV['COVERAGE'] != '0'
    require 'simplecov'
    SimpleCov.start 'rails' if defined?(SimpleCov)
  end
rescue LoadError
  # SimpleCov not installed — ignore coverage instrumentation.
end

require 'rspec/core'

RSpec.configure do |config|
  # Use the new expect syntax only
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Configure mocks to verify doubles where possible
  config.mock_with :rspec do |m|
    m.verify_partial_doubles = true
  end

  # Disable monkey patching (must use RSpec.describe, not describe)
  config.disable_monkey_patching!

  # Print the 10 slowest examples and example groups at the end of the run,
  # helpful for spotting slow tests.
  config.profile_examples = 10 if ENV['RSPEC_PROFILE']

  # Persist example status so you can run only failed examples with --only-failures
  config.example_status_persistence_file_path = 'tmp/rspec_examples.txt'

  # rspec-core will default to the :documentation formatter when running a
  # single file. Preserve that behavior for easier local debugging.
  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end

  # Run specs in random order to surface order dependencies.
  config.order = :random
  Kernel.srand config.seed

  # Shared context metadata behavior
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Enable warnings to surface Ruby-level issues
  config.warnings = true

  # Allow running focused examples via `:focus` metadata
  config.filter_run_when_matching :focus

  # Filter lines from gems in backtraces to make failures easier to read
  config.filter_gems_from_backtrace "railties", "rack", "activesupport"

  # Hooks useful for cleaning/resetting global state — override in rails_helper if needed.
  config.before(:suite) do
    # noop by default; place global setup here if necessary
  end

  config.after(:suite) do
    # noop by default; place global teardown here if necessary
  end
end
