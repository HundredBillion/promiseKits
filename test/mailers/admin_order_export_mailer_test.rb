require "test_helper"
require "tempfile"

class Admin::OrderExportMailerTest < ActionMailer::TestCase
  setup do
    ActionMailer::Base.deliveries.clear

    # Minimal supporting records for an OrderExport context
    @export = OrderExport.create!(
      status: "pending",
      scheduled_for: Time.current.utc,
      recipient: "ops@example.com"
    )
  end

  test "export_email attaches xlsx file and composes subject/body correctly" do
    tmp = Tempfile.new(["orders_export_test", ".xlsx"])
    begin
      tmp.binmode
      tmp.write("xlsx-binary-placeholder")
      tmp.rewind

      mail = Admin::OrderExportMailer.export_email(
        recipient: "ops@example.com",
        file_path: tmp.path,
        filename: "orders_export_test.xlsx",
        export_id: @export.id,
        scheduled_for: @export.scheduled_for,
        exported_count: 2
      ).deliver_now

      # Delivery
      assert_not ActionMailer::Base.deliveries.empty?, "Expected an email to be delivered"

      # Subject starts with the exported count and the word Orders
      assert_match(/\A2 Orders\b/, mail.subject)

      # Attachment assertions
      assert_equal 1, mail.attachments.length
      attachment = mail.attachments.first
      assert_equal "orders_export_test.xlsx", attachment.filename
      assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", attachment.mime_type

      # Body contains useful summary info
      body_text = mail.body.encoded
      assert_includes body_text, "Export ID: #{@export.id}"
      assert_includes body_text, "Please find attached the orders export"
    ensure
      tmp.close
      tmp.unlink
    end
  end

  test "export_email still delivers when attachment missing (no file present)" do
    non_existent_path = Rails.root.join("tmp", "does_not_exist_#{SecureRandom.hex}.xlsx").to_s

    mail = Admin::OrderExportMailer.export_email(
      recipient: "ops@example.com",
      file_path: non_existent_path,
      filename: "missing.xlsx",
      export_id: @export.id,
      scheduled_for: @export.scheduled_for,
      exported_count: 0
    ).deliver_now

    assert_not ActionMailer::Base.deliveries.empty?, "Expected an email to be delivered even when file is missing"

    # No attachments because file did not exist
    assert_equal 0, mail.attachments.length
    assert_match(/\A0 Orders\b/, mail.subject)
    assert_includes mail.body.encoded, "Export ID: #{@export.id}"
  end
end
