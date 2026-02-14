class CreateSequences < ActiveRecord::Migration[8.1]
  def change
    create_table :sequences do |t|
      t.string  :name,        null: false
      t.integer :last_value,  null: false, default: 0
      t.text    :description
      t.timestamps
    end

    add_index :sequences, :name, unique: true

    reversible do |dir|
      dir.up do
        # If an orders table exists, initialize a sequence for order confirmations
        # to the current maximum so we don't accidentally reuse existing numbers.
        if table_exists?(:orders)
          max = select_value("SELECT COALESCE(MAX(order_confirmation), 0) FROM orders").to_i

          # Use INSERT OR IGNORE so running the migration twice doesn't error.
          execute <<~SQL
            INSERT OR IGNORE INTO sequences (name, last_value, created_at, updated_at)
            VALUES ('order_confirmation', #{max}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
          SQL
        end
      end
    end
  end
end
