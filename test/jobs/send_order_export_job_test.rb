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
      assert_raises StandardError do
        Admin::SendOrderExportJob.new.perform(scheduled_for, recipient: recipient, manual: true)
      end

      export = OrderExport.order(created_at: :desc).first
      assert_not_nil export, "expected an OrderExport record to exist after failure"
      assert_equal "failed", export.status
      assert_match /builder boom/, export.error_message
    ensure
      OrderExportBuilder.define_singleton_method(:build_to_tempfile, original_method)
    end
  end

  test "retry uses the same export and reserved orders" do
    recipient = "retry-#{SecureRandom.hex(4)}@example.com"
    job = Admin::SendOrderExportJob.new
    scheduled_for = Time.current.utc
    original_method = OrderExportBuilder.method(:build_to_tempfile)
    attempts = 0
    OrderExportBuilder.define_singleton_method(:build_to_tempfile) do |orders:|
      attempts += 1
      raise "builder unavailable" if attempts == 1

      Tempfile.new([ "orders_export_retry", ".xlsx" ]).tap { |file| file.write("xlsx data"); file.flush }
    end

    assert_raises(RuntimeError) { job.perform(scheduled_for, recipient: recipient) }
    first = OrderExport.find_by!(recipient: recipient)
    reserved_ids = first.orders.pluck(:id)
    assert_not_empty reserved_ids

    job.perform(scheduled_for, recipient: recipient)

    assert_equal [ first.id ], OrderExport.where(recipient: recipient).pluck(:id)
    assert_equal reserved_ids.sort, first.reload.orders.pluck(:id).sort
    assert_equal "succeeded", first.status
  ensure
    OrderExportBuilder.define_singleton_method(:build_to_tempfile, original_method) if original_method
  end

  test "delivery error requires review and is not sent again automatically" do
    recipient = "review-#{SecureRandom.hex(4)}@example.com"
    job = Admin::SendOrderExportJob.new
    delivery_attempts = 0
    delivery = Object.new
    delivery.define_singleton_method(:message) { true }
    delivery.define_singleton_method(:deliver_now) do
      delivery_attempts += 1
      raise IOError, "SMTP connection lost"
    end

    Admin::OrderExportMailer.stub(:export_email, delivery) do
      job.perform(Time.current.utc, recipient: recipient)
      job.perform(Time.current.utc, recipient: recipient)
    end

    export = OrderExport.find_by!(recipient: recipient)
    assert_equal "review_required", export.status
    assert_includes export.orders, @order1
    assert_includes export.orders, @order2
    assert_equal 1, delivery_attempts
  end

  test "a duplicate job leaves an in-progress delivery alone" do
    job = Admin::SendOrderExportJob.new
    export = OrderExport.create!(
      job_id: job.job_id,
      status: "running",
      scheduled_for: Time.current.utc,
      recipient: "ops@example.com",
      delivery_started_at: Time.current.utc
    )

    Admin::OrderExportMailer.stub(:export_email, ->(**) { flunk "delivery must not repeat" }) do
      job.perform(export.scheduled_for, recipient: export.recipient)
    end

    assert_equal "running", export.reload.status
    assert_nil export.error_message
  end

  test "an admin retry reuses an earlier failed export" do
    export = OrderExport.create!(scheduled_for: Time.current.utc, recipient: "ops@example.com")
    reserved_ids = export.reserve_orders!(ends_at: export.scheduled_for).pluck(:id)
    export.mark_failed!("builder failed")

    Admin::SendOrderExportJob.new.perform(export.scheduled_for, recipient: export.recipient, export_id: export.id)

    assert_equal "succeeded", export.reload.status
    assert_equal reserved_ids.sort, export.orders.pluck(:id).sort
    assert_equal 1, OrderExport.where(id: export.id).count
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "a build failure schedules an Active Job retry" do
    original_method = OrderExportBuilder.method(:build_to_tempfile)
    OrderExportBuilder.define_singleton_method(:build_to_tempfile) do |orders:|
      raise "builder unavailable"
    end

    assert_difference -> { ActiveJob::Base.queue_adapter.enqueued_jobs.size }, 1 do
      Admin::SendOrderExportJob.perform_now(Time.current.utc, recipient: "retry@example.com")
    end

    assert_equal "failed", OrderExport.find_by!(recipient: "retry@example.com").status
  ensure
    OrderExportBuilder.define_singleton_method(:build_to_tempfile, original_method) if original_method
  end

  test "scheduled export uses the configured recipient" do
    config = Rails.configuration.x.order_export
    original_recipient = config.recipient_email
    config.recipient_email = "configured@example.com"

    assert_equal "configured@example.com", Admin::SendOrderExportJob.new.send(:determine_recipient, nil)
  ensure
    config.recipient_email = original_recipient if config
  end
end
