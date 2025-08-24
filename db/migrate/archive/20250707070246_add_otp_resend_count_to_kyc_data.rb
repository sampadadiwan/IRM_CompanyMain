class AddOtpResendCountToKycData < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:kyc_data, :otp_resend_count)
      add_column :kyc_data, :otp_resend_count, :integer, default: 0, null: false
    end
    unless column_exists?(:kyc_data, :otp_sent_at)
      add_column :kyc_data, :otp_sent_at, :datetime
    end
  end
end
