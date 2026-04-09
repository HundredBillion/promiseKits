class RenameAdminsToAdminUsers < ActiveRecord::Migration[8.1]
  def change
    rename_table :admins, :admin_users
  end
end
