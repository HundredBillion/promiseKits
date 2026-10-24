class TrackExportJobAndDeliveryReview < ActiveRecord::Migration[8.1]
  def change
    add_column :order_exports, :job_id, :string
    add_index :order_exports, :job_id, unique: true
  end
end
