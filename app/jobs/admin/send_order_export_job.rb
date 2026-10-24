# frozen_string_literal: true

#
# Job: Admin::SendOrderExportJob
#
# Orchestrates a single export run:
#  - determines the export window (ends_at = scheduled_for)
#  - creates an OrderExport record
#  - atomically reserves orders for the export via OrderExport#reserve_orders!
#  - builds an .xlsx via OrderExportBuilder to a Tempfile
#  - sends the file via Admin::OrderExportMailer
#  - records success, retryable failure, or a delivery that needs review
#
# Notes:
#  - The job accepts an optional `scheduled_for_utc` which should be a Time/String representing
#    the scheduled run time in UTC. If not provided, Time.current.utc is used.
#  - The `recipient` may be provided; otherwise the job falls back to ENV or configured default.
#  - We rely on the DB unique index on exported_orders.order_id plus transactional reservation
#    to ensure each order is exported at most once.
#
class Admin::SendOrderExportJob < ApplicationJob
  queue_as :default

  # Retry pre-delivery errors with Active Job's polynomial backoff.
  retry_on StandardError, attempts: 3, wait: :polynomially_longer

  # Perform the export.
  #
  # scheduled_for_utc - optional Time/String; the canonical scheduled time (UTC) that defines the export window end.
  # recipient         - optional String email address to send the export to
  # manual            - optional Boolean to indicate this was triggered manually
  def perform(scheduled_for_utc = nil, recipient: nil, manual: false, export_id: nil)
    scheduled_for_utc = parse_time_to_utc(scheduled_for_utc) || Time.current.utc
    recipient = determine_recipient(recipient)
    export = if export_id
      OrderExport.find(export_id)
    else
      OrderExport.create_or_find_by!(job_id: job_id) do |run|
        run.status = "pending"
        run.scheduled_for = scheduled_for_utc
        run.recipient = recipient
      end
    end
    if export_id
      claimed = OrderExport.where(id: export.id, status: "failed").update_all(status: "pending")
      return if claimed.zero?
      export.reload
    end
    return if export.succeeded? || export.review_required?

    if export.delivery_started_at.present?
      export.mark_review_required!("Delivery was started but its outcome was not recorded")
      return
    end

    scheduled_for_utc = export.scheduled_for
    recipient = export.recipient
    delivery_attempted = false

    begin
      reserved_orders = export.reserve_orders!(ends_at: scheduled_for_utc)
      tmpfile = OrderExportBuilder.build_to_tempfile(orders: reserved_orders)
      filename = "orders_export_#{scheduled_for_utc.strftime('%Y%m%d_%H%M%S')}_UTC.xlsx"
      delivery = Admin::OrderExportMailer.export_email(
        recipient: recipient,
        file_path: tmpfile.path,
        filename: filename,
        export_id: export.id,
        scheduled_for: scheduled_for_utc,
        exported_count: reserved_orders.size
      )
      delivery.message
      return unless export.begin_delivery!
      delivery_attempted = true
      delivery.deliver_now
      export.mark_succeeded!(filename)
    rescue StandardError => error
      Rails.logger.error("[Admin::SendOrderExportJob] export_id=#{export.id} failed: #{error.class}: #{error.message}")
      if delivery_attempted
        begin
          export.mark_review_required!(error.message)
        rescue StandardError => status_error
          Rails.logger.error("[Admin::SendOrderExportJob] export_id=#{export.id} needs delivery review; status update failed: #{status_error.class}: #{status_error.message}")
        end
      else
        export.mark_failed!(error.message)
        raise
      end
    ensure
      if defined?(tmpfile) && tmpfile.respond_to?(:close)
        tmpfile.close
        tmpfile.unlink
      end
    end
  end

  private

  # Parse various time representations to UTC Time.
  def parse_time_to_utc(value)
    return nil if value.nil?

    case value
    when String
      Time.parse(value).utc rescue nil
    when Time, DateTime
      value.to_time.utc
    else
      nil
    end
  end

  # Determine recipient: prefer explicit arg, then ENV, then Rails configuration.
  def determine_recipient(provided)
    return provided if provided.present?

    # prefer an app config value if available
    begin
      cfg = Rails.configuration.x.order_export if defined?(Rails) && Rails.configuration.respond_to?(:x)
      return cfg.recipient if cfg && cfg.respond_to?(:recipient) && cfg.recipient.present?
    rescue
      # swallow config errors and fall back to ENV
    end

    ENV["ORDER_EXPORT_RECIPIENT"] || ENV["DEFAULT_ORDER_EXPORT_RECIPIENT"] || raise(ArgumentError, "No recipient configured for Order Export")
  end
end
