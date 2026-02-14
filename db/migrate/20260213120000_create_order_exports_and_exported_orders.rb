class CreateOrderExportsAndExportedOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :order_exports do |t|
      t.string  :status, null: false, default: "pending"   # pending, running, succeeded, failed
      t.datetime :scheduled_for, precision: 6                # the intended schedule time (UTC)
      t.datetime :started_at, precision: 6
      t.datetime :ends_at, precision: 6                      # inclusive upper bound for included orders (UTC)
      t.string  :recipient                                   # email recipient for this run
      t.string  :filename                                    # generated filename (for audit)
      t.text    :error_message
      t.timestamps
    end

    add_index :order_exports, :scheduled_for
    add_index :order_exports, :status

    create_table :exported_orders do |t|
      t.references :order_export, null: false, foreign_key: { to_table: :order_exports }, index: true
      t.references :order, null: false, foreign_key: true
      t.timestamps
    end

    # Enforce that an order can only be assigned to a single export.
    # This provides a strong DB-level guard against duplicate exports of the same order.
    add_index :exported_orders, :order_id, unique: true

    # Optional: an index to quickly find all exported_orders for a given export run
    add_index :exported_orders, [:order_export_id, :created_at], name: "index_exported_orders_on_export_and_created_at"
  end
end
