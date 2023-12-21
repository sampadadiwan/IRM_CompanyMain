class AddEsignEmailsToCapitalCommitment < ActiveRecord::Migration[7.1]
  def change
    add_column :capital_commitments, :esign_emails, :string
    add_column :investor_kycs, :esign_emails, :string

    CapitalCommitment.where.not(investor_signatory_id: nil).each do |cc|
      cc.update_column(:esign_emails, cc.investor_signatory.email)
    end
  end
end
