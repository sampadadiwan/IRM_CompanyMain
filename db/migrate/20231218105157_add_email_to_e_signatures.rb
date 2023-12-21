class AddEmailToESignatures < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:e_signatures, :email)
      add_column :e_signatures, :email, :string, limit: 60
    end
    update_emails
  end

  def update_emails
    ESignature.all.each do |es|
      if es.user && es.email.blank?
        Rails.logger.info "Updating email for esign #{es.id} - #{es.user.email}"
        # es.email = es.user&.email
        # es.save!
        es.update_column(:email, es.user.email)        
      else
        Rails.logger.info "No email for esign #{es.id}"
      end
    end
  end
end
