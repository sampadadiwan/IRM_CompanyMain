# Proposes payout custom fields for the bank change controls (OWASP review 2026-11 M14,
# openspec/changes/bank-detail-change-controls, design D20; LLD "Method Contracts › Rake").
#
# Firms that keep SWIFT / IBAN in KYC custom fields are covered only once those fields are marked as payout fields.
# This lists, per firm › KYC form type › field, every unmarked TEXT field whose name or label is a SWIFT, BIC, IBAN,
# routing, sort code or ABA field, the kind it would get (IBAN → account identifier, the rest → bank code) and how
# many KYCs hold a value — a count, never the values. Check boxes and other types are never proposed.
#
# Dry run by default (prints, saves nothing):
#   bin/rails bank_detail_changes:propose_payout_fields
#   bin/rails bank_detail_changes:propose_payout_fields FIRM_ID=3103
# Mark (only after the firm's company admin agreed in the support ticket; one firm at a time):
#   EXECUTE=1 FIRM_ID=3103 bin/rails bank_detail_changes:propose_payout_fields
#
# Marking changes no KYC and sends no email (E65, E79): the rules apply to saves made after it.
# production.in and production.us are independent: run it on each, separately.
# Worked examples E78, E79 — openspec/changes/bank-detail-change-controls/business-rules.md#8
namespace :bank_detail_changes do
  desc "Propose (or with EXECUTE=1 FIRM_ID=<id>, mark) KYC SWIFT/IBAN text fields as payout fields"
  task propose_payout_fields: :environment do
    execute = ENV["EXECUTE"] == "1"
    firm_id = ENV.fetch("FIRM_ID", nil).presence
    # E79 — marking is per firm, after its admin agreed: never across every firm at once
    abort "EXECUTE=1 needs FIRM_ID=<entity id> (mark one firm at a time, after its admin agreed)" if execute && firm_id.nil?

    # Whole words of the name (underscores read as spaces) or the label
    pattern = /\b(swift|bic|iban|routing|sort code|aba)\b/i
    fields = FormCustomField.joins(:form_type)
                            .where(form_types: { name: FormCustomField::PAYOUT_FORM_TYPES }, field_type: "TextField")
    fields = fields.where(form_types: { entity_id: firm_id }) if firm_id
    candidates = fields.includes(form_type: :entity).order("form_types.entity_id", "form_types.name", :position).select do |field|
      # Already marked: nothing to propose
      field.payout_field.blank? && [field.name.to_s.tr("_", " "), field.label.to_s].any? { |text| text.match?(pattern) }
    end

    puts(execute ? "Marking payout fields for firm #{firm_id}" : "Payout field proposal (dry run)")
    if candidates.empty?
      puts "No unmarked SWIFT / BIC / IBAN / routing / sort code / ABA text fields found."
      next
    end

    candidates.group_by { |field| field.form_type.entity }.each do |firm, firm_fields|
      puts "#{firm.name} (#{firm.id})"
      firm_fields.each do |field|
        kind = field.name.to_s.match?(/iban/i) || field.label.to_s.match?(/iban/i) ? "account" : "code"
        # A count only, never the values (portable JSON path test: IS NOT NULL behaves the same on MySQL and SQLite)
        filled = InvestorKyc.where(form_type_id: field.form_type_id)
                            .where("json_extract(json_fields, ?) IS NOT NULL", "$.#{field.name}").count
        line = "  #{field.form_type.name} › #{field.label.presence || field.name} (#{field.name}) → #{kind} · #{filled} filled"
        if execute
          # Through the model, so its validations (KYC text fields only) run
          field.payout_field = kind
          field.save!
          line += " · marked"
        end
        puts line
      end
    end
    puts "Dry run: nothing was saved. After the firm's admin agrees, re-run with EXECUTE=1 FIRM_ID=<id>." unless execute
  end
end
