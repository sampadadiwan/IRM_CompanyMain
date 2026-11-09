# N1 (OWASP review 2026-11): which CapHive support user made an upload while signed in as a client.
#
# Imports run in a background job, after the request. By then User#support? cannot tell support acting as a
# client (session[:support_user_id], gone with the request) from the client, and import_uploads.user_id holds
# the client. Support-only rows (a Calculation custom field, whose meta_data is Ruby) need to know, so
# ImportUploadsController#create records the support user here. Nullable: nil for every upload a client makes
# and for every existing row.
class AddSupportUserIdToImportUploads < ActiveRecord::Migration[8.1]
  def change
    add_column :import_uploads, :support_user_id, :bigint, null: true
  end
end
