# frozen_string_literal: true

module Admin
  class OrderExportMailer < ApplicationMailer
    # Default sender — override with ENV or application config if desired
    default from: -> { ENV.fetch('DEFAULT_FROM_EMAIL', 'no-reply@example.com') }

    # Sends an email with the generated Excel attachment.
    #
    # Params:
    # - recipient: String email address to send to (required)
    # - file_path: path to the generated .xlsx Tempfile (required)
    # - filename: filename to use for the attachment (required)
    # - export_id: optional OrderExport id (used to compute total count / audit)
    # - scheduled_for: optional Time/DateTime representing the scheduled run time (UTC). If omitted, Time.current is used.
    # - exported_count: optional Integer provided by the job to avoid extra DB queries
    #
    # Subject formatting (per spec):
    # - Monday run  => "<total> Orders Fri-Mon 7am <MM/DD/YYYY>"
    # - Wednesday   => "<total> Orders Mon-Wed 7am <MM/DD/YYYY>"
    # - Friday      => "<total> Orders Wed-Fri 7am <MM/DD/YYYY>"
    #
    # The date in the subject is the scheduled run date expressed in America/New_York.
    def export_email(recipient:, file_path:, filename:, export_id: nil, scheduled_for: nil, exported_count: nil)
      raise ArgumentError, "recipient is required" if recipient.blank?
      raise ArgumentError, "file_path is required" if file_path.blank?
      raise ArgumentError, "filename is required" if filename.blank?

      @export = OrderExport.find_by(id: export_id) if export_id.present?

      # Determine the scheduled time (use provided scheduled_for or now).
      scheduled_for_utc = if scheduled_for.present?
                            scheduled_for.to_time.utc
                          else
                            Time.current.utc
                          end

      # Determine window label using centralized config helper so formatting is consistent
      # Fallback to a simple date label if helper not available.
      window_label = if defined?(OrderExport::Config) && OrderExport::Config.respond_to?(:window_label_for)
                       OrderExport::Config.window_label_for(scheduled_for_utc)
                     else
                       scheduled_for_utc.in_time_zone('America/New_York').strftime('%b %d %Y')
                     end

      # Use exported_count if caller/job provided it; otherwise fall back to export record count if available.
      total_count = if exported_count.present?
                      exported_count.to_i
                    elsif @export.present?
                      @export.reserved_count
                    else
                      0
                    end

      mail_subject = "#{total_count} Orders #{window_label}"

      # Attach the generated file if present. Read in binary mode.
      if File.exist?(file_path)
        attachments[filename] = {
          mime_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          content: File.binread(file_path)
        }
      else
        # If file missing, still send an alert-style email (should be rare)
        Rails.logger.warn("[OrderExportMailer] Attachment not found at #{file_path} for export_id=#{export_id}")
      end

      # Compose body with a small summary and audit reference
      @recipient = recipient
      @scheduled_for = scheduled_for_utc
      @export_id = @export&.id
      @total_count = total_count
      @window_label = window_label

      mail(to: recipient, subject: mail_subject) do |format|
        format.text do
          render plain: <<~TEXT
            Please find attached the orders export (#{@total_count} orders).
            Export window: #{@window_label}
            Scheduled (UTC): #{@scheduled_for.utc.iso8601}
            Export ID: #{@export_id || 'n/a'}

            If you have any questions, reply to this email.
          TEXT
        end

        format.html do
          render html: <<~HTML.html_safe
            <p>Please find attached the orders export (<strong>#{@total_count}</strong> orders).</p>
            <p><strong>Export window:</strong> #{@window_label}</p>
            <p><strong>Scheduled (UTC):</strong> #{@scheduled_for.utc.iso8601}</p>
            <p><strong>Export ID:</strong> #{@export_id || 'n/a'}</p>
          HTML
        end
      end
    end
  end
end
