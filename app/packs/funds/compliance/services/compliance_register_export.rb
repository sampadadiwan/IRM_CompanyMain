# ⑨ Excel export of a period: results at period end, register items opened or open in the period
# (with approvals, labelled "Self-approved — single approver" where so — E110) and duties.
# Rows are limited to funds the user can see (E47). States its data basis (H58).
class ComplianceRegisterExport
  BASIS = "Computed on data as entered at run time".freeze

  def self.call(user:, from:, to:, fund_ids: [])
    new(user, from, to, fund_ids).call
  end

  def initialize(user, from, to, fund_ids)
    @user = user
    @from = from
    @to = to
    visible = ComplianceAccess.fund_ids(user)
    @fund_ids = fund_ids.any? ? visible & fund_ids : visible
  end

  def call
    pkg = Axlsx::Package.new
    fund_packs = FundCompliancePack.where(entity_id: @user.entity_id, fund_id: @fund_ids).includes(:fund, :compliance_pack)
    results_sheet(pkg, fund_packs)
    register_sheet(pkg, fund_packs)
    duties_sheet(pkg, fund_packs)
    pkg.to_stream.read
  end

  def rows_for_test
    fund_packs = FundCompliancePack.where(entity_id: @user.entity_id, fund_id: @fund_ids)
    { results: results(fund_packs).map { |r| [r.fund_compliance_pack.fund.name, r.check_key, r.outcome] },
      items: items(fund_packs).map { |i| [i.fund.name, i.check_key, approval_label(i)] }, basis: BASIS }
  end

  private

  def results(fund_packs)
    ids = ComplianceResult.joins(:compliance_run).where(fund_compliance_pack_id: fund_packs.map(&:id))
                          .where(compliance_runs: { run_date: ..@to }).group(:fund_compliance_pack_id, :check_key).maximum(:id).values
    ComplianceResult.where(id: ids).includes(:compliance_run, fund_compliance_pack: %i[fund compliance_pack]).order(:id)
  end

  def items(fund_packs)
    ComplianceRegisterItem.where(fund_compliance_pack_id: fund_packs.map(&:id))
                          .where("opened_on <= ? AND (closed_on IS NULL OR closed_on >= ?)", @to, @from).includes(:fund).order(:opened_on)
  end

  def results_sheet(pkg, fund_packs)
    pkg.workbook.add_worksheet(name: "Results") do |s|
      s.add_row [BASIS]
      s.add_row ["Period", "#{I18n.l(@from)} – #{I18n.l(@to)}"]
      s.add_row ['Fund', 'Pack', 'Version', 'Check', 'Run date', 'Outcome', 'Figure', 'Limit', 'Working']
      results(fund_packs).each do |r|
        w = r.working_hash
        s.add_row [r.fund_compliance_pack.fund.name, r.fund_compliance_pack.pack_name, w["version"], w["check_name"] || r.check_key,
                   I18n.l(r.compliance_run.run_date), r.outcome, r.figure&.to_s, r.limit_value&.to_s, Array(w["lines"]).join(" | ")]
      end
    end
  end

  def register_sheet(pkg, fund_packs)
    pkg.workbook.add_worksheet(name: "Register") do |s|
      s.add_row ['Fund', 'Check', 'Opened', 'Status', 'Closed reason', 'Fix by', 'Approval']
      items(fund_packs).each do |i|
        s.add_row [i.fund.name, i.check_name, I18n.l(i.opened_on), i.status, i.closed_label, i.fix_by && I18n.l(i.fix_by), approval_label(i)]
      end
    end
  end

  def duties_sheet(pkg, fund_packs)
    pkg.workbook.add_worksheet(name: "Duties") do |s|
      s.add_row %w[Fund Duty Period Due Done Note]
      ComplianceDuty.where(fund_compliance_pack_id: fund_packs.map(&:id), due_on: @from..@to).includes(fund_compliance_pack: :fund).find_each do |d|
        s.add_row [d.fund_compliance_pack.fund.name, d.name, d.period_key, d.due_on && I18n.l(d.due_on), d.done_on && I18n.l(d.done_on), d.note]
      end
    end
  end

  def approval_label(item)
    ComplianceRequest.where(target_type: "ComplianceRegisterItem", target_id: item.id, status: "approved").order(:id).last&.approval_label ||
      ComplianceRequest.where(target_type: "FundCompliancePack", target_id: item.fund_compliance_pack_id, status: "approved").order(:id).last&.approval_label
  end
end
