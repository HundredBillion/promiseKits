# frozen_string_literal: true
#
# Job: Admin::SendOrderExportJob
#
# Orchestrates a single export run:
#  - determines the export window (ends_at = scheduled_for)
#  - creates an OrderExport record
#  - atomically reserves orders for the export via OrderExport#reserve_orders!
#  - builds an .xlsx via OrderExport::Builder to a Tempfile
#  - sends the file via Admin::OrderExportMailer
#  - marks the export succeeded/failed and ensures temporary file cleanup
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

  # Retry a few times on transient errors (exponential backoff)
  retry_on StandardError, attempts: 3, wait: :exponentially_longer

  # Perform the export.
  #
  # scheduled_for_utc - optional Time/String; the canonical scheduled time (UTC) that defines the export window end.
  # recipient         - optional String email address to send the export to
  # manual            - optional Boolean to indicate this was triggered manually
  def perform(scheduled_for_utc = nil, recipient: nil, manual: false)
    scheduled_for_utc = parse_time_to_utc(scheduled_for_utc) || Time.current.utc
    recipient = determine_recipient(recipient)

    export = OrderExport.create!(status: 'pending', scheduled_for: scheduled_for_utc, recipient: recipient)

    begin
      # Reserve orders for this export run. The reserve_orders! method handles transactionality
      # and skips IDs that may have been reserved by concurrent workers.
      reserved_orders = export.reserve_orders!(ends_at: scheduled_for_utc)

      Rails.logger.info("[Admin::SendOrderExportJob] export_id=#{export.id} reserved #{reserved_orders.size} orders (scheduled_for=#{scheduled_for_utc.iso8601})")

      # Build the .xlsx into a Tempfile
      tmpfile = OrderExport::Builder.build_to_tempfile(orders: reserved_orders)
      filename = "orders_export_#{scheduled_for_utc.strftime('%Y%m%d_%H%M%S')}_UTC.xlsx"

      # Send the email synchronously from within the job (deliver_now)
      Admin::OrderExportMailer.export_email(
        recipient: recipient,
        file_path: tmpfile.path,
        filename: filename,
        export_id: export.id,
        scheduled_for: scheduled_for_utc,
        exported_count: reserved_orders.size
      ).deliver_now

      # Mark export as succeeded
      export.mark_succeeded!(filename)
      Rails.logger.info("[Admin::SendOrderExportJob] export_id=#{export.id} succeeded; emailed to #{recipient}")

    rescue => e
      Rails.logger.error("[Admin::SendOrderExportJob] export_id=#{export&.id} failed: #{e.class}: #{e.message}\n#{Array(e.backtrace).join(\"\\n\")}")
      begin
        export.mark_failed!(e.message) if export
      rescue => mark_err
        Rails.logger.error("[Admin::SendOrderExportJob] Failed to mark export failed for export_id=#{export&.id}: #{mark_err.class}: #{mark_err.message}")
      end
      # Re-raise so ActiveJob retry mechanism can act
      raise
    ensure
      # Ensure tempfile cleanup
      if defined?(tmpfile) && tmpfile.respond_to?(:close)
        begin
          tmpfile.close
          tmpfile.unlink
        rescue => cleanup_err
          Rails.logger.warn("[Admin::SendOrderExportJob] Failed to cleanup tempfile for export_id=#{export&.id}: #{cleanup_err.class}: #{cleanup_err.message}")
        end
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

    ENV['ORDER_EXPORT_RECIPIENT'] || ENV['DEFAULT_ORDER_EXPORT_RECIPIENT'] || raise(ArgumentError, "No recipient configured for Order Export")
  end
end
