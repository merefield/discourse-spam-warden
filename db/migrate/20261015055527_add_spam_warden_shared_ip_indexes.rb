# frozen_string_literal: true

class AddSpamWardenSharedIpIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_warden_users_registration_ip"
    add_index :users,
              %i[registration_ip_address created_at],
              name: :idx_warden_users_registration_ip,
              algorithm: :concurrently
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_warden_user_ip_address_histories_ip"
    add_index :user_ip_address_histories,
              %i[ip_address updated_at],
              name: :idx_warden_user_ip_address_histories_ip,
              algorithm: :concurrently
  end

  def down
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_warden_users_registration_ip"
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_warden_user_ip_address_histories_ip"
  end
end
