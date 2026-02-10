# frozen_string_literal: true
#
# This file exists so model tests which call:
#   require_relative "test_helper"
# from files under test/models/... can resolve to the root test helper.
#
# It simply delegates to the top-level test/test_helper.rb.

require_relative File.join(__dir__, '..', 'test_helper')
