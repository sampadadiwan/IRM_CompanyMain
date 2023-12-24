class ChangeNotNullTemplateForDocument < ActiveRecord::Migration[7.1]
  def change
    Document.with_deleted.where(template: nil).update_all(template: false)
    Document.with_deleted.where(sent_for_esign: nil).update_all(sent_for_esign: false)
    Document.with_deleted.where(approved: nil).update_all(approved: false)
    Document.with_deleted.where(signature_enabled: nil).update_all(signature_enabled: false)
    Document.with_deleted.where(locked: nil).update_all(locked: false)
    Document.with_deleted.where(send_email: nil).update_all(send_email: false)
    change_column_null :documents, :template, false
    change_column_null :documents, :sent_for_esign, false    
    change_column_null :documents, :approved, false    
    change_column_null :documents, :signature_enabled, false    
    change_column_null :documents, :locked, false    
    change_column_null :documents, :send_email, false    
  end
end
