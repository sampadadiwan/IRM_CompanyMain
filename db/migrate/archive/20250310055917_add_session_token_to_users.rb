class AddSessionTokenToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :session_token, :string
    User.where(session_token: nil).find_each do |user|
      user.update_columns(session_token: SecureRandom.hex(64))
    end
  end
end
