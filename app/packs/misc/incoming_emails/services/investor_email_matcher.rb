class InvestorEmailMatcher
  include Pundit::Authorization

  GENERIC_DOMAINS = %w[gmail.com yahoo.com outlook.com hotmail.com icloud.com aol.com me.com msn.com rediffmail.com].freeze

  def initialize(from_email:, user:, to_emails: [], cc_emails: [])
    @from_email = from_email.downcase
    @to_emails = Array(to_emails).map(&:downcase).uniq.compact_blank
    @cc_emails = Array(cc_emails).map(&:downcase).uniq.compact_blank
    @user = user
  end

  def match
    # 1. First try matching by InvestorAccess email
    all_emails = ([@from_email] + @cc_emails).uniq.compact_blank
    matches = investor_access_scope.approved.where(email: all_emails).includes(:investor)

    # 2. If no match, try matching the from_email domain with the investor's primary_email domain
    if matches.none?
      from_domain = @from_email.split("@").last
      matches = investor_scope.where("primary_email LIKE ?", "%@#{from_domain}") unless generic_domain?(from_domain)
    end

    # 3. If still no match, try matching cc emails domain
    if matches.none?
      cc_domains = @cc_emails.map { |email| email.split("@").last }.uniq
      cc_domains -= GENERIC_DOMAINS
      if cc_domains.any?
        domain_queries = cc_domains.map { |domain| "primary_email LIKE '%@#{domain}'" }.join(" OR ")
        matches = investor_scope.where(domain_queries)
      end
    end

    if matches.one?
      # If matches are from InvestorAccess, we need to return the investor
      result = matches.first
      investor = result.is_a?(Investor) ? result : result.investor
      { match_type: "single", investors: [investor] }
    elsif matches.many?
      # Group by investor to avoid duplicate investors if multiple emails match same investor
      investors = matches.map { |m| m.is_a?(Investor) ? m : m.investor }.uniq
      if investors.one?
        { match_type: "single", investors: [investors.first] }
      else
        { match_type: "multiple", investors: investors }
      end
    else
      { match_type: "none", investors: [] }
    end
  end

  private

  def generic_domain?(domain)
    GENERIC_DOMAINS.include?(domain)
  end

  def investor_scope
    Pundit.policy_scope!(@user, Investor)
  end

  def investor_access_scope
    Pundit.policy_scope!(@user, InvestorAccess)
  end
end
