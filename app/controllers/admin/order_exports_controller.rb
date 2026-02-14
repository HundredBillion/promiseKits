# frozen_string_literal: true

# Controller: Admin::OrderExportsController
#
# Responsible for admin UI to request ad-hoc exports of orders. Scheduling of
# recurring exports (Mon/Wed/Fri 07:00 America/New_York) is handled via Sidekiq
# scheduler configuration (see config/sidekiq or scheduler config).
#
# Notes:
# - This controller enqueues Admin::SendOrderExportJob which performs the
#   actual reservation, building and emailing of the export.
# - The admin form may optionally provide an `ends_at` time (interpreted in the
#   configured OrderExport timezone). If absent, the job uses Time.current.utc as
#   the scheduled_for time (meaning "export up to now").
#
class Admin::OrderExportsController < Admin::BaseController
  # GET /admin/order_exports/new
  def new
    @last_export = OrderExport.last_successful
    # Default recipient from config (initializer or ENV)
    @default_recipient = OrderExport::Config.recipient_email
    # Default scheduled_for shown to the admin in local (America/New_York) timezone
    tz = ActiveSupport::TimeZone[OrderExport::Config.timezone]
    @default_scheduled_local = Time.current.in_time_zone(tz)
  end

  # POST /admin/order_exports
  #
  # Accepts these (optional) params via `order_export`:
  #   - ends_at: string representation of local time in configured timezone (e.g. "2026-02-16 07:00")
  #   - recipient: override recipient email for this run
  #
  # Behavior:
  #   - Parse `ends_at` in the configured timezone and convert to UTC for the job.
  #   - If ends_at is not provided, use Time.current.utc.
  #   - Enqueue Admin::SendOrderExportJob with scheduled_for_utc and recipient.
  def create
    attrs = order_export_params
    recipient = attrs[:recipient].presence || OrderExport::Config.recipient_email

    scheduled_for_utc = if attrs[:ends_at].present?
                          parse_local_to_utc(attrs[:ends_at])
                        else
                          Time.current.utc
                        end

    # Enqueue the export job (job will create an OrderExport record and perform the run)
    Admin::SendOrderExportJob.perform_later(scheduled_for_utc, recipient: recipient, manual: true)

    redirect_to admin_dashboard_path, notice: "Export requested — an email will be sent to #{recipient} when the export is ready."
  rescue ArgumentError => e
    redirect_to admin_dashboard_path, alert: "Invalid input: #{e.message}"
  rescue StandardError => e
    Rails.logger.error("[Admin::OrderExportsController#create] Failed to schedule export: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
    redirect_to admin_dashboard_path, alert: "Unable to schedule export: #{e.message}"
  end

  private

  # Strong params for the admin form
  def order_export_params
    params.fetch(:order_export, {}).permit(:ends_at, :recipient)
  end

  # Parse a local-time string (assumed in configured timezone) into a UTC Time.
  # Raises ArgumentError if parsing fails.
  def parse_local_to_utc(value)
    tz = ActiveSupport::TimeZone[OrderExport::Config.timezone]
    raise ArgumentError, "Unknown timezone configuration" unless tz

    # Use Time.zone parsing resilience by constructing a tz-local time
    # The admin UI should provide a value like "2026-02-16 07:00" or an ISO string.
    parsed = begin
      # Try to parse as an ISO8601 or common datetime string first
      Time.zone = tz.name
      Time.zone.parse(value)
    rescue StandardError
      nil
    ensure
      # Reset Time.zone to app default just in case (do not rely on global side effects)
      Time.zone = Rails.application.config.time_zone rescue nil
    end

    parsed ||= begin
      # Fallback: try to build with tz.local (this will raise if invalid parts provided)
      parts = value.to_s.strip.split(/[^\d]/).map(&:to_i)
      # Expect at least year, month, day for a robust parse; otherwise raise
      if parts.size >= 3
        year, month, day = parts[0..2]
        hour = parts[3] || OrderExport::Config.schedule_hour
        min  = parts[4] || OrderExport::Config.schedule_minute
        tz.local(year, month, day, hour, min, 0)
      else
        raise ArgumentError, "Unable to parse ends_at: '#{value}'"
      end
    end

    raise ArgumentError, "Unable to parse ends_at: '#{value}'" if parsed.nil?

    parsed.utc
  end
end
