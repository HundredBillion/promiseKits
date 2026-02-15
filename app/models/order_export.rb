# frozen_string_literal: true

# Model: OrderExport
#
# Tracks export runs that collect a set of orders and produce an export file.
# Each OrderExport has many ExportedOrder rows which list the orders assigned
# to that run. The exported_orders table has a unique index on order_id to
# ensure a given Order is exported at most once (DB-level guard).
#
# Typical lifecycle:
#  - status: 'pending' (created by scheduler or UI)
#  - call `reserve_orders!(ends_at: ...)` to atomically reserve orders for this run.
#  - status -> 'running'
#  - build file using OrderExport::Builder and email via Admin::OrderExportMailer
#  - on success: mark_succeeded!(filename)
#  - on failure: mark_failed!(error_message)
#
class OrderExport < ApplicationRecord
  has_many :exported_orders, dependent: :restrict_with_exception
  has_many :orders, through: :exported_orders

  enum status: {
    pending: 'pending',
    running: 'running',
    succeeded: 'succeeded',
    failed: 'failed'
  }

  validates :status, presence: true
  validates :scheduled_for, presence: true

  # Returns the most recent successful export (or nil)
  def self.last_successful
    where(status: 'succeeded').order(ends_at: :desc).limit(1).first
  end

  # Atomically reserve orders for inclusion in this export.
  #
  # Behavior:
  # - Determine `starts_at` (if not provided) from the most recent successful export.
  # - Select orders where (created_at > starts_at) AND (created_at <= ends_at).
  # - Create ExportedOrder rows linking those orders to this export inside a transaction.
  # - If a unique constraint prevents creating a row (concurrent reservation), the conflict is skipped.
  #
  # Returns an ActiveRecord::Relation of Order records that were reserved for this export.
  #
  # Params:
  # - ends_at: DateTime (UTC) inclusive upper bound for orders to include (required)
  # - starts_at: DateTime (UTC) exclusive lower bound; if nil, derived from last successful export
  def reserve_orders!(ends_at:, starts_at: nil)
    raise ArgumentError, "ends_at is required" if ends_at.nil?

    starts_at ||= self.class.last_successful&.ends_at

    # Select candidate order ids in deterministic order.
    scope = ::Order.all
    scope = scope.where('created_at > ?', starts_at) if starts_at.present?
    scope = scope.where('created_at <= ?', ends_at)
    order_ids = scope.order(:created_at).pluck(:id)

    # Mark this export as running and set ends_at / started_at inside the transaction.
    reserved_ids = []
    self.transaction do
      update!(status: 'running', started_at: Time.current.utc, ends_at: ends_at)

      # Insert ExportedOrder rows. We handle uniqueness violations gracefully,
      # because another concurrent worker may have exported some of these orders.
      order_ids.each do |oid|
        begin
          ExportedOrder.create!(order_export_id: id, order_id: oid)
          reserved_ids << oid
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          # Skip orders that were reserved by a concurrent transaction.
          # They are not part of this export.
          next
        end
      end
    end

    # Return the reserved orders in chronological order
    ::Order.where(id: reserved_ids).order(:created_at)
  end

  # Convenience: number of orders reserved for this export
  def reserved_count
    exported_orders.count
  end

  # Mark export succeeded and persist the filename used
  def mark_succeeded!(filename = nil)
    update!(status: 'succeeded', filename: filename, error_message: nil)
  end

  # Mark export failed and record error message
  def mark_failed!(error_message = nil)
    update!(status: 'failed', error_message: error_message.to_s)
  end
end
