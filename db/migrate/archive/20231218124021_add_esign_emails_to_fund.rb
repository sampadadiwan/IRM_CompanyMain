class AddEsignEmailsToFund < ActiveRecord::Migration[7.1]
  def change
    add_column :funds, :esign_emails, :string
    Fund.where.not(fund_signatory_id: nil).each do |f|
      emails = [f.fund_signatory&.email, f.trustee_signatory&.email].compact.uniq.join(",")
      f.update_column(:esign_emails, emails)
    end
  end
end
