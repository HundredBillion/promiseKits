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
#  - on failure: mark_failed!(error_message)
#
class OrderExport < ApplicationRecord
  has_many :exported_orders, inverse_of: :order_export, dependent: :restrict_with_exception
  has_many :orders, through: :exported_orders

  enum :status, {
    pending: "pending",
    running: "running",
    succeeded: "succeeded",
    failed: "failed"
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

    starts_at ||= self.class.last_successful&.ends_at

    # Select candidate order ids in deterministic order.
    scope = ::Order.all
    scope = scope.where("created_at > ?", starts_at) if starts_at.present?
    scope = scope.where("created_at <= ?", ends_at)
    order_ids = scope.order(:created_at).pluck(:id)

    # Prepare for reservation
    reserved_ids = []

    # Use DB-optimized bulk insert on Postgres, fall back to batched per-row inserts otherwise.
    self.transaction do
      update!(status: "running", started_at: Time.current.utc, ends_at: ends_at)

      conn = ActiveRecord::Base.connection
      adapter = conn.adapter_name.to_s.downcase

      if adapter.include?("post") && order_ids.any?
        # Postgres: bulk insert with ON CONFLICT DO NOTHING for efficiency and concurrency-safety.
        # Build a VALUES list safely by quoting each element.
        now_sql = conn.quote(Time.current.utc)
        values_sql = order_ids.map do |oid|
          "(#{conn.quote(id)}, #{conn.quote(oid)}, #{now_sql}, #{now_sql})"
        end.join(", ")

        sql = <<~SQL.squish
          INSERT INTO exported_orders (order_export_id, order_id, created_at, updated_at)
          VALUES #{values_sql}
          ON CONFLICT (order_id) DO NOTHING
        SQL

        conn.execute(sql)

        # Determine which ids were successfully reserved for this export.
        reserved_ids = ExportedOrder.where(order_export_id: id, order_id: order_ids).pluck(:order_id)
      else
        # Non-Postgres or fallback: perform batched per-row creates and gracefully handle uniqueness conflicts.
        order_ids.each_slice(500) do |batch|
          batch.each do |oid|
            begin
              ExportedOrder.create!(order_export_id: id, order_id: oid)
              reserved_ids << oid
            rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
              # Skip orders reserved concurrently or invalid entries.
              next
            end
          end
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
    update!(status: "succeeded", filename: filename, error_message: nil)
  end

  # Mark export failed and record error message
  def mark_failed!(error_message = nil)
    update!(status: "failed", error_message: error_message.to_s)
  end
end
