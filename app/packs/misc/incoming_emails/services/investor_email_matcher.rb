# Resolves the investor an email belongs to, for the Outlook and Gmail add-ins.
#
# Matching runs in tiers, most specific first, and stops at the first tier that
# produces candidates:
#
#   1. Contact  — a participant address is a known, approved InvestorAccess email.
#   2. Primary  — a participant address is an Investor's primary_email exactly.
#   3. Domain   — a participant address shares a domain with an Investor's
#                 primary_email. Generic mail hosts (gmail.com etc.) are excluded,
#                 since sharing them implies nothing.
#
# Matching considers the **sender only**. To and CC are deliberately ignored.
#
# A recipient address is weak evidence of who an email is about: everybody on a thread is
# a recipient, distribution lists and CCs drag in unrelated records, and the mailbox owner
# is a recipient of every message they receive. The one thing recipients would buy is
# auto-matching mail the fund *sent* to an investor, where the investor appears only in To.
# That case is handled by picking the record by hand instead — a deliberate product
# decision, on the grounds that a wrong suggestion costs more than an absent one.
#
# Addresses identifying the filer — their CapHive login and the mailbox they are reading —
# are excluded, so opening your own sent mail matches nothing rather than matching an
# investor record that happens to be registered against your own address.
#
# @see docs/modules/mail_addins/mail_addin_review.md
class InvestorEmailMatcher
  # Domains where a shared suffix carries no signal about who the counterparty is.
  GENERIC_DOMAINS = %w[
    gmail.com googlemail.com yahoo.com yahoo.co.in ymail.com outlook.com hotmail.com
    live.com msn.com icloud.com me.com mac.com aol.com protonmail.com proton.me
    zoho.com gmx.com mail.com yandex.com rediffmail.com
  ].freeze

  # @return [Hash] :match_type is "single" | "multiple" | "none"; :investors is ordered
  #   best-first; :matches pairs each investor with the tier that found it.
  Result = Struct.new(:match_type, :investors, :matches, keyword_init: true) do
    def to_h
      { match_type: match_type, investors: investors, matches: matches }
    end
  end

  # @param from_email [String] sender address — the only address matching considers
  # @param user [User] whose Pundit scope bounds every lookup
  # @param mailbox_email [String, nil] address of the mailbox the message was read from,
  #   as reported by the add-in host. Usually differs from user.email: the CapHive login
  #   and the mail account are separate identities.
  def initialize(from_email:, user:, mailbox_email: nil)
    @from_email = normalize_one(from_email)
    @mailbox_email = normalize_one(mailbox_email)
    @user = user
  end

  def match
    investors = match_by_contact
    reason = :contact

    if investors.empty?
      investors = match_by_primary_email
      reason = :primary_email
    end

    if investors.empty?
      investors = match_by_domain
      reason = :domain
    end

    build_result(investors, reason)
  end

  private

  # The sender, unless the sender is the person doing the filing.
  #
  # Their own addresses carry no signal about who the mail is about, and both have to go
  # because they are usually different strings: user.email is the CapHive login, while the
  # mailbox address is the mail account. Without the second, an investor record registered
  # against the user's own address (a personal Gmail on a test fund, a GP who is also an
  # LP) matches their own sent mail.
  #
  # nil when there is nothing to match on, which short-circuits every tier.
  def sender_email
    return @sender_email if defined?(@sender_email)

    @sender_email = own_emails.include?(@from_email) ? nil : @from_email.presence
  end

  # The filer's own addresses. Blank entries are stripped so a host that cannot report the
  # mailbox address does not accidentally exclude a blank sender.
  def own_emails
    @own_emails ||= [normalize_one(@user.email), @mailbox_email].compact_blank.uniq
  end

  # Tier 1 — an approved investor contact. includes(:investor) because the investors are
  # read straight back out of the result.
  def match_by_contact
    return [] if sender_email.nil?

    investor_access_scope
      .approved
      .where(email: sender_email)
      .includes(:investor)
      .filter_map(&:investor)
      .uniq
  end

  # Tier 2 — exact hit on the investor record's own address.
  def match_by_primary_email
    return [] if sender_email.nil?

    investor_scope.where(primary_email: sender_email).to_a
  end

  # Tier 3 — shared domain. Equality against the indexed primary_email_domain column
  # rather than `primary_email LIKE '%@domain'`, which could not use an index and scanned
  # the whole investors table on every request. Equality also removes the LIKE-escaping
  # problem, where an attacker-supplied From header of `a_b.com` matched `axb.com`.
  def match_by_domain
    domain = sender_email && domain_of(sender_email)
    return [] if domain.nil?

    investor_scope.where(primary_email_domain: domain).to_a
  end

  # Nil for generic mail hosts, so they never form a match on their own.
  def domain_of(email)
    domain = email.to_s.split("@").last.presence
    return nil if domain.nil? || GENERIC_DOMAINS.include?(domain)

    domain
  end

  def build_result(investors, reason)
    investors = investors.compact.uniq

    match_type = case investors.size
                 when 0 then "none"
                 when 1 then "single"
                 else "multiple"
                 end

    matches = investors.map { |investor| { investor: investor, reason: reason } }
    Result.new(match_type: match_type, investors: investors, matches: investors.empty? ? [] : matches)
  end

  def normalize_one(email)
    email.to_s.strip.downcase.presence
  end

  def normalize_many(emails)
    Array(emails).map { |email| normalize_one(email) }.compact_blank.uniq
  end

  def investor_scope
    Pundit.policy_scope!(@user, Investor)
  end

  def investor_access_scope
    Pundit.policy_scope!(@user, InvestorAccess)
  end
end
