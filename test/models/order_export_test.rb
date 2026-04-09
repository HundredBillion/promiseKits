require "test_helper"

class OrderExportTest < ActiveSupport::TestCase
  setup do
    # Basic fixtures for related models - use unique slugs to avoid conflicts
    @kit = PromiseFitnessKit.create!(name: "Kit A", description: "Desc", slug: "kit-a-#{SecureRandom.hex(4)}")
    @coupon1 = CouponCode.create!(code: "SK3000AAA", usage: "unused")
    @coupon2 = CouponCode.create!(code: "SK3001BBB", usage: "unused")
    @coupon3 = CouponCode.create!(code: "SK3002CCC", usage: "unused")
    @coupon4 = CouponCode.create!(code: "SK3003DDD", usage: "unused")

    # Create three orders with controlled created_at times
    now = Time.current.utc
    @order_before = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon1,
      first_name: "Before",
      last_name: "Order",
      address1: "1 Test St",
      city: "Testville",
      state: "CA",
      zip: "94102",
      phone: "4155550001",
      email: "before@example.com",
      created_at: now - 2.days
    )

    @order_in_window_1 = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon2,
      first_name: "Window1",
      last_name: "Order",
      address1: "2 Test St",
      city: "Testville",
      state: "CA",
      zip: "94102",
      phone: "4155550002",
      email: "w1@example.com",
      created_at: now - 1.day + 1.hour
    )

    @order_in_window_2 = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon3,
      first_name: "Window2",
      last_name: "Order",
      address1: "3 Test St",
      city: "Testville",
      state: "CA",
      zip: "94102",
      phone: "4155550003",
      email: "w2@example.com",
      created_at: now - 1.day + 2.hours
    )

    @order_after = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon4,
      first_name: "After",
      last_name: "Order",
      address1: "4 Test St",
      city: "Testville",
      state: "CA",
      zip: "94102",
      phone: "4155550004",
      email: "after@example.com",
      created_at: now + 1.hour
    )

    # Ensure no pre-existing exported rows
    ExportedOrder.delete_all
    ::OrderExport.delete_all
  end

  test "reserve_orders! reserves only orders in (starts_at, ends_at] and marks export running" do
    # Simulate a last successful export that ended before the window
    last = ::OrderExport.create!(status: "succeeded", scheduled_for: 2.days.ago.utc, ends_at: 2.days.ago.utc)
    scheduled_for = Time.current.utc
    export = OrderExport.create!(status: "pending", scheduled_for: scheduled_for)

    # Reserve orders up to scheduled_for (ends_at)
    reserved = export.reserve_orders!(ends_at: scheduled_for)

    # Expect that orders in the window are reserved (order_in_window_1 & _2), but not order_before or order_after
    reserved_ids = reserved.pluck(:id)
    assert_includes reserved_ids, @order_in_window_1.id
    assert_includes reserved_ids, @order_in_window_2.id
    assert_not_includes reserved_ids, @order_before.id
    assert_not_includes reserved_ids, @order_after.id

    # Export record should be running (set inside transaction) and record reserved_count
    assert_equal "running", export.reload.status
    assert_equal reserved.count, export.reserved_count
  end

  test "reserve_orders! skips orders already exported (uniqueness) and returns only newly reserved" do
    # Clear any existing exports to ensure deterministic behavior
    ExportedOrder.delete_all
    OrderExport.delete_all

    scheduled_for = Time.current.utc

    # Pre-reserve one of the orders to simulate concurrent reservation (as if another worker took it)
    # Use a different scheduled_for time so it doesn't interfere with the test export
    earlier_time = 10.minutes.ago.utc
    taken_export = OrderExport.create!(status: "succeeded", scheduled_for: earlier_time, ends_at: earlier_time)
    ExportedOrder.create!(order_export: taken_export, order: @order_in_window_1)

    # Now create a new export and attempt to reserve orders starting from before the orders were created
    # This forces the query to include @order_in_window_1 and @order_in_window_2
    export = OrderExport.create!(status: "pending", scheduled_for: scheduled_for)

    # Use starts_at before the orders were created to include both in the window
    starts_at = @order_in_window_1.created_at - 1.hour
    reserved = export.reserve_orders!(ends_at: scheduled_for, starts_at: starts_at)

    reserved_ids = reserved.pluck(:id)

    # @order_in_window_1 was already exported, so it should be skipped
    assert_not_includes reserved_ids, @order_in_window_1.id, "Previously exported order should be skipped"

    # @order_in_window_2 should be reserved
    assert_includes reserved_ids, @order_in_window_2.id, "Other orders in window should be reserved"

    # Ensure only one ExportedOrder exists for @order_in_window_1 (the original one)
    assert_equal 1, ExportedOrder.where(order_id: @order_in_window_1.id).count
  end

  test "mark_succeeded! and mark_failed! update status and metadata" do
    export = OrderExport.create!(status: "pending", scheduled_for: Time.current.utc)

    export.mark_succeeded!("file.xlsx")
    assert_equal "succeeded", export.reload.status
    assert_equal "file.xlsx", export.filename
    assert_nil export.error_message

    export2 = OrderExport.create!(status: "pending", scheduled_for: Time.current.utc)
    export2.mark_failed!("boom")
    assert_equal "failed", export2.reload.status
    assert_match /boom/, export2.error_message
  end

  test "exported_order uniqueness validation prevents duplicate exported rows" do
    export = OrderExport.create!(status: "succeeded", scheduled_for: Time.current.utc, ends_at: Time.current.utc)
    eo = ExportedOrder.create!(order_export: export, order: @order_in_window_1)

    # Attempt to create a duplicate exported_order for same order_id should raise
    assert_raises(ActiveRecord::RecordInvalid) do
      ExportedOrder.create!(order_export: export, order: @order_in_window_1)
    end
  end
end
