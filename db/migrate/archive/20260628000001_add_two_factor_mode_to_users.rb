class AddTwoFactorModeToUsers < ActiveRecord::Migration[8.1]
  def change
    # 'authenticator' = TOTP via app (QR code); 'whatsapp' = TOTP auto-sent via WhatsApp
    add_column :users, :two_factor_mode, :string, default: "authenticator", null: false
  end
end
