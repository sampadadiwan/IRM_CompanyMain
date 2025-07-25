module FundsHelper
  def fund_bread_crumbs(current = nil)
    @bread_crumbs = { Funds: funds_path }
    @bread_crumbs[Fund.find(params[:fund_id]).name] = fund_path(params[:fund_id]) if params[:fund_id].present?
    @bread_crumbs[current] = nil if current
  end

  def investor_commitments_chart(capital_commitments)
    commitments = capital_commitments.joins(:fund, :investor)
                                     .order(commitment_date: :asc)
                                     .group_by { |v| v.fund.name }
                                     .map do |fname, vals|
      [fname,
       vals.inject(0) { |sum, com| sum + com.committed_amount.to_f },
       vals.inject(0) { |sum, com| sum + com.call_amount.to_f },
       vals.inject(0) { |sum, com| sum + com.collected_amount.to_f },
       vals.inject(0) { |sum, com| sum + com.distribution_amount.to_f }]
    end

    # column_chart cumulative(commitments), library: {
    #   plotOptions: { column: {
    #     dataLabels: {
    #       enabled: true,
    #       format: "{point.y:,.2f}"
    #     }
    #   } }
    # }

    column_chart [
      { name: "Committed", data: commitments.map { |k| [k[0], k[1]] } },
      { name: "Called", data: commitments.map { |k| [k[0], k[2]] } },
      { name: "Collected", data: commitments.map { |k| [k[0], k[3]] } },
      { name: "Distributed", data: commitments.map { |k| [k[0], k[4]] } }
    ],
                 library: {
                   plotOptions: { column: {
                     dataLabels: {
                       enabled: true,
                       format: "{point.y:,.2f}"
                     }
                   } },
                   **chart_theme_color
                 }
  end

  def email_list_for(model)
    case model.class.name
    when "Fund"
      capital_commitments = model.capital_commitments
      access_rights = model.access_rights
      investors = model.committed_investors
      investor_accesses = model.entity.investor_accesses.joins(:investor).merge(investors).distinct
    when "CapitalCall"
      model.fund
      capital_commitments = model.capital_commitments
      access_rights = model.fund.access_rights
      investors = model.committed_investors
      investor_accesses = model.entity.investor_accesses.joins(:investor).merge(investors).distinct
    when "CapitalDistribution"
      model.fund
      capital_commitments = model.capital_commitments
      access_rights = model.fund.access_rights
      investors = model.investors
      investor_accesses = model.entity.investor_accesses.joins(:investor).merge(investors).distinct
    end

    # This is the commitments that do not have access rights for the investor in this fund
    commitments_wo_access_rights = capital_commitments.where.not(investor_id: access_rights.pluck(:access_to_investor_id)).includes(:investor).distinct
    # This is the commitments that do not have investor access for the investor in this fund
    commitment_wo_investor_accesses = capital_commitments.where(investor_id: investors.without_investor_accesses.select(:id)).includes(:investor).distinct

    # Total number of folios (capital commitments)
    no_of_folios = capital_commitments.count

    # Number of folios that do NOT have email access (commitments without access rights but not missing investor access)
    no_of_folios_no_email = (commitments_wo_access_rights.pluck(:id) | commitment_wo_investor_accesses.pluck(:id)).length

    # Number of folios that DO have email access
    no_of_folios_with_email = no_of_folios - no_of_folios_no_email

    # Total number of investors
    no_of_investors = investors.count

    # Number of investors who will NOT receive emails
    no_of_investors_no_email = investors.where(will_receive_email: 0).count

    # Number of investors who WILL receive emails
    no_of_investors_with_email = no_of_investors - no_of_investors_no_email

    # This is the investor accesses that are not approved
    unapproved_investor_accesses = investor_accesses.unapproved.includes(:user, :granter).distinct
    # This is the investor accesses that are approved and have email enabled
    approved_investor_access = investor_accesses.approved.email_enabled.not_investor_advisors.includes(:user, :granter).distinct
    approved_investor_access_ia = investor_accesses.approved.email_enabled.investor_advisors.includes(:user, :granter).distinct
    # The challenge is that Investor Advisors, may not have permission to the fund
    approved_investor_access_ia = approved_investor_access_ia.filter do |ia|
      FundPolicy.new(ia.user, model).permissioned_investor_advisor?(as_entity_id: model.entity_id)
    end

    # Number of users who either have email disabled or are not approved
    no_of_users_no_email = investor_accesses.where("email_enabled=? or approved = ?", false, false).count
    # Total number of users with investor access
    no_of_users = approved_investor_access.count + approved_investor_access_ia.count + no_of_users_no_email
    # Number of users who have email enabled and are approved
    no_of_users_with_email = no_of_users - no_of_users_no_email

    # This is the investor accesses that are email disabled
    email_disabled_investor_accesses = investor_accesses.email_disabled.includes(:user, :granter).distinct

    {
      no_of_folios: no_of_folios,
      no_of_folios_no_email: no_of_folios_no_email,
      no_of_folios_with_email: no_of_folios_with_email,
      no_of_investors: no_of_investors,
      no_of_investors_no_email: no_of_investors_no_email,
      no_of_investors_with_email: no_of_investors_with_email,
      no_of_users: no_of_users,
      no_of_users_no_email: no_of_users_no_email,
      no_of_users_with_email: no_of_users_with_email,
      commitments_wo_access_rights: commitments_wo_access_rights,
      commitment_wo_investor_accesses: commitment_wo_investor_accesses,
      unapproved_investor_accesses: unapproved_investor_accesses,
      approved_investor_access: approved_investor_access,
      approved_investor_access_count: approved_investor_access.count,
      approved_investor_access_ia: approved_investor_access_ia,
      approved_investor_access_ia_count: approved_investor_access_ia.count,
      email_disabled_investor_accesses: email_disabled_investor_accesses
    }
  end

  def render_number_stats_cards(results_map, card_definitions)
    cards_data = card_definitions.map do |definition|
      stat_value = results_map[definition[:key]]
      {
        path: definition[:path],
        stat: stat_value.respond_to?(:count) ? stat_value.count : stat_value,
        subtitle: definition[:subtitle],
        progress_bar_color: definition[:progress_bar_color],
        text_info: definition[:text_info]
      }
    end

    render(partial: "funds/number_stats_cards", locals: { cards_data: cards_data })
  end
end
