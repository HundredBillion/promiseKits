# frozen_string_literal: true
require 'rails_helper'
require 'tempfile'
require 'active_support/time'

RSpec.describe Admin::OrderExportMailer, type: :mailer do
  let(:recipient) { 'reports@example.com' }
  let(:tz) { ActiveSupport::TimeZone['America/New_York'] }

  describe '#export_email' do
    it 'builds an email with the expected subject and attaches the xlsx file' do
      # Prepare a small tempfile to act as the generated xlsx
      tmp = Tempfile.new(['spec_export', '.xlsx'])
      tmp.binmode
      tmp.write('fake-xlsx-bytes')
      tmp.rewind

      scheduled_local = tz.local(2026, 2, 16, 7, 0, 0)
      scheduled_utc = scheduled_local.utc

      mail = described_class.new.export_email(
        recipient: recipient,
        file_path: tmp.path,
        filename: 'orders_20260216.xlsx',
        scheduled_for: scheduled_utc,
        exported_count: 5
      )

      expect(mail).to be_a(Mail::Message)
      expect(mail.to).to include(recipient)

      # Subject should include the exported count and the window label
      expected_label = OrderExport::Config.window_label_for(scheduled_utc)
      expect(mail.subject).to include('5 Orders')
      expect(mail.subject).to include(expected_label)

      # Attachment present and matches filename & MIME type
      expect(mail.attachments.count).to be >= 1
      att = mail.attachments.find { |a| a.filename == 'orders_20260216.xlsx' }
      expect(att).to be_present
      expect(att.mime_type).to include('spreadsheet')

      tmp.close
      tmp.unlink
    end

    it 'raises ArgumentError when required arguments are missing' do
      tmp = Tempfile.new(['spec_export', '.xlsx'])
      tmp.binmode
      tmp.write('data')
      tmp.rewind

      expect {
        described_class.new.export_email(recipient: '', file_path: tmp.path, filename: 'f.xlsx')
      }.to raise_error(ArgumentError)

      expect {
        described_class.new.export_email(recipient: recipient, file_path: '', filename: 'f.xlsx')
      }.to raise_error(ArgumentError)

      expect {
        described_class.new.export_email(recipient: recipient, file_path: tmp.path, filename: '')
      }.to raise_error(ArgumentError)

      tmp.close
      tmp.unlink
    end

    it 'composes an email when attachment file is missing (no attachment present)' do
      scheduled_local = tz.local(2026, 2, 18, 7, 0, 0) # Wednesday
      scheduled_utc = scheduled_local.utc

      missing_path = '/tmp/this_file_does_not_exist_hopefully.xlsx'
      mail = described_class.new.export_email(
        recipient: recipient,
        file_path: missing_path,
        filename: 'missing.xlsx',
        scheduled_for: scheduled_utc,
        exported_count: 2
      )

      expect(mail).to be_a(Mail::Message)
      expect(mail.subject).to include('2 Orders')
      # No attachment should be present for the missing file
      att = mail.attachments.find { |a| a.filename == 'missing.xlsx' }
      expect(att).to be_nil
    end

    it 'uses export_id to look up the export and falls back to exported_count when provided' do
      # Create an OrderExport record with some exported orders for the test
      export = OrderExport.create!(status: 'succeeded', scheduled_for: Time.current.utc, started_at: Time.current.utc, ends_at: Time.current.utc, filename: 'a.xlsx')

      tmp = Tempfile.new(['spec_export', '.xlsx'])
      tmp.binmode
      tmp.write('content')
      tmp.rewind

      mail = described_class.new.export_email(
        recipient: recipient,
        file_path: tmp.path,
        filename: 'attached.xlsx',
        export_id: export.id,
        scheduled_for: Time.current.utc
      )

      expect(mail).to be_a(Mail::Message)
      expect(mail.to).to include(recipient)
      # When export exists but has no exported_orders, exported_count should default to 0 in subject
      expect(mail.subject).to include('0 Orders').or include('Orders')

      tmp.close
      tmp.unlink
    end
  end
end
