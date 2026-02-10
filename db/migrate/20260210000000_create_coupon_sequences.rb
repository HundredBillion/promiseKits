class CreateCouponSequences < ActiveRecord::Migration[8.1]
  def change
    create_table :coupon_sequences do |t|
      t.string  :name, null: false, default: 'default'
      t.integer :last_sequence, null: false, default: 999
      t.timestamps
    end

    add_index :coupon_sequences, :name, unique: true
  end
end
