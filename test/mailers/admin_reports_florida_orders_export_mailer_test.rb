require "test_helper"

class FloridaOrdersExportMailerTest < ActionMailer::TestCase
  test "florida_orders_email sends email with correct subject and recipients" do
    summary = [
      { name: "SK-1", total: 5 },
      { name: "SK-2", total: 3 },
      { name: "SK-3", total: 0 },
      { name: "WK-1", total: 2 }
    ]

    mail = AdminReports::FloridaOrdersExportMailer.florida_orders_email(
      recipient: "reports@example.com",
      month_name: "March 2026",
      summary: summary
    )

    assert_equal "reports@example.com", mail.to.first
    assert_match /Florida Fitness Kit Orders - March 2026/, mail.subject
  end

  test "florida_orders_email includes all kits in the table" do
    summary = [
      { name: "SK-1", total: 10 },
      { name: "SK-2", total: 5 },
      { name: "PK-1", total: 0 }
    ]

    mail = AdminReports::FloridaOrdersExportMailer.florida_orders_email(
      recipient: "reports@example.com",
      month_name: "January 2026",
      summary: summary
    )

    assert_match /SK-1/, mail.body.encoded
    assert_match /10/, mail.body.encoded
    assert_match /SK-2/, mail.body.encoded
    assert_match /5/, mail.body.encoded
    assert_match /PK-1/, mail.body.encoded
    assert_match /0/, mail.body.encoded
  end

  test "florida_orders_email calculates and displays total correctly" do
    summary = [
      { name: "SK-1", total: 10 },
      { name: "SK-2", total: 5 },
      { name: "WK-1", total: 3 }
    ]

    mail = AdminReports::FloridaOrdersExportMailer.florida_orders_email(
      recipient: "reports@example.com",
      month_name: "February 2026",
      summary: summary
    )

    # Should show total of 18
    assert_match /Total.*18.*kits/m, mail.body.encoded
  end

  test "florida_orders_email renders both text and html parts" do
    summary = [
      { name: "SK-1", total: 1 }
    ]

    mail = AdminReports::FloridaOrdersExportMailer.florida_orders_email(
      recipient: "reports@example.com",
      month_name: "March 2026",
      summary: summary
    )

    # Mail should have both text and html parts
    assert mail.multipart?
    assert mail.text_part
    assert mail.html_part

    # Text part should contain plain text table
    assert_match /Fitness Kit/, mail.text_part.body.encoded
    assert_match /SK-1/, mail.text_part.body.encoded

    # HTML part should contain table
    assert_match /<table/, mail.html_part.body.encoded
    assert_match /SK-1/, mail.html_part.body.encoded
  end

  test "florida_orders_email handles zero orders correctly" do
    summary = [
      { name: "SK-1", total: 0 },
      { name: "SK-2", total: 0 },
      { name: "SK-3", total: 0 }
    ]

    mail = AdminReports::FloridaOrdersExportMailer.florida_orders_email(
      recipient: "reports@example.com",
      month_name: "March 2026",
      summary: summary
    )

    # Should show 0 total
    assert_match /Total.*0.*kits/m, mail.body.encoded

    # HTML should show 0 for each
    html_body = mail.html_part.body.encoded
    assert_match /<td>0<\/td>/, html_body
  end
end
