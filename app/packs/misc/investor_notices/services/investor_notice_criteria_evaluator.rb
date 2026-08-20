# Safely evaluates InvestorNotice#criteria — a boolean expression written by a
# GP admin (e.g. `[investor.category] == "Lead Investor"`), used to further
# narrow which investors already in a notice's audience (InvestorNoticeEntry)
# actually see it, at render time, per viewer.
#
# Never uses Ruby eval/instance_eval on the stored string — that would let
# anyone who can edit a notice execute arbitrary code on the server. Instead
# this follows the same pattern already used for report-builder formulas
# (ReportBuilderFormulaService): Dentaku's safe expression parser, with
# `[bracket.path]` variables remapped to Dentaku-safe identifiers.
#
# The set of variables available to an expression is a deliberate allow-list
# (#build_context below) — Dentaku only ever sees a plain Hash of values we
# chose to expose, never a live model object or #send/#public_send. Extend
# that method (not the expression syntax) to add new variables.
class InvestorNoticeCriteriaEvaluator
  # Blank criteria always matches — preserves the pre-criteria behavior for
  # every existing notice, which has no `criteria` value.
  def self.matches?(investor_notice, user)
    expression = investor_notice.criteria.to_s.strip
    return true if expression.blank?

    context = build_context(investor_notice, user)
    # Coerce to a real boolean — a well-formed expression should be a
    # comparison/logical expression already, but this guards against a
    # bare truthy value (e.g. a string) being written by mistake.
    !!Dentaku::Calculator.new.evaluate!(to_safe_expression(expression), context)
  rescue StandardError => e
    # Fail closed: an unresolvable variable or a typo hides the notice for
    # this viewer rather than crashing their dashboard or leaking the notice
    # to everyone. criteria_expression_is_valid (on the model) is what
    # surfaces broken expressions to the GP admin at save time instead.
    Rails.logger.warn("[InvestorNoticeCriteriaEvaluator] notice=#{investor_notice.id} error=#{e.message}")
    false
  end

  # Dry-run validation against a representative investor of the notice's GP —
  # used by InvestorNotice's model validation so a broken expression is
  # rejected at save time instead of silently hiding the notice from everyone
  # later. Mirrors ReportBuilderFormulaService.validate.
  # @return [true, String] true if it evaluates cleanly, else the error message
  def self.validate(expression, investor_notice)
    return true if expression.blank?
    return true if investor_notice.entity.nil?

    sample_investor = investor_notice.entity.investors.first
    return true if sample_investor.nil? # nothing to validate against yet

    context = build_context(investor_notice, sample_investor.users.first, investor: sample_investor)
    Dentaku::Calculator.new.evaluate!(to_safe_expression(expression), context)
    true
  rescue StandardError => e
    e.message
  end

  # [investor.category] -> investor__category (Dentaku identifiers can't contain dots)
  def self.to_safe_expression(expression)
    expression.gsub(/\[([^\]]+)\]/) { Regexp.last_match(1).strip.gsub(".", "__") }
  end
  private_class_method :to_safe_expression

  def self.build_context(investor_notice, user, investor: nil)
    investor ||= Investor.find_by(entity_id: investor_notice.entity_id, investor_entity_id: user&.entity_id)

    context = {}
    if investor
      context["investor__category"] = investor.category
      context["investor__investor_name"] = investor.investor_name
      context["investor__city"] = investor.city
    end

    # The logged-in LP user themselves (not the Investor/firm row) — phone is
    # the login user's own attribute, e.g. `[user.phone] == ""` for "this
    # person hasn't added a phone number yet".
    context["user__phone"] = user.phone if user

    owner = investor_notice.owner
    if owner.is_a?(Fund)
      context["fund__name"] = owner.name
      context["fund__currency"] = owner.currency
    end

    # Dentaku's == doesn't treat nil and "" as equal (nil == "" is false, not
    # true), so an author writing `[x] == ""` to mean "blank" would silently
    # get the wrong answer for a genuinely-nil column. Normalize every
    # exposed string to "" so blank checks work regardless of whether the
    # underlying column is nil or empty.
    context.transform_values! { |v| v.is_a?(String) || v.nil? ? v.to_s : v }

    context
  end
  private_class_method :build_context
end
