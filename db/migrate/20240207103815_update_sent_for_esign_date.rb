class UpdateSentForEsignDate < ActiveRecord::Migration[7.1]
  def change
    # for all docs sent for esign update sent_for_esign_date to doc creation date
    Document.where(sent_for_esign: true, sent_for_esign_date: nil).each do |doc|
      p "Updating sent_for_esign_date for doc #{doc.id} to #{doc.created_at}"
      doc.update_column(:sent_for_esign_date, doc.created_at)
    end
  end
end
