# ⑥/⑧ Kind-4 checks — "AI prepares, a person decides" (proposal › four kinds of content check):
# a duty whose trigger is a document input ({"document": "ppm"}) gets one occurrence per new document of
# that input on the fund (e.g. each new PPM version), due n days after upload, with the AI's notes
# attached when reading is on. The duty stays Due until a person marks it done (H44).
# Documents are those attached to the fund itself (R82). Re-runs create nothing twice (unique key).
# Worked examples H44 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceDocumentDuties
  def self.document_trigger?(duty)
    duty.dig("trigger", "document").present?
  end

  # From ComplianceDutyScheduler on each run
  def self.schedule(fund_pack, duty, setup)
    mapping = setup&.document_mapping(duty.dig("trigger", "document"))
    return 0 if mapping.nil?

    docs = Document.where(entity_id: fund_pack.entity_id, owner_type: "Fund", owner_id: fund_pack.fund_id)
                   .where(created_at: (fund_pack.attached_on || Time.zone.today).beginning_of_day..)
    docs = if mapping["tag"].present?
             docs.where("documents.tag_list LIKE ?", "%#{Document.sanitize_sql_like(mapping['tag'])}%")
           else
             docs.where(name: mapping["name"])
           end
    insert(fund_pack, duty, docs.pluck(:id, :created_at), setup)
  end

  # From DocumentFactReader once notes exist: create the occurrence now and attach the notes
  def self.after_reading(reading)
    doc = reading.document
    return unless doc.owner_type == "Fund"

    setup = ComplianceEntitySetup.for(reading.entity)
    FundCompliancePack.active.where(fund_id: doc.owner_id).includes(:compliance_pack_version).find_each do |fp|
      Array(fp.compliance_pack_version&.duties).each do |duty|
        next unless duty.dig("trigger", "document") == reading.input_key

        schedule(fp, duty, setup)
      end
    end
  end

  def self.insert(fund_pack, duty, docs, setup)
    return 0 if docs.empty?

    notes = DocumentReading.where(document_id: docs.map(&:first), input_key: duty.dig("trigger", "document"), status: "read")
                           .where.not(notes: nil).order(:id).pluck(:document_id, :notes).to_h
    now = Time.current
    rows = docs.map do |id, created_at|
      { entity_id: fund_pack.entity_id, fund_compliance_pack_id: fund_pack.id, duty_key: duty["key"], period_key: "",
        subject_type: "Document", subject_id: id, due_on: created_at.to_date + duty.dig("due", "n").to_i.days,
        owner_id: setup&.owner_id, ai_notes: notes[id], created_at: now, updated_at: now }
    end
    before = ComplianceDuty.where(fund_compliance_pack_id: fund_pack.id).count
    # Duplicates skipped by idx_cduty_unique (no unique_by: — MySQL does not support it)
    ComplianceDuty.insert_all(rows)
    # Notes that arrived after the occurrence was created
    notes.each do |doc_id, text|
      ComplianceDuty.where(fund_compliance_pack_id: fund_pack.id, duty_key: duty["key"], subject_type: "Document", subject_id: doc_id, ai_notes: nil)
                    .update_all(ai_notes: text, updated_at: now)
    end
    ComplianceDuty.where(fund_compliance_pack_id: fund_pack.id).count - before
  end
end
