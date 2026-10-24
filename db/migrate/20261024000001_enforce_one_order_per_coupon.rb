class EnforceOneOrderPerCoupon < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    name = "index_orders_on_coupon_code_id_unique"
    postgres = connection.adapter_name.downcase.include?("postgres")
    if postgres
      valid = select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = to_regclass(#{connection.quote(name)})")
      return if valid == true || valid == "t"

      remove_index :orders, name: name, algorithm: :concurrently if valid == false || valid == "f"
    end

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

    options = { unique: true, name: name }
    options[:algorithm] = :concurrently if postgres
    begin
      add_index :orders, :coupon_code_id, **options
    rescue ActiveRecord::StatementInvalid => error
      remove_index :orders, name: name, algorithm: :concurrently if postgres && index_exists?(:orders, :coupon_code_id, name: name)
      raise ActiveRecord::MigrationError, "Unique coupon index could not be created; check for concurrent duplicate redemptions: #{error.message}"
    end
  end

  def down
    options = { name: "index_orders_on_coupon_code_id_unique" }
    options[:algorithm] = :concurrently if connection.adapter_name.downcase.include?("postgres")
    remove_index :orders, **options
  end
end
