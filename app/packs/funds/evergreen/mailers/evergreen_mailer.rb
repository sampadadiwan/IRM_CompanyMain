# Renders the evergreen investor emails. Dates use l(date), which EmailDateLocalization turns into
# "Mon dd, yyyy" in English for every email (CLAUDE.md).
# Worked examples H7, H21, H25, E32 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper
  helper EvergreenNavHelper
  helper EvergreenWordingHelper

  # %<fund>s is the fund name; %<contract_note>s, %<redemption_advice>s and %<Units>s are the fund's evergreen
  # labels (EvergreenLabels) and %<order_date>s the order's "subscription date" / "redemption date" — see .subject_for
  SUBJECTS = {
    "subscription_acknowledgement" => "%<fund>s: Subscription received",
    "redemption_acknowledgement" => "%<fund>s: Redemption request received",
    "request_cancelled" => "%<fund>s: Request cancelled",
    "request_rolled" => "%<fund>s: Request moved to the next %<order_date>s",
    "gate_notice" => "%<fund>s: Redemption partly filled",
    "payment_instructions" => "%<fund>s: Payment instructions",
    "contract_note" => "%<fund>s: %<contract_note>s",
    "redemption_advice" => "%<fund>s: %<redemption_advice>s",
    "payment_reminder" => "%<fund>s: Payment due before the cut-off",
    "action_needed" => "%<fund>s: Action needed on your request",
    "payment_received" => "%<fund>s: Payment received",
    "units_unlocked" => "%<fund>s: %<Units>s now free to redeem",
    "nav_update" => "%<fund>s: NAV update"
  }.freeze

  # The subject for an email method in the fund's wording ("Contract note" / "Trade confirmation").
  # order: the order the email is about, so a rolled request names its own kind of date.
  def self.subject_for(email_method, fund, order: nil, fallback: "Evergreen fund update")
    template = SUBJECTS[email_method.to_s]
    # Unknown methods keep the plain fallback text (no fund name), as before
    return fallback unless template

    # Every label a template may name; format ignores the ones it does not use
    labels = %i[contract_note redemption_advice Units].index_with { |key| EvergreenLabels.t(key, fund:) }
    date_key = order&.redemption? ? :redemption_date : :subscription_date
    format(template, fund: fund.name, order_date: EvergreenLabels.lower(EvergreenLabels.t(date_key, fund:)), **labels)
  end

  # {{placeholders}} for fund-level "Evergreen" custom notifications (CustomNotification for_type "Evergreen")
  money = ->(m, cents) { cents && m.view_context.evergreen_money(cents, m.instance_variable_get(:@fund)) }
  email_date = ->(d) { d && I18n.l(d, format: :email, locale: :en) }
  PLACEHOLDERS = ApplicationMailer::PLACEHOLDERS.merge(
    "investor_name" => ->(m) { m.instance_variable_get(:@order)&.investor&.investor_name },
    "fund_name" => ->(m) { m.instance_variable_get(:@fund)&.name },
    "folio_id" => ->(m) { m.instance_variable_get(:@order)&.capital_commitment&.folio_id },
    "unit_class" => ->(m) { m.instance_variable_get(:@order)&.unit_type },
    "request_type" => ->(m) { (o = m.instance_variable_get(:@order)) && EvergreenLabels.t(o.kind, fund: o.fund) },
    "requested_amount" => ->(m) { money.call(m, m.instance_variable_get(:@order)&.amount_cents) },
    "requested_units" => ->(m) { (u = m.instance_variable_get(:@order)&.units) && m.view_context.number_with_precision(u, precision: 4, delimiter: ",") },
    "dealing_date" => ->(m) { email_date.call(m.instance_variable_get(:@order)&.dealing_date&.date) },
    "cutoff_date" => ->(m) { email_date.call(m.instance_variable_get(:@order)&.dealing_date&.cutoff_at&.to_date) },
    "nav_per_unit" => ->(m) { (f = m.instance_variable_get(:@fill)) && m.view_context.evergreen_nav_per_unit(f.nav_per_unit_cents) },
    "units_dealt" => ->(m) { (f = m.instance_variable_get(:@fill)) && m.view_context.number_with_precision(f.units, precision: 4, delimiter: ",") },
    "amount_dealt" => ->(m) { money.call(m, m.instance_variable_get(:@fill)&.amount_cents) },
    "units_carried" => ->(m) { (f = m.instance_variable_get(:@fill)) && m.view_context.number_with_precision(f.carried_units, precision: 4, delimiter: ",") },
    "early_redemption_fee" => ->(m) { money.call(m, m.instance_variable_get(:@fill)&.early_fee_cents) },
    "net_paid" => ->(m) { money.call(m, m.instance_variable_get(:@fill)&.net_payment_cents) },
    "payment_instructions" => ->(m) { m.instance_variable_get(:@setting)&.payment_instructions },
    "pending_step" => ->(m) { (o = m.instance_variable_get(:@order)) && OrderJourneyStatus.waiting_on(o) },
    "nav_date" => ->(m) { email_date.call(m.instance_variable_get(:@fund_nav)&.nav_date) },
    "holding_units" => ->(m) { (u = m.instance_variable_get(:@holding_units)) && m.view_context.number_with_precision(u, precision: 4, delimiter: ",") },
    "holding_value" => ->(m) { money.call(m, m.instance_variable_get(:@holding_value_cents)) },
    "unlocked_units" => ->(m) { (u = m.instance_variable_get(:@unlocked_units)) && m.view_context.number_with_precision(u, precision: 4, delimiter: ",") }
  ).freeze

  before_action :set_order

  # Order-level emails carry dealing_order_id; folio-level ones (units_unlocked, nav_update) carry
  # capital_commitment_id (+ fund_nav_id / unlocked_units)
  def set_order
    # Read fresh per email, so views see the order as it is now (gate_notice compares its dealing
    # date with the fill's to tell carried from not carried — no reload needed in the view)
    @order = DealingOrder.find(params[:dealing_order_id]) if params[:dealing_order_id]
    @folio = @order&.capital_commitment || (CapitalCommitment.find(params[:capital_commitment_id]) if params[:capital_commitment_id])
    @fund = @order&.fund || @folio.fund
    @fund_nav = FundNav.find_by(id: params[:fund_nav_id]) if params[:fund_nav_id]
    @unlocked_units = params[:unlocked_units]&.to_d
    if @fund_nav && @folio
      @holding_units = FundUnit.where(capital_commitment_id: @folio.id, unit_type: @fund_nav.unit_type, issue_date: ..@fund_nav.nav_date).sum(:quantity).to_d
      @holding_value_cents = (@holding_units * @fund_nav.nav_per_unit_cents.to_d).round(0) # to the paisa
    end
    @setting = @fund.evergreen_fund_setting
    @fill = DealingFill.find_by(id: params[:dealing_fill_id]) if params[:dealing_fill_id]
    # A fund-level "Evergreen" custom notification replaces this email's subject and body when present
    @custom_notification = @fund.custom_notification(action_name, for_type: "Evergreen")
  end

  SUBJECTS.each_key do |email_method|
    define_method(email_method) do
      # The approved document generated from the fund's template, if any (no template → email only)
      attach_document if %w[contract_note redemption_advice].include?(email_method) && @fill&.document&.approved
      send_mail(subject: self.class.subject_for(email_method, @fund, order: @order))
    end
  end

  # A custom notification's subject may use {{placeholders}} like its body: fill them before sending
  def send_mail(**)
    if @custom_notification&.subject.to_s.include?("{{")
      @custom_notification.subject = @custom_notification.subject.gsub(CustomNotification::PLACEHOLDER_REGEXP) do
        PLACEHOLDERS[Regexp.last_match(1)]&.call(self).to_s
      end
    end
    super
  end

  private

  def attach_document
    attach_doc(@fill.document)
  end
end
