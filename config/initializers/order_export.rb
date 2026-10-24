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
#
Rails.application.configure do
  config.x.order_export = ActiveSupport::InheritableOptions.new(
    # Primary recipient for scheduled export emails. Can be overridden by ENV.
    recipient_email: ENV.fetch("ORDER_EXPORT_RECIPIENT", "reports@example.com"),

    from_email: ENV.fetch("ORDER_EXPORT_FROM", "no-reply@example.com"),

    # Timezone to use for scheduling and human-readable dates in emails.
    # Use the IANA timezone name. Spec requires America/New_York (EST/EDT).
    timezone: ENV.fetch("ORDER_EXPORT_TIMEZONE", "America/New_York"),

    # Scheduled weekdays for exporting (Ruby wday integers: 0 = Sunday, 1 = Monday, ... 6 = Saturday)
    # Spec: Monday, Wednesday, Friday
    schedule_weekdays: [ 1, 3, 5 ],

    # Scheduled local time (hour/minute) in the configured timezone
    schedule_hour: ENV.fetch("ORDER_EXPORT_HOUR", 7).to_i,
    schedule_minute: ENV.fetch("ORDER_EXPORT_MINUTE", 0).to_i
  )
end

# Lightweight helper module for order export scheduling & config access.
module OrderExportSettings
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

    def schedule_cron
      "#{schedule_minute} #{schedule_hour} * * #{schedule_weekdays.join(',')} #{timezone}"
    end

    def monthly_schedule_cron
      "#{schedule_minute} #{schedule_hour} 1 * * #{timezone}"
    end

    def schedule_description
      days = schedule_weekdays.map { |day| Date::ABBR_DAYNAMES.fetch(day) }.join("/")
      hour = schedule_hour % 12
      hour = 12 if hour.zero?
      period = schedule_hour < 12 ? "AM" : "PM"
      "#{days} at #{hour}:#{format('%02d', schedule_minute)} #{period} #{timezone}"
    end

    def window_label_for(scheduled_for_utc)
      tz = ActiveSupport::TimeZone[timezone]
      local = scheduled_for_utc.in_time_zone(tz)
      date_str = local.strftime("%m/%d/%Y")
      time_str = local.min.zero? ? local.strftime("%-I%P") : local.strftime("%-I:%M%P")

      case local.wday
      when 1
        "Fri-Mon #{time_str} #{date_str}"
      when 3
        "Mon-Wed #{time_str} #{date_str}"
      when 5
        "Wed-Fri #{time_str} #{date_str}"
      else
        "#{date_str} #{local.strftime('%H:%M %Z')}"
      end
    end
  end
end
