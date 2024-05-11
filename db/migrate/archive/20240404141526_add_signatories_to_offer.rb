class AddSignatoriesToOffer < ActiveRecord::Migration[7.1]
  def change
    add_column :offers, :seller_signatory_emails, :string
    remove_column :offers, :esign_required
    remove_column :offers, :esign_provider
    remove_column :offers, :esign_link
    add_column :interests, :buyer_signatory_emails, :string
  end
end
