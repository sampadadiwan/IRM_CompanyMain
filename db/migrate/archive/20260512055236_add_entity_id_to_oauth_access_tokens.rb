class AddEntityIdToOauthAccessTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_access_tokens, :entity_id, :bigint, null: true
    add_index :oauth_access_tokens, :entity_id
  end
end
