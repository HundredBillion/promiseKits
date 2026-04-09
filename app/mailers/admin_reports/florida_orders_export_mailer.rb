# frozen_string_literal: true

module AdminReports
  class FloridaOrdersExportMailer < ApplicationMailer
    default from: -> { ENV.fetch("DEFAULT_FROM_EMAIL", "no-reply@example.com") }

    def florida_orders_email(recipient:, month_name:, summary:)
      @recipient = recipient
      @month_name = month_name
      @summary = summary

      total_kits = summary.sum { |kit| kit[:total] }

      mail(to: recipient, subject: "Florida Fitness Kit Orders - #{month_name}") do |format|
        format.text do
          render plain: text_content(total_kits)
        end

        format.html do
          render html: html_content(total_kits)
        end
      end
    end

    private

    def text_content(total_kits)
      lines = []
      lines << "Florida Fitness Kit Orders - #{@month_name}"
      lines << ""
      lines << "#{'Fitness Kit'.ljust(20)} #{'Total'}"
      lines << "#{'-' * 20} #{'-' * 5}"

      @summary.each do |kit|
        lines << "#{kit[:name].ljust(20)} #{kit[:total]}"
      end

      lines << ""
      lines << "Total: #{total_kits} kits"

      lines.join("\n")
    end

    def html_content(total_kits)
      rows = @summary.map do |kit|
        "<tr><td>#{kit[:name]}</td><td>#{kit[:total]}</td></tr>"
      end.join("\n")

      <<~HTML.html_safe
        <h2>Florida Fitness Kit Orders - #{@month_name}</h2>
        <table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse;">
          <thead>
            <tr style="background-color: #f0f0f0;">
              <th>Fitness Kit</th>
              <th>Total</th>
            </tr>
          </thead>
          <tbody>
            #{rows}
          </tbody>
          <tfoot>
            <tr style="background-color: #f0f0f0; font-weight: bold;">
              <td>Total</td>
              <td>#{total_kits}</td>
            </tr>
          </tfoot>
        </table>
      HTML
    end
  end
end
