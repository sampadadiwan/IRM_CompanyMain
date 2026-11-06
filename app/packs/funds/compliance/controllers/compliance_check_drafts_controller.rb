# ⑧ "Describe in words": draft a check from a sentence (AI in a job), review it in plain words, edit it
# field by field, test-run it on a fund and save it into the pack version's draft with its provenance.
# Every record is loaded through policy_scope and then authorized (design › Security item 1).
# Worked examples H37, H38, H39, E57–E62, X39–X43 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceCheckDraftsController < ApplicationController
  include ComplianceCrumbs

  UNAVAILABLE = "Describe in words is unavailable — use the form".freeze

  before_action :set_draft, except: :create

  # Draft from a sentence: the draft row is written first ("drafting"), the AI runs in a job
  def create
    version = CompliancePackVersion.where(compliance_pack_id: policy_scope(CompliancePack).select(:id))
                                   .find_by(id: params[:compliance_pack_version_id]) || raise(Pundit::NotAuthorizedError)
    @draft = ComplianceCheckDraft.new(compliance_pack_version: version, user: current_user,
                                      entity_id: version.compliance_pack.entity_id, sentence: params.dig(:compliance_check_draft, :sentence).to_s)
    authorize @draft
    # X41: the entity's drafting switch is off — the form still works
    return redirect_to(compliance_pack_version_path(version), alert: UNAVAILABLE) unless ComplianceCheckDrafter.available?(version, current_user)

    if @draft.save
      ComplianceCheckDraftJob.perform_later(@draft.id)
      redirect_to compliance_check_draft_path(@draft)
    else
      # X39: "Keep the rule under 1,000 characters"
      redirect_to compliance_pack_version_path(version), alert: @draft.errors.messages.values.flatten.to_sentence
    end
  end

  def show
    authorize @draft
    @funds = test_funds
    version = @draft.compliance_pack_version
    compliance_crumbs(["Rule library", compliance_packs_path], [version.compliance_pack.name, compliance_pack_path(version.compliance_pack)],
                      [version.label, compliance_pack_version_path(version)], ["Describe in words", nil])
  end

  # Field-by-field edits; any edit clears the test run (E60) and settles that part's assumption (E58)
  def update
    authorize @draft
    draft = @draft.draft_hash
    edits = draft_params
    %w[name citation compare limit_unit duty_trigger reason].each { |k| draft[k] = edits[k].to_s.strip.first(200) if edits.key?(k) }
    draft["limit_value"] = edits[:limit_value].presence && edits[:limit_value].to_d.to_f if edits.key?(:limit_value)
    draft["duty_due_days"] = edits[:duty_due_days].to_i.clamp(0, 365) if edits.key?(:duty_due_days)
    draft["evidence"] = edits[:evidence] == "1" if edits.key?(:evidence)
    ComplianceCheckDraft::PARTS.each do |role|
      next unless edits[role]

      changed = apply_part(draft, role, edits[role].to_h)
      draft["assumptions"] = Array(draft["assumptions"]).reject { |a| a["part"] == role } if changed
    end
    @draft.update!(draft:, test_result: nil, test_fund_id: nil)
    redirect_to compliance_check_draft_path(@draft), notice: "Draft updated — run the test again"
  end

  # Test run on a fund the user picks — inside CapHive, nothing stored but the result on the draft (H38)
  def test_run
    authorize @draft
    errors = @draft.validation_errors
    return redirect_to(compliance_check_draft_path(@draft), alert: errors.to_sentence) if errors.any?

    fund = policy_scope(Fund).find_by(id: params[:fund_id])
    raise Pundit::NotAuthorizedError if fund.nil? || !CompliancePreview.allowed_fund?(current_user, @draft.compliance_pack_version, fund)

    @draft.update!(test_result: ComplianceCheckDraftTest.call(draft: @draft, fund:), test_fund_id: fund.id)
    redirect_to compliance_check_draft_path(@draft)
  end

  # Save appends the check (or duty) to the version's draft with provenance (H38); refused until tested (E59)
  def save_check
    authorize @draft
    errors = @draft.save_into_version!(current_user)
    return redirect_to(compliance_check_draft_path(@draft), alert: errors.to_sentence) if errors.any?

    version = @draft.compliance_pack_version
    redirect_to compliance_pack_version_path(version), notice: "#{@draft.draft_hash['name']} added to #{version.label}"
  end

  private

  def set_draft
    @draft = policy_scope(ComplianceCheckDraft).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
  end

  # Funds offered for a test run: the user's own visible funds; super admins the CapHive demo entity's (E7)
  def test_funds
    scope = policy_scope(Fund)
    scope = if current_user.has_cached_role?(:super)
              scope.where(entity_id: Entity.where(name: CompliancePreview::DEMO_ENTITY_NAME).select(:id))
            else
              scope.where(entity_id: current_user.entity_id)
            end
    scope.order(:name).limit(200)
  end

  def draft_params
    params.expect(compliance_check_draft: [:name, :citation, :compare, :limit_value, :limit_unit, :duty_trigger, :duty_due_days,
                                           :evidence, :reason, { figure: %i[measure op source field group_by],
                                                                 divided_by: %i[measure op source field group_by] }])
  end

  # A part is either an existing measure or op/source/field/group_by (filters kept as drafted)
  def apply_part(draft, role, edit)
    before = draft[role]
    if edit["measure"] == "none"
      draft[role] = nil
    elsif edit["measure"].present?
      draft[role] = { "measure" => edit["measure"].to_s }
    else
      kept = before.is_a?(Hash) && before["measure"].blank? ? before.slice("filters") : {}
      draft[role] = kept.merge(edit.slice("op", "source", "field", "group_by").transform_values { |v| v.to_s.strip }.compact_blank)
    end
    draft[role] != before
  end
end
