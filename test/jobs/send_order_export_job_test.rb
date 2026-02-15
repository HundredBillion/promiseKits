require "test_helper"
require "tempfile"

class SendOrderExportJobTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear

    @kit = PromiseFitnessKit.create!(name: "Job Kit", description: "desc", slug: "job-kit")
    @coupon = CouponCode.create!(code: "JOBCOUPON", usage: "unused")

    # Create a few orders to be exported
    @order1 = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon,
      first_name: "Jane",
      last_name: "Doe",
      address1: "1 Example Way",
      city: "Exampleton",
      state: "CA",
      zip: "94102",
      phone: "4155550101",
      email: "jane@example.com"
    )

    @order2 = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon,
      first_name: "John",
      last_name: "Smith",
      address1: "2 Example Ave",
      city: "Exampleton",
      state: "CA",
      zip: "94103",
      phone: "4155550102",
      email: "john@example.com"
    )
  end

  test "perform reserves orders, builds file and sends mail; marks export succeeded" do
    scheduled_for = Time.current.utc
    recipient = "ops@example.com"

    # Prepare a Tempfile to be returned by the builder stub
    tmp = Tempfile.new(["orders_export_test", ".xlsx"])
    tmp.binmode
    tmp.write("dummy content")
    tmp.rewind

    # Stub the builder to return our tempfile (accepting named args)
    OrderExport::Builder.stub :build_to_tempfile, proc { |orders:, opts: {}| tmp } do
      # Run the job synchronously
      Admin::SendOrderExportJob.perform_now(scheduled_for, recipient: recipient, manual: true)
    end

    # One mail should have been sent
    assert_equal 1, ActionMailer::Base.deliveries.size
    mail = ActionMailer::Base.deliveries.last
    assert_match /Orders/, mail.subject
    # Attachment should be present and its filename should match expected pattern
    assert_equal 1, mail.attachments.count
    attachment = mail.attachments.first
    assert_match(/\Aorders_export_\d{8}_\d{6}_UTC\.xlsx\z/, attachment.filename)

    # Export record created and marked succeeded
    export = OrderExport.order(created_at: :desc).first
    assert_not_nil export, "expected an OrderExport record to be created"
    assert_equal "succeeded", export.status
    assert_equal recipient, export.recipient
    assert_match /\.xlsx\z/, export.filename.to_s

    # Cleanup tempfile (job attempts to unlink; ensure it's gone)
    tmp.close
    tmp.unlink rescue nil
  end

  test "perform failure marks export failed and records error_message" do
    scheduled_for = Time.current.utc
    recipient = "ops@example.com"

    # Stub builder to raise an error to simulate failure during build
    OrderExport::Builder.stub :build_to_tempfile, proc { |_orders:, _opts: {}| raise StandardError, "builder boom" } do
      # The job re-raises after marking failed; we capture the exception to continue assertions
      assert_raises StandardError do
        Admin::SendOrderExportJob.perform_now(scheduled_for, recipient: recipient, manual: true)
      end
    end

    # There should be at least one OrderExport record created (failed)
    export = OrderExport.order(created_at: :desc).first
    assert_not_nil export, "expected an OrderExport record to exist after failure"
    assert_equal "failed", export.status
    assert_match /builder boom/, export.error_message
  end
end
