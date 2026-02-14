# frozen_string_literal: true

# Configuration for the Order Export feature.
#
# This initializer centralizes runtime configuration values used by the
# export job, mailer and admin UI. Values can be overridden via environment
# variables in production.
#
# Usage:
#   Rails.configuration.x.order_export.recipient_email
#   Rails.configuration.x.order_export.timezone
#   OrderExport::Config.next_scheduled_for # => returns a UTC Time for the next scheduled run
#
Rails.application.configure do
  config.x.order_export = ActiveSupport::InheritableOptions.new(
    # Primary recipient for scheduled export emails. Can be overridden by ENV.
    recipient_email: ENV.fetch('ORDER_EXPORT_RECIPIENT', 'reports@example.com'),

    # From address used by the export mailer (fallback)
    from_email: ENV.fetch('ORDER_EXPORT_FROM', 'no-reply@example.com'),

    # Timezone to use for scheduling and human-readable dates in emails.
    # Use the IANA timezone name. Spec requires America/New_York (EST/EDT).
    timezone: ENV.fetch('ORDER_EXPORT_TIMEZONE', 'America/New_York'),

    # Scheduled weekdays for exporting (Ruby wday integers: 0 = Sunday, 1 = Monday, ... 6 = Saturday)
    # Spec: Monday, Wednesday, Friday
    schedule_weekdays: [1, 3, 5],

    # Scheduled local time (hour/minute) in the configured timezone
    schedule_hour: ENV.fetch('ORDER_EXPORT_HOUR', 7).to_i,
    schedule_minute: ENV.fetch('ORDER_EXPORT_MINUTE', 0).to_i,

    # Optional: maximum number of rows per XLSX sheet (if you later implement splitting)
    sheet_row_limit: ENV.fetch('ORDER_EXPORT_SHEET_ROW_LIMIT', 100_000).to_i
  )
end

# Lightweight helper module for order export scheduling & config access.
# Placed here so other code (jobs, mailers, scheduler config) can call these utilities.
module OrderExport
  module Config
    extend self

    def recipient_email
      Rails.configuration.x.order_export.recipient_email
    end

    def from_email
      Rails.configuration.x.order_export.from_email
    end

    def timezone
      Rails.configuration.x.order_export.timezone
    end

    def schedule_weekdays
      Rails.configuration.x.order_export.schedule_weekdays
    end

    def schedule_hour
      Rails.configuration.x.order_export.schedule_hour
    end

    def schedule_minute
      Rails.configuration.x.order_export.schedule_minute
    end

    # Compute the next scheduled run time (UTC) after `from_time` (defaults to now).
    # The returned Time is the configured local scheduled time converted to UTC.
    #
    # This function iterates up to 7 days looking for the next weekday that matches
    # `schedule_weekdays`. It compares using the configured timezone to avoid DST issues.
    def next_scheduled_for(from_time = Time.current)
      tz = ActiveSupport::TimeZone[timezone]
      raise "Unknown timezone #{timezone}" unless tz

      # Use a TimeWithZone in the configured timezone for consistent comparisons
      local_from = from_time.in_time_zone(tz)

      # Check today + next 7 days
      (0..7).each do |offset|
        candidate_date = (local_from.to_date + offset)
        candidate_local = tz.local(candidate_date.year, candidate_date.month, candidate_date.day,
                                   schedule_hour, schedule_minute, 0)

        # wday is 0-6 (Sunday..Saturday)
        if schedule_weekdays.include?(candidate_local.wday)
          # We want the next scheduled time strictly after the given from_time.
          # Compare candidate_local vs local_from to account for timezone and DST.
          return candidate_local.utc if candidate_local > local_from
        end
      end

      # Fallback: schedule for the next matching weekday exactly one week from today
      future = local_from + 7.days
      (0..7).each do |offset|
        candidate_date = (future.to_date + offset)
        candidate_local = tz.local(candidate_date.year, candidate_date.month, candidate_date.day,
                                   schedule_hour, schedule_minute, 0)
        return candidate_local.utc if schedule_weekdays.include?(candidate_local.wday)
      end
    end

    # Returns a human-friendly window label for use in the email subject per-spec.
    # Given a scheduled_for UTC time, computes the proper label:
    # - If scheduled falls on Monday (local), label "Fri-Mon 7am <MM/DD/YYYY>"
    # - If Wednesday => "Mon-Wed 7am <MM/DD/YYYY>"
    # - If Friday => "Wed-Fri 7am <MM/DD/YYYY>"
    # The date included is the scheduled date in America/New_York (MM/DD/YYYY).
    def window_label_for(scheduled_for_utc)
      tz = ActiveSupport::TimeZone[timezone]
      local = scheduled_for_utc.in_time_zone(tz)
      date_str = local.strftime('%m/%d/%Y')

      case local.wday
      when 1 # Monday
        "Fri-Mon 7am #{date_str}"
      when 3 # Wednesday
        "Mon-Wed 7am #{date_str}"
      when 5 # Friday
        "Wed-Fri 7am #{date_str}"
      else
        # Generic fallback
        "#{date_str} #{local.strftime('%H:%M %Z')}"
      end
    end
  end
end
