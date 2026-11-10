# frozen_string_literal: true

# The Security Events screen's filter, shared by the screen and the emailed download so both show exactly the same
# rows (OWASP review 2026-11 M11, design card ⑥).
#
#   from, to   — the period (dates); last 30 days by default, never longer than 13 months — the trail keeps no
#                more, so a longer period is shortened and the screen says so (E39)
#   q          — Ransack on SecurityEvent's allowlist: category, kind, outcome, door, ip_address. entity_id is not
#                on it, so a crafted q[entity_id_eq] is dropped and the policy scope stays the only tenant filter (X8)
#   account    — a name or an email. Matches the account by name / email; an email also matches failed attempts on
#                an address with no account, through its digest — the address itself is never stored (D10)
#
# It narrows a scope it is given (the policy scope); it never widens one.
class SecurityEventFilter
  DEFAULT_PERIOD = 30.days
  # The longest period: the trail keeps 13 months (SecurityEvent::RETENTION)
  MAX_PERIOD = SecurityEvent::RETENTION
  # Ransack conditions the form sends; anything else in q is ignored by Ransack (not ransackable)
  FORM_CONDITIONS = %w[category_eq kind_eq outcome_eq door_eq ip_address_eq].freeze
  # An account search names at most this many people (a name like "Shah" can match many)
  ACCOUNT_MATCH_LIMIT = 200

  attr_reader :from, :to, :account, :conditions

  # @param params [Hash, ActionController::Parameters] from, to, account, q
  def initialize(params)
    params = params.to_h.with_indifferent_access
    @to = parse_date(params[:to]) || Time.zone.today
    @from = parse_date(params[:from]) || (@to - DEFAULT_PERIOD)
    # E39 — never longer than the trail keeps
    @clamped = @from < (@to - MAX_PERIOD)
    @from = (@to - MAX_PERIOD) if @clamped
    @account = params[:account].to_s.strip.first(100).presence
    # Only the form's conditions, with blanks dropped (an "All" select sends "")
    @conditions = (params[:q] || {}).to_h.stringify_keys.slice(*FORM_CONDITIONS).compact_blank
    # A kind or group not in the catalogue (a hand-edited link) is dropped, not searched for
    @conditions.delete("kind_eq") unless SecurityEventCatalogue::KINDS.key?(@conditions["kind_eq"].to_s)
    @conditions.delete("category_eq") unless SecurityEventCatalogue::CATEGORIES.key?(@conditions["category_eq"].to_s)
  end

  # E39 — the period asked for was longer than 13 months and was shortened
  def clamped?
    @clamped
  end

  # The time range the period covers, whole days in the app's time zone
  def period
    from.beginning_of_day..to.end_of_day
  end

  # @param scope [ActiveRecord::Relation] the policy scope
  # @return [ActiveRecord::Relation]
  def apply(scope)
    # The period, then the form's allowlisted conditions
    scope = scope.for_period(period).ransack(conditions).result
    account ? scope.merge(account_condition(scope)) : scope
  end

  # The values to carry into the Download link and the pager, so they keep the same rows
  def to_params
    { from: from.iso8601, to: to.iso8601, account:, q: conditions.presence }.compact
  end

  # The same filter with the Event (kind) replaced — or removed when kind is nil; the Event links and the chip
  def with_kind(kind)
    conditions = self.conditions.except("kind_eq")
    conditions["kind_eq"] = kind if kind
    to_params.merge(q: conditions.presence).compact
  end

  # True when the person narrowed the list beyond the default period
  def narrowed?
    account.present? || conditions.present?
  end

  private

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Account: users whose name or email contains the text, plus (for an email) the digest of failed attempts on it
  def account_condition(_scope)
    user_ids = matching_users.limit(ACCOUNT_MATCH_LIMIT).pluck(:id)
    condition = SecurityEvent.where(user_id: user_ids)
    # D10 — an address with no account is found through its digest only
    condition = condition.or(SecurityEvent.where(identifier_digest: SecurityEventContext.identifier_digest(account))) if account.include?("@")
    condition
  end

  # "Priya Shah" → first and last name; one word → first name, last name or email contains it
  def matching_users
    first, rest = account.split(/\s+/, 2)
    like = ->(text) { "%#{ActiveRecord::Base.sanitize_sql_like(text)}%" }
    if rest
      User.where("first_name LIKE ? AND last_name LIKE ?", like.call(first), like.call(rest))
    else
      User.where("first_name LIKE :term OR last_name LIKE :term OR email LIKE :term", term: like.call(first))
    end
  end
end
