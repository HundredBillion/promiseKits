# frozen_string_literal: true

namespace :florida_orders do
  desc "Send Florida orders export email for previous month"
  task export: :environment do
    require "sidekiq-scheduler"

    # Get previous month
    prev_date = 1.month.ago
    year = prev_date.year
    month = prev_date.month

    recipient = ENV["ORDER_EXPORT_RECIPIENT"]
    if recipient.blank?
      puts "ERROR: No recipient configured. Set ORDER_EXPORT_RECIPIENT env variable."
      exit 1
    end

    puts "Running Florida orders export for #{Date.new(year, month, 1).strftime('%B %Y')}..."

    # Run the job directly
    job = AdminReports::FloridaOrdersExportJob.new
    job.perform(year, month, recipient: recipient)

    puts "Done!"
  end

  desc "Send Florida orders export for a specific month"
  task :export_for, [ :year, :month ] => :environment do |_t, args|
    require "sidekiq-scheduler"

    year = args[:year].to_i
    month = args[:month].to_i

    recipient = ENV["ORDER_EXPORT_RECIPIENT"]
    if recipient.blank?
      puts "ERROR: No recipient configured. Set ORDER_EXPORT_RECIPIENT env variable."
      exit 1
    end

    puts "Running Florida orders export for #{Date.new(year, month, 1).strftime('%B %Y')}..."

    job = AdminReports::FloridaOrdersExportJob.new
    job.perform(year, month, recipient: recipient)

    puts "Done!"
  end
end
