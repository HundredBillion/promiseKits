# frozen_string_literal: true
#
# Model: ExportedOrder
#
# Join model linking an Order to the OrderExport run that exported it.
# Enforces DB- and application-level uniqueness so a given Order is exported
# at most once (per current product acceptance criteria).
#
class ExportedOrder < ApplicationRecord
  belongs_to :order_export, inverse_of: :exported_orders
  belongs_to :order, inverse_of: :exported_order

  validates :order_export, presence: true
  validates :order, presence: true
  validates :order_id, uniqueness: true

  # Convenience delegate to surface export metadata from the joined export record
  delegate :scheduled_for, :ends_at, to: :order_export, allow_nil: true

  # Helpful scopes
  scope :for_export, ->(export_id) { where(order_export_id: export_id) }
  scope :for_order, ->(order_id) { where(order_id: order_id) }

  # Return a human-friendly identification used in admin views/logs
  def to_s
    "ExportedOrder(order_id=#{order_id}, export_id=#{order_export_id})"
  end
end
