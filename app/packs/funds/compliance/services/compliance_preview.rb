# ① ⑤ Evaluates a version on a fund WITHOUT storing anything — the draft test run (R37, H4, E7) and the
# "coming into effect" preview (H48, E88, E89). Never writes results, items or digest lines.
class CompliancePreview
  Row = Struct.new(:check_key, :name, :outcome, :figure, :limit, :message, :working, keyword_init: true)
  Preview = Struct.new(:version, :rows, :not_applicable, keyword_init: true)

  DEMO_ENTITY_NAME = ENV.fetch("COMPLIANCE_DEMO_ENTITY", "CapHive Demo")

  # Super admins: the CapHive demo entity, or a customer that granted support access (E7, X11).
  # Customers: a fund of their own firm they can see, for their own entity packs or attached packs.
  def self.allowed_fund?(user, version, fund)
    if user.has_cached_role?(:super)
      return true if fund.entity&.name == DEMO_ENTITY_NAME

      return SupportClientMapping.where(entity_id: fund.entity_id, user_id: user.id, enabled: true)
                                 .exists?(["end_date IS NULL OR end_date >= ?", Time.zone.today])
    end
    ComplianceAccess.editor?(user) && ComplianceAccess.fund_visible?(user, fund) &&
      (version.compliance_pack.entity_id == user.entity_id || version.compliance_pack.caphive?)
  end

  def self.call(version:, fund:, classification: nil)
    new(version, fund, classification).call
  end

  def initialize(version, fund, classification)
    @version = version
    @fund = fund
    @classification = classification.presence || version.classifications.first
  end

  def call
    # E88: a "new funds only" version that will not apply to this fund says so
    return Preview.new(version: @version, rows: [], not_applicable: true) if @version.applies_to?(@fund) == false

    setup = ComplianceEntitySetup.find_by(entity_id: @fund.entity_id) || ComplianceEntitySetup.new(entity_id: @fund.entity_id)
    context = ComplianceMeasureQuery.context(fund: @fund, as_of: Time.zone.today, setup:, version: @version)
    rows = @version.checks.filter_map do |check|
      next if check["kind"] == "manual" || !applies?(check)

      out = ComplianceCheckEvaluator.call(check, context:)
      Row.new(check_key: check["key"], name: check["name"], outcome: out.outcome, figure: out.figure,
              limit: out.limit_value, message: out.working["message"] || out.working["lines"]&.last, working: out.working)
    end
    Preview.new(version: @version, rows:, not_applicable: false)
  end

  private

  def applies?(check)
    applies = check["applies_to"]
    applies.nil? || applies == "all" || Array(applies).include?(@classification)
  end
end
