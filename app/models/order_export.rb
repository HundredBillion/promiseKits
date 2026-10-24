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
#  - build file using OrderExportBuilder and email via Admin::OrderExportMailer
#  - on success: mark_succeeded!(filename)
#  - on failure before delivery: mark_failed!(error_message)
#  - after delivery starts, an uncertain outcome requires review
#
class OrderExport < ApplicationRecord
  has_many :exported_orders, inverse_of: :order_export, dependent: :restrict_with_exception
  has_many :orders, through: :exported_orders

  enum :status, {
    pending: "pending",
    running: "running",
    succeeded: "succeeded",
    failed: "failed",
    review_required: "review_required"
  }

  validates :status, presence: true
  validates :scheduled_for, presence: true

  def self.last_successful
    where(status: "succeeded").order(ends_at: :desc).limit(1).first
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

    with_lock { reserve_orders_locked!(ends_at: ends_at, starts_at: starts_at) }
  end

  private

  def reserve_orders_locked!(ends_at:, starts_at:)
    if started_at.present?
      update!(status: "running", error_message: nil)
      return orders.order(:created_at)
    end

    starts_at ||= self.class.last_successful&.ends_at

    # Select candidate order ids in deterministic order.
    scope = ::Order.all
    scope = scope.where("created_at > ?", starts_at) if starts_at.present?
    scope = scope.where("created_at <= ?", ends_at)
    order_ids = scope.order(:created_at).pluck(:id)

    # The unique index on order_id decides which concurrent export owns each order.
    self.transaction do
      update!(status: "running", started_at: Time.current.utc, ends_at: ends_at)

      order_ids.each_slice(500) do |batch|
        rows = batch.map { |order_id| { order_export_id: id, order_id: order_id } }
        ExportedOrder.insert_all(rows, unique_by: :index_exported_orders_on_order_id_unique, record_timestamps: true)
      end
    end

    orders.order(:created_at)
  end

  public

  # Convenience: number of orders reserved for this export
  def reserved_count
    exported_orders.count
  end

  # Mark export succeeded and persist the filename used
  def mark_succeeded!(filename = nil)
    update!(status: "succeeded", filename: filename, error_message: nil)
  end

  # Mark export failed and record error message
  def mark_failed!(error_message = nil)
    timestamp = Time.current.utc
    changed = self.class.where(id: id, status: [ "pending", "running", "failed" ], delivery_started_at: nil)
      .update_all(status: "failed", error_message: error_message.to_s, updated_at: timestamp)
    reload if changed == 1
    changed == 1
  end

  def mark_review_required!(error_message = nil)
    timestamp = Time.current.utc
    changed = self.class.where(id: id, status: [ "running", "review_required" ]).where.not(delivery_started_at: nil)
      .update_all(status: "review_required", error_message: error_message.to_s, updated_at: timestamp)
    reload if changed == 1
    changed == 1
  end

  def begin_delivery!
    timestamp = Time.current.utc
    claimed = self.class.where(id: id, status: "running", delivery_started_at: nil)
      .update_all(delivery_started_at: timestamp, updated_at: timestamp)
    reload if claimed == 1
    claimed == 1
  end

  def confirm_undelivered!
    timestamp = Time.current.utc
    changed = self.class.where(id: id, status: "review_required").where.not(delivery_started_at: nil)
      .update_all(status: "failed", delivery_started_at: nil, error_message: "Admin confirmed delivery was not received", updated_at: timestamp)
    reload if changed == 1
    changed == 1
  end
end
