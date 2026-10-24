class EnforceOneOrderPerCoupon < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    duplicates = select_rows(<<~SQL)
      SELECT coupon_code_id, COUNT(*)
      FROM orders
      GROUP BY coupon_code_id
      HAVING COUNT(*) > 1
    SQL
    if duplicates.any?
      examples = duplicates.first(10).map { |id, count| "#{id} (#{count} orders)" }.join(", ")
      raise ActiveRecord::MigrationError, "Resolve #{duplicates.size} duplicate coupon groups before adding the unique index: #{examples}"
    end

    options = { unique: true, name: "index_orders_on_coupon_code_id_unique" }
    options[:algorithm] = :concurrently if connection.adapter_name.downcase.include?("postgres")
    add_index :orders, :coupon_code_id, **options

  end

  def down
    options = { name: "index_orders_on_coupon_code_id_unique" }
    options[:algorithm] = :concurrently if connection.adapter_name.downcase.include?("postgres")
    remove_index :orders, **options
  end
end
