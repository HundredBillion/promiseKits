require "test_helper"

class OhioOrdersFridayIntegrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    ActionMailer::Base.deliveries.clear
    ExportedOrder.delete_all
    OrderExport.delete_all
    Order.delete_all
    PromiseFitnessKit.delete_all
    CouponCode.delete_all

    @kit = PromiseFitnessKit.create!(name: "Friday Kit OH", description: "Test Kit", slug: "friday-kit-ohio-#{SecureRandom.hex(4)}")
    @recipient = "admin@example.com"

    @original_env = ENV["ORDER_EXPORT_RECIPIENT"]
    ENV["ORDER_EXPORT_RECIPIENT"] = @recipient
  end

  teardown do
    ENV["ORDER_EXPORT_RECIPIENT"] = @original_env
  end

  test "ohio order on thursday appears in friday regular export" do
    Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: CouponCode.create!(code: "SK9100AAA", usage: "unused"),
      first_name: "Ohio",
      last_name: "Buyer",
      address1: "100 Ohio St",
      city: "Columbus",
      state: "OH",
      zip: "43201",
      phone: "6145559999",
      email: "ohio@example.com",
      created_at: Time.zone.local(2025, 1, 30, 14, 0, 0)
    )

    travel_to Time.zone.local(2025, 1, 31, 8, 0, 0) do
      ActionMailer::Base.deliveries.clear

      OrderExport.create!(
        status: "succeeded",
        scheduled_for: Time.zone.local(2025, 1, 29, 7, 0, 0).utc,
        ends_at: Time.zone.local(2025, 1, 29, 7, 0, 0).utc
      )

      Admin::SendOrderExportJob.new.perform(Time.current.utc, recipient: @recipient, manual: true)

      assert_equal 1, ActionMailer::Base.deliveries.size
    end

    job_export = OrderExport.where(status: "succeeded").last
    assert_equal 1, job_export.exported_orders.count
  end

  test "florida export shows zero for non-florida orders" do
    Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: CouponCode.create!(code: "SK9101BBB", usage: "unused"),
      first_name: "Ohio",
      last_name: "Buyer",
      address1: "100 Ohio St",
      city: "Columbus",
      state: "OH",
      zip: "43201",
      phone: "6145559998",
      email: "ohio2@example.com",
      created_at: Time.zone.local(2025, 1, 30, 14, 0, 0)
    )

    travel_to Time.zone.local(2025, 1, 31, 8, 0, 0) do
      ActionMailer::Base.deliveries.clear

      Admin::FloridaOrdersExportJob.new.perform(2024, 12)

      assert_equal 1, ActionMailer::Base.deliveries.size
    end

    florida_mail = ActionMailer::Base.deliveries.last
    assert_match /December 2024/, florida_mail.subject

    text_body = florida_mail.text_part&.body&.to_s || florida_mail.body.to_s
    html_body = florida_mail.html_part&.body&.to_s || ""
    full_body = text_body + html_body

    assert full_body.include?(@kit.name), "Body should include kit name"
    assert full_body.include?("0"), "Florida report should show 0 orders"
  end

  test "both jobs send correct emails on friday after ohio order on thursday" do
    Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: CouponCode.create!(code: "SK9102CCC", usage: "unused"),
      first_name: "Ohio",
      last_name: "Buyer",
      address1: "100 Ohio St",
      city: "Columbus",
      state: "OH",
      zip: "43201",
      phone: "6145559997",
      email: "ohio3@example.com",
      created_at: Time.zone.local(2025, 1, 30, 14, 0, 0)
    )

    travel_to Time.zone.local(2025, 1, 31, 8, 0, 0) do
      ActionMailer::Base.deliveries.clear

      OrderExport.create!(
        status: "succeeded",
        scheduled_for: Time.zone.local(2025, 1, 29, 7, 0, 0).utc,
        ends_at: Time.zone.local(2025, 1, 29, 7, 0, 0).utc
      )

      Admin::SendOrderExportJob.new.perform(Time.current.utc, recipient: @recipient, manual: true)
      Admin::FloridaOrdersExportJob.new.perform(2024, 12)

      assert_equal 2, ActionMailer::Base.deliveries.size
    end

    job_export = OrderExport.where(status: "succeeded").last
    assert_equal 1, job_export.exported_orders.count

    florida_mail = ActionMailer::Base.deliveries.find { |m| m.subject.include?("Florida") }
    assert_not_nil florida_mail
    assert_match /December 2024/, florida_mail.subject

    text_body = florida_mail.text_part&.body&.to_s || florida_mail.body.to_s
    html_body = florida_mail.html_part&.body&.to_s || ""
    full_body = text_body + html_body

    assert full_body.include?("0"), "Florida report should show 0 orders"
  end
end
