# Audit trail of what the embedded signing page reported (completed, closed, an error code), kept beside the
# other Digio payloads on the document's esign log. Nullable: most logs never get one.
# openspec/changes/embedded-esign-digio — design card ⑤, LLD › Schema Detail.
class AddSdkEventsToEsignLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :esign_logs, :sdk_events, :json
  end
end
