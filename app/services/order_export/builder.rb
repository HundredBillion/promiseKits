# frozen_string_literal: true
#
# Service: OrderExport::Builder
#
# Purpose:
# - Build an Excel (.xlsx) file containing the given set of orders.
# - Returns a Tempfile opened in binary mode containing the .xlsx content.
#
# Usage:
#   orders = Order.where(created_at: start..finish).order(:created_at)
#   tmpfile = OrderExport::Builder.build_to_tempfile(orders: orders)
#   # attach tmpfile.path to mailer, then ensure unlink/close when done
#
# Notes:
# - Uses the `caxlsx` gem (Axlsx-compatible API).
# - The method returns a Tempfile that the caller is responsible for closing/unlinking.
# - We format `order_confirmation` as a zero-padded 6-digit string to match UI formatting.
#
require 'tempfile'
require 'caxlsx'

module OrderExport
  class Builder
    # Public: build an .xlsx file containing provided orders.
    #
    # Params:
    # - orders: ActiveRecord::Relation or Array of Order records (ordered as desired)
    # - opts: Hash of options (not required)
    #   - sheet_name: name for the Excel sheet (default: "Orders")
    #
    # Returns:
    # - Tempfile containing the .xlsx binary (the file is not unlinked; caller should unlink when done)
    #
    def self.build_to_tempfile(orders:, opts: {})
      raise ArgumentError, "orders is required" if orders.nil?

      sheet_name = opts.fetch(:sheet_name, 'Orders')

      # Ensure we have an array or relation we can iterate multiple times
      orders_enum = orders.respond_to?(:to_a) ? orders.to_a : Array(orders)

      # Create a temp file for binary xlsx output
      tmp = Tempfile.new(['orders_export', '.xlsx'])
      tmp.binmode

      package = Axlsx::Package.new
      workbook = package.workbook

      # Styles
      header_style = workbook.styles.add_style(b: true, sz: 12, alignment: { horizontal: :center })
      date_style = workbook.styles.add_style(format_code: 'yyyy-mm-dd hh:mm:ss')

      workbook.add_worksheet(name: sheet_name) do |sheet|
        # Header row (column names)
        sheet.add_row header_columns, style: header_style

        # Add rows in batches to limit memory pressure (we already have orders in memory likely)
        # We'll iterate and append rows; caxlsx builds the file in memory until serialize is called.
        orders_enum.each do |order|
          sheet.add_row row_for(order), style: [nil, date_style] + Array.new(header_columns.count - 2)
        end
      end

      # Serialize to tempfile
      package.serialize(tmp.path)

      # Rewind so caller can read from start
      tmp.rewind

      tmp
    end

    # Define the header columns. These correspond to the orders table columns,
    # plus friendly names for related fields.
    def self.header_columns
      [
        'id',
        'order_confirmation',
        'created_at_utc',
        'first_name',
        'last_name',
        'email',
        'phone',
        'address1',
        'address2',
        'city',
        'state',
        'zip',
        'promise_fitness_kit',
        'coupon_code',
        'description'
      ]
    end

    # Prepare a single row array for an Order instance.
    # Order: expected association `promise_fitness_kit` and `coupon_code` (may be nil).
    def self.row_for(order)
      [
        order.id,
        formatted_order_confirmation(order.order_confirmation),
        order.created_at.utc.iso8601,
        order.first_name,
        order.last_name,
        order.email,
        order.formatted_phone rescue order.phone,
        order.address1,
        order.address2,
        order.city,
        order.state,
        order.zip,
        promise_fitness_kit_label(order.promise_fitness_kit),
        coupon_code_label(order.coupon_code),
        order.description
      ]
    end

    def self.formatted_order_confirmation(value)
      return nil if value.nil?
      # Ensure we coerce to integer then format with zero padding to 6 digits
      sprintf('%06d', value.to_i)
    end
    private_class_method :formatted_order_confirmation

    def self.promise_fitness_kit_label(kit)
      return nil if kit.nil?
      # Prefer name (human-readable), fallback to slug or id
      kit.name.presence || kit.slug.presence || kit.id
    end
    private_class_method :promise_fitness_kit_label

    def self.coupon_code_label(coupon)
      return nil if coupon.nil?
      coupon.code.presence || coupon.id
    end
    private_class_method :coupon_code_label
  end
end
