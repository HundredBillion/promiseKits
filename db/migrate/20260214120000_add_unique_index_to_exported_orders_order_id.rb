class AddUniqueIndexToExportedOrdersOrderId < ActiveRecord::Migration[8.1]
  # Add a unique index on exported_orders.order_id to enforce exactly-once semantics.
  #
  # Notes:
  # - If a non-unique index on :order_id already exists, we remove it first so we can
  #   create a uniquely-named unique index. This keeps schema.rb tidy and avoids
  #   duplicate-index confusion.
  # - In very large Postgres deployments you may want to create the unique index
  #   CONCURRENTLY to avoid locking; this migration uses the straightforward approach
  #   for compatibility with SQLite and typical CI/dev environments. If you need
  #   concurrent index creation in prod, replace the add_index call with an
  #   algorithm: :concurrently variant and use disable_ddl_transaction! at the class level.
  #
  # Also: after applying this migration, ensure the admin routes include:
  #   namespace :admin do
  #     resource :order_exports, only: [:new, :create], controller: 'admin/order_exports'
  #   end
  #
  def up
    # If the unique index already exists, nothing to do.
    return if index_exists?(:exported_orders, :order_id, unique: true)

    # If a non-unique index exists on order_id, remove it to avoid duplicate index names.
    if index_exists?(:exported_orders, :order_id) && !index_exists?(:exported_orders, :order_id, unique: true)
      begin
        remove_index :exported_orders, column: :order_id
      rescue StandardError => e
        warn "Could not remove existing non-unique index on exported_orders.order_id: #{e.class}: #{e.message}"
        # continue — attempt to add the unique index anyway
      end
    end

    begin
      add_index :exported_orders, :order_id, unique: true, name: 'index_exported_orders_on_order_id_unique'
    rescue StandardError => e
      warn "Failed to create unique index on exported_orders.order_id: #{e.class}: #{e.message}"
      raise
    end
  end

  def down
    if index_exists?(:exported_orders, :order_id, unique: true)
      remove_index :exported_orders, name: 'index_exported_orders_on_order_id_unique'
    end

    # Restore a non-unique index if one does not exist to preserve prior lookup performance.
    unless index_exists?(:exported_orders, :order_id)
      add_index :exported_orders, :order_id, name: 'index_exported_orders_on_order_id'
    end
  end
end
