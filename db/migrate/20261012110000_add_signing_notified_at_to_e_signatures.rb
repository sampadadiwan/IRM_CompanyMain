# Marks that a signer has been told it is their turn for the current signature request, so the bell entry and
# the email go out once however many times a webhook or status check confirms the earlier signature.
# Cleared by Re-Send. Nullable, no default: null means "not yet notified".
# openspec/changes/embedded-esign-digio — design card ⑨, LLD › Schema Detail.
class AddSigningNotifiedAtToESignatures < ActiveRecord::Migration[8.1]
  def change
    add_column :e_signatures, :signing_notified_at, :datetime
  end
end
