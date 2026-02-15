# frozen_string_literal: true

class CreateOrderExports < ActiveRecord::Migration[8.1]
  def change
    create_table :order_exports do |t|
      t.string   :status,        null: false, default: "pending"
      t.datetime :scheduled_for, null: false
      t.datetime :started_at
      t.datetime :ends_at
      t.string   :recipient
      t.string   :filename
      t.text     :error_message

      t.timestamps
    end

    add_index :order_exports, :scheduled_for
    add_index :order_exports, :status

    create_table :exported_orders do |t|
      t.references :order_export, null: false, foreign_key: { to_table: :order_exports, on_delete: :restrict }, index: true
      t.references :order,        null: false, foreign_key: { to_table: :orders, on_delete: :restrict },       index: true

      t.timestamps
    end

    # Enforce exactly-once semantics: an Order may be exported at most once.
    add_index :exported_orders, :order_id, unique: true, name: "index_exported_orders_on_order_id_unique"
  end
end
