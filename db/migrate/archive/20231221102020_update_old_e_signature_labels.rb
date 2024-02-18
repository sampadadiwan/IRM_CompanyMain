class UpdateOldESignatureLabels < ActiveRecord::Migration[7.1]
  def change
    ActiveRecord::Base.transaction do
      ESignature.all.each do |esign|
        if esign.label.present? && ["Fund Signatory", "Investor Signatory"].include?(esign.label)
          esign.label = esign.label.pluralize
          esign.update_column(:label, esign.label)
        end
        if esign.user.present? && esign.email.blank?
          esign.email = esign.user.email
          esign.update_column(:email, esign.email)
        end
      end
    end
  end
end
