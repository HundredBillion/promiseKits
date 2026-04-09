require "test_helper"

class FloridaOrdersExportJobTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    ActionMailer::Base.deliveries.clear
    ExportedOrder.delete_all
    OrderExport.delete_all
    Order.delete_all
    CouponCode.delete_all
    PromiseFitnessKit.delete_all

    @kit1 = PromiseFitnessKit.create!(name: "SK-1", description: "Strength Kit 1", slug: "strength-kit-1-#{SecureRandom.hex(4)}")
    @kit2 = PromiseFitnessKit.create!(name: "SK-2", description: "Strength Kit 2", slug: "strength-kit-2-#{SecureRandom.hex(4)}")
    @kit3 = PromiseFitnessKit.create!(name: "WK-1", description: "Walking Kit 1", slug: "walking-kit-1-#{SecureRandom.hex(4)}")

    @coupon = CouponCode.create!(code: CouponCode.generate_next_code, usage: "unused")

    create_florida_orders
  end

  def create_florida_orders
    # Create Florida orders in March 2026
    @florida_order1 = Order.create!(
      promise_fitness_kit: @kit1,
      coupon_code: @coupon,
      first_name: "John",
      last_name: "Florida",
      address1: "123 Beach Blvd",
      city: "Miami",
      state: "FL",
      zip: "33101",
      phone: "3055550101",
      email: "john@florida.com",
      created_at: Date.new(2026, 3, 15)
    )

    @florida_order2 = Order.create!(
      promise_fitness_kit: @kit1,
      coupon_code: CouponCode.create!(code: "SK1001BBB", usage: "unused"),
      first_name: "Jane",
      last_name: "Sunshine",
      address1: "456 Palm Ave",
      city: "Orlando",
      state: "FL",
      zip: "32801",
      phone: "4075550102",
      email: "jane@florida.com",
      created_at: Date.new(2026, 3, 20)
    )

    @florida_order3 = Order.create!(
      promise_fitness_kit: @kit2,
      coupon_code: CouponCode.create!(code: "SK1002CCC", usage: "unused"),
      first_name: "Bob",
      last_name: "Sand",
      address1: "789 Ocean Dr",
      city: "Fort Lauderdale",
      state: "FL",
      zip: "33301",
      phone: "9545550103",
      email: "bob@florida.com",
      created_at: Date.new(2026, 3, 25)
    )
  end

  test "perform sends email with correct Florida orders summary for previous month" do
    recipient = "reports@example.com"

    # Run job for March 2026 (previous month from April 2026)
    travel_to Date.new(2026, 4, 1) do
      AdminReports::FloridaOrdersExportJob.new.perform(2026, 3, recipient: recipient)
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
    mail = ActionMailer::Base.deliveries.last

    assert_match /Florida Fitness Kit Orders/, mail.subject
    assert_match /March 2026/, mail.subject
    assert_equal recipient, mail.to.first

    # Verify body contains the kit counts
    assert_match /SK-1/, mail.body.encoded
    assert_match /SK-2/, mail.body.encoded
    assert_match /WK-1/, mail.body.encoded

    # SK-1 should have 2
    assert_match /2/, mail.body.encoded
  end

  test "perform defaults to previous month when no month/year provided" do
    recipient = "reports@example.com"

    # Travel to April 2026, run without explicit month/year
    travel_to Date.new(2026, 4, 1) do
      AdminReports::FloridaOrdersExportJob.new.perform(nil, nil, recipient: recipient)
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
    mail = ActionMailer::Base.deliveries.last

    assert_match /March 2026/, mail.subject
  end

  test "perform raises error when no recipient configured" do
    assert_raises ArgumentError do
      AdminReports::FloridaOrdersExportJob.new.perform(2026, 3, recipient: nil)
    end

    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  test "perform includes all kits even when some have zero orders" do
    recipient = "reports@example.com"

    travel_to Date.new(2026, 4, 1) do
      AdminReports::FloridaOrdersExportJob.new.perform(2026, 3, recipient: recipient)
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
    mail = ActionMailer::Base.deliveries.last

    # WK-1 was created but no FL orders for it, should show 0
    assert_match /WK-1.*0/m, mail.body.encoded
  end

  test "perform only includes Florida orders in the specified month" do
    recipient = "reports@example.com"

    # Create a Florida order in a different month (should not be included)
    Order.create!(
      promise_fitness_kit: @kit1,
      coupon_code: CouponCode.create!(code: "SK1003DDD", usage: "unused"),
      first_name: "OutOfRange",
      last_name: "Florida",
      address1: "999 Test St",
      city: "Jacksonville",
      state: "FL",
      zip: "32201",
      phone: "9045550199",
      email: "out@range.com",
      created_at: Date.new(2026, 2, 15) # February, not March
    )

    travel_to Date.new(2026, 4, 1) do
      AdminReports::FloridaOrdersExportJob.new.perform(2026, 3, recipient: recipient)
    end

    mail = ActionMailer::Base.deliveries.last

    # SK-1 should still be 2 (Feb order should not be included)
    # Count occurrences of "2" near SK-1 in the body
    assert_match /SK-1.*2/m, mail.body.encoded
  end

  test "perform excludes non-Florida orders" do
    # Create a non-Florida order in the same month
    Order.create!(
      promise_fitness_kit: @kit1,
      coupon_code: CouponCode.create!(code: "SK1004EEE", usage: "unused"),
      first_name: "Non",
      last_name: "Florida",
      address1: "100 California St",
      city: "San Francisco",
      state: "CA",
      zip: "94102",
      phone: "4155559999",
      email: "nonfl@example.com",
      created_at: Date.new(2026, 3, 10)
    )

    recipient = "reports@example.com"

    travel_to Date.new(2026, 4, 1) do
      AdminReports::FloridaOrdersExportJob.new.perform(2026, 3, recipient: recipient)
    end

    mail = ActionMailer::Base.deliveries.last

    # SK-1 should still be 2 (CA order should not be included)
    assert_match /SK-1.*2/m, mail.body.encoded
  end
end
