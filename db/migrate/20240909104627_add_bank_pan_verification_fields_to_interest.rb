class AddBankPanVerificationFieldsToInterest < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:interests, :pan_verification_response)
      add_column :interests, :pan_verification_response, :text
    end
    unless column_exists?(:interests, :pan_verification_status)
      add_column :interests, :pan_verification_status, :string
    end
    unless column_exists?(:interests, :pan_verified)
      add_column :interests, :pan_verified, :boolean
    end
    unless column_exists?(:interests, :bank_verification_response)
      add_column :interests, :bank_verification_response, :text
    end
    unless column_exists?(:interests, :bank_verification_status)
      add_column :interests, :bank_verification_status, :string
    end
    unless column_exists?(:interests, :bank_verified)
      add_column :interests, :bank_verified, :boolean
    end
  end
end
