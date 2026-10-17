# The device registry for the LP mobile app: one row per user per app install, binding the
# phone's current devise-api token and its Expo push address together so that signing a phone
# out ends both at once.
# openspec/changes/lp-mobile-app — design card ③. Worked examples E5, E6, E7, E8, X5, X6, X15.
class CreateMobileDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :mobile_devices do |t|
      t.references :user, null: false, foreign_key: true, index: false
      # Nullified when the token row is purged; a device without a token is signed out
      t.references :devise_api_token, foreign_key: { on_delete: :nullify }
      # Generated once per install by the app and kept in secure storage (E6)
      t.string :install_id, limit: 64, null: false
      t.string :platform, limit: 10, null: false
      t.string :name, limit: 100
      t.string :app_version, limit: 20
      t.string :region_code, limit: 10, null: false
      t.string :push_token, limit: 255
      t.boolean :push_enabled, null: false, default: true
      t.string :push_status, limit: 20, null: false, default: "none"
      t.datetime :last_used_at, null: false
      t.datetime :last_push_at
      t.datetime :revoked_at
      t.string :revoked_reason, limit: 30
      t.timestamps

      # Upsert key — the same install signing in again reuses its row (E6)
      t.index %i[user_id install_id], unique: true
      # One push address belongs to one device (E7)
      t.index :push_token, unique: true
      # live / pushable / least-recently-used lookups (E5, E8)
      t.index %i[user_id revoked_at last_used_at], name: "idx_mobile_devices_live"
    end
  end
end
