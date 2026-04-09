# frozen_string_literal: true

#
# Job: Admin::FloridaOrdersExportJob
#
# Runs on the 1st of each month, sending a summary email of all fitness kits
# ordered with a Florida shipping address during the previous month.
#
# Example:
#   - On Feb 1, sends January's data
#   - On Mar 1, sends February's data
#
# Can be run manually with optional parameters:
#   Admin::FloridaOrdersExportJob.perform_now(month: 1, year: 2026)
#   Admin::FloridaOrdersExportJob.perform_now(2026, 1)  # year, month
#
class Admin::FloridaOrdersExportJob < ApplicationJob
  queue_as :default

  # Remove retry for now to simplify testing
  # retry_on StandardError, attempts: 3, wait: :exponential_wait

  def perform(year = nil, month = nil, recipient: nil)
    month ||= prev_month
    year  ||= prev_year
    recipient ||= ENV["ORDER_EXPORT_RECIPIENT"]

    raise ArgumentError, "No recipient configured for Florida Orders Export" if recipient.blank?

    florida_orders = fetch_florida_orders(month, year)
    summary = build_summary(florida_orders)

    send_email(recipient: recipient, month: month, year: year, summary: summary)
  end

  private

  def prev_month
    prev_date = 1.month.ago
    prev_date.month
  end

  def prev_year
    prev_date = 1.month.ago
    prev_date.year
  end

  def fetch_florida_orders(month, year)
    start_date = Date.new(year, month, 1)
    end_date = start_date.next_month

    Order.where(state: "FL")
        .where(created_at: start_date...end_date)
  end

  def build_summary(florida_orders)
    all_kits = PromiseFitnessKit.order(:name).to_a
    kit_counts = florida_orders.group(:promise_fitness_kit_id).count

    all_kits.map do |kit|
      {
        name: kit.name,
        total: kit_counts[kit.id] || 0
      }
    end
  end

  def send_email(recipient:, month:, year:, summary:)
    month_name = Date.new(year, month, 1).strftime("%B %Y")

    Admin::FloridaOrdersExportMailer.florida_orders_email(
      recipient: recipient,
      month_name: month_name,
      summary: summary
    ).deliver_now
  end
end
