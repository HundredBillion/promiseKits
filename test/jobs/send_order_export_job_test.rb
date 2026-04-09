require "test_helper"
require "tempfile"

class SendOrderExportJobTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear

    @kit = PromiseFitnessKit.create!(name: "Job Kit", description: "desc", slug: "job-kit")
    @coupon1 = CouponCode.create!(code: "SK2000AAA", usage: "unused")
    @coupon2 = CouponCode.create!(code: "SK2001BBB", usage: "unused")

    @order1 = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon1,
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
      coupon_code: @coupon2,
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

    tmp = Tempfile.new([ "orders_export_test", ".xlsx" ])
    tmp.binmode
    tmp.write("dummy content")
    tmp.rewind

    original_method = OrderExportBuilder.method(:build_to_tempfile)
    OrderExportBuilder.define_singleton_method(:build_to_tempfile) do |orders:|
      tmp
    end

    begin
      ActiveJob::Base.queue_adapter = :inline
      Admin::SendOrderExportJob.perform_now(scheduled_for, recipient: recipient, manual: true)

      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.last
      assert_match /Orders/, mail.subject
      assert_equal 1, mail.attachments.count
      attachment = mail.attachments.first
      assert_match(/\Aorders_export_\d{8}_\d{6}_UTC\.xlsx\z/, attachment.filename)

      export = OrderExport.order(created_at: :desc).first
      assert_not_nil export, "expected an OrderExport record to be created"
      assert_equal "succeeded", export.status
      assert_equal recipient, export.recipient
      assert_match /\.xlsx\z/, export.filename.to_s
    ensure
      tmp.close
      tmp.unlink rescue nil
      OrderExportBuilder.define_singleton_method(:build_to_tempfile, original_method)
      ActiveJob::Base.queue_adapter = :test
    end
  end

  test "perform failure marks export failed and records error_message" do
    scheduled_for = Time.current.utc
    recipient = "ops@example.com"

    original_method = OrderExportBuilder.method(:build_to_tempfile)
    OrderExportBuilder.define_singleton_method(:build_to_tempfile) do |orders:|
      raise StandardError, "builder boom"
    end

    begin
      ActiveJob::Base.queue_adapter = :inline
      assert_raises StandardError do
        Admin::SendOrderExportJob.perform_now(scheduled_for, recipient: recipient, manual: true)
      end

      export = OrderExport.order(created_at: :desc).first
      assert_not_nil export, "expected an OrderExport record to exist after failure"
      assert_equal "failed", export.status
      assert_match /builder boom/, export.error_message
    ensure
      OrderExportBuilder.define_singleton_method(:build_to_tempfile, original_method)
      ActiveJob::Base.queue_adapter = :test
    end
  end
end
