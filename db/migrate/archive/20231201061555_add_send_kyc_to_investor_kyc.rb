class AddSendKycToInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_kycs, :send_kyc_form_to_user, :boolean, default: false
    add_column :investor_kycs, :notification_msg, :text
  end
end
