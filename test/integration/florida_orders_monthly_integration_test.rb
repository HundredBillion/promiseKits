require "test_helper"

class FloridaOrdersMonthlyIntegrationTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear

    @kit = PromiseFitnessKit.create!(name: "Monthly Kit", description: "Test Kit", slug: "monthly-kit")
    @recipient = "admin@example.com"
  end

  test "florida order placed on first of month appears in that month's report" do
    # Step 2: Simulate a Florida user buying on Tuesday Feb 1, 2027 (first of month)
    florida_order = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: CouponCode.create!(code: "SK9000ZZZ", usage: "unused"),
      first_name: "Florida",
      last_name: "Buyer",
      address1: "123 Ocean Dr",
      city: "Miami",
      state: "FL",
      zip: "33139",
      phone: "3055559999",
      email: "florida@example.com",
      created_at: Time.zone.local(2027, 2, 1, 10, 0, 0)
    )

    assert_equal "FL", florida_order.state

    # Step 3a: On Wednesday Feb 2, run job for January (previous month) - should have 0
    travel_to Time.zone.local(2027, 2, 2, 12, 0, 0) do
      Admin::FloridaOrdersExportJob.new.perform(2027, 1, recipient: @recipient)

      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.last

      assert_match /January 2027/, mail.subject
      assert_match(/Monthly Kit.*0/m, mail.body.encoded)
    end

    # Step 3b: On Friday Feb 3, run job for February - should have 1 (the Feb 1 order)
    travel_to Time.zone.local(2027, 2, 3, 12, 0, 0) do
      ActionMailer::Base.deliveries.clear
      Admin::FloridaOrdersExportJob.new.perform(2027, 2, recipient: @recipient)

      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.last

      assert_match /February 2027/, mail.subject
      assert_match(/Monthly Kit.*1/m, mail.body.encoded)
    end

    # Step 4: On first of next month (March 1), run job for February - should still have 1
    travel_to Time.zone.local(2027, 3, 1, 8, 0, 0) do
      ActionMailer::Base.deliveries.clear
      Admin::FloridaOrdersExportJob.new.perform(2027, 2, recipient: @recipient)

      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.last

      assert_match /February 2027/, mail.subject
      assert_match(/Monthly Kit.*1/m, mail.body.encoded)
    end
  end

  test "no florida orders in month results in zero count email" do
    # No orders created - just run the job for February
    travel_to Time.zone.local(2027, 2, 15, 12, 0, 0) do
      Admin::FloridaOrdersExportJob.new.perform(2027, 2, recipient: @recipient)

      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.last

      assert_match /February 2027/, mail.subject
      assert_match(/Monthly Kit.*0/m, mail.body.encoded)
    end
  end
end
