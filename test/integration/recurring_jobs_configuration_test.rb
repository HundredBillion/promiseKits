require "test_helper"
require "fugit"

class RecurringJobsConfigurationTest < ActiveSupport::TestCase
  test "production schedules both exports on Solid Queue" do
    tasks = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml")).fetch("production")
    orders = tasks.fetch("send_order_export_job")
    florida = tasks.fetch("florida_orders_export_job")

    assert_equal "Admin::SendOrderExportJob", orders.fetch("class")
    assert_equal "Admin::FloridaOrdersExportJob", florida.fetch("class")
    assert_equal "0 7 * * 1,3,5 America/New_York", orders.fetch("schedule")
    assert_equal "0 7 1 * * America/New_York", florida.fetch("schedule")
    assert Fugit::Cron.parse(orders.fetch("schedule"))
    assert Fugit::Cron.parse(florida.fetch("schedule"))
  end
end
