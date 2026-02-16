require "test_helper"

class OrderExportTest < ActiveSupport::TestCase
  setup do
    # Basic fixtures for related models
    @kit = PromiseFitnessKit.create!(name: "Kit A", description: "Desc", slug: "kit-a")
    @coupon = CouponCode.create!(code: "C-TEST", usage: "unused")

    # Create three orders with controlled created_at times
    now = Time.current.utc
    @order_before = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon,
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
      coupon_code: @coupon,
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
      coupon_code: @coupon,
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
      coupon_code: @coupon,
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
    OrderExport.delete_all
  end

  test "reserve_orders! reserves only orders in (starts_at, ends_at] and marks export running" do
    # Simulate a last successful export that ended before the window
    last = OrderExport.create!(status: "succeeded", scheduled_for: 2.days.ago.utc, ends_at: 2.days.ago.utc)
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
    scheduled_for = Time.current.utc

    # Pre-reserve one of the orders to simulate concurrent reservation (as if another worker took it)
    pre_export = OrderExport.create!(status: "succeeded", scheduled_for: 1.day.ago.utc, ends_at: 1.day.ago.utc)
    taken_export = OrderExport.create!(status: "succeeded", scheduled_for: scheduled_for, ends_at: scheduled_for)
    ExportedOrder.create!(order_export: taken_export, order: @order_in_window_1)

    # Now create a new export and attempt to reserve the same window; the already-taken order should be skipped
    export = OrderExport.create!(status: "pending", scheduled_for: scheduled_for)
    reserved = export.reserve_orders!(ends_at: scheduled_for)

    reserved_ids = reserved.pluck(:id)
    assert_not_includes reserved_ids, @order_in_window_1.id, "Previously exported order should be skipped"
    assert_includes reserved_ids, @order_in_window_2.id, "Other orders in window should be reserved"

    # Ensure exported_orders are not duplicated for the taken order (unique constraint enforced)
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
