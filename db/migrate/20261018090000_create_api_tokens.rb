# Profile › API tokens: a user's named integration token over one devise-api token, so it can be
# listed, limited and revoked without touching the gem's table. Same shape as mobile_devices.
# openspec/changes/funds-json-api-hardening — design card ①. Worked examples H10–H12, E9–E11, X16–X21.
class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true, index: false
      # The devise-api token this row names; revoking the row revokes it
      t.references :devise_api_token, null: false, foreign_key: true, index: { unique: true }
      t.string :name, limit: 100, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps

      # Live-token count and the list (MAX_LIVE per user)
      t.index %i[user_id revoked_at]
    end
  end
end
