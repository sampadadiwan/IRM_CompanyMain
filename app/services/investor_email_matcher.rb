class InvestorEmailMatcher
  def initialize(from_email:, policy_scope:, to_emails: [], cc_emails: [])
    @emails = ([from_email] + Array(to_emails) + Array(cc_emails)).map(&:downcase).uniq.compact_blank
    @policy_scope = policy_scope
  end

  def match
    matches = @policy_scope.approved.where(email: @emails).includes(:investor)

    if matches.one?
      { match_type: "single", investors: [matches.first.investor] }
    elsif matches.many?
      # Group by investor to avoid duplicate investors if multiple emails match same investor
      investors = matches.filter_map(&:investor).uniq
      if investors.one?
        { match_type: "single", investors: [investors.first] }
      else
        { match_type: "multiple", investors: investors }
      end
    else
      { match_type: "none", investors: [] }
    end
  end
end
