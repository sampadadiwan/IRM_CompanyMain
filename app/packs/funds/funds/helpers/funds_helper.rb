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

  # Provides a comprehensive list of email-related statistics and investor access details
  # for a given model (Fund, CapitalCall, or CapitalDistribution).
  #
  # @param model [Object] An instance of Fund, CapitalCall, or CapitalDistribution.
  # @return [Hash] A hash containing various counts and collections related to folios,
  #   investors, and user access rights for email communication.
  def email_list_for(model)
    # Initialize core data based on the model type
    data = initialize_email_list_data(model)
    capital_commitments = data[:capital_commitments]
    access_rights = data[:access_rights]
    investors = data[:investors]
    investor_accesses = data[:investor_accesses]

    # Calculate statistics related to folios (capital commitments)
    folio_stats = calculate_folio_stats(capital_commitments, access_rights, investors)

    # Calculate statistics related to investors
    investor_stats = calculate_investor_stats(investors)

    # Calculate statistics and filter investor accesses related to user email permissions
    user_access_stats = calculate_user_access_stats(model, investor_accesses)

    # Combine all calculated statistics into a single hash for return
    {
      no_of_folios: folio_stats[:no_of_folios],
      no_of_folios_no_email: folio_stats[:no_of_folios_no_email],
      no_of_folios_with_email: folio_stats[:no_of_folios_with_email],
      no_of_investors: investor_stats[:no_of_investors],
      no_of_investors_no_email: investor_stats[:no_of_investors_no_email],
      no_of_investors_with_email: investor_stats[:no_of_investors_with_email],
      no_of_users: user_access_stats[:no_of_users],
      no_of_users_no_email: user_access_stats[:no_of_users_no_email],
      no_of_users_with_email: user_access_stats[:no_of_users_with_email],
      commitments_wo_access_rights: folio_stats[:commitments_wo_access_rights],
      commitment_wo_investor_accesses: folio_stats[:commitment_wo_investor_accesses],
      unapproved_investor_accesses: user_access_stats[:unapproved_investor_accesses],
      approved_investor_access: user_access_stats[:approved_investor_access],
      approved_investor_access_count: user_access_stats[:approved_investor_access_count],
      approved_investor_access_ia: user_access_stats[:approved_investor_access_ia],
      approved_investor_access_ia_count: user_access_stats[:approved_investor_access_ia_count],
      email_disabled_investor_accesses: user_access_stats[:email_disabled_investor_accesses]
    }
  end

  private

  # Initializes and returns the core data (capital commitments, access rights, investors, investor accesses)
  # based on the type of the provided model.
  #
  # @param model [Object] An instance of Fund, CapitalCall, or CapitalDistribution.
  # @return [Hash] A hash containing initialized ActiveRecord relations.
  def initialize_email_list_data(model)
    case model.class.name
    when "Fund"
      capital_commitments = model.capital_commitments
      access_rights = model.access_rights
      investors = model.committed_investors
      investor_accesses = model.entity.investor_accesses.joins(:investor).merge(investors).distinct
    when "CapitalCall"
      # For CapitalCall, fund-related data is accessed via model.fund
      capital_commitments = model.capital_commitments
      access_rights = model.fund.access_rights
      investors = model.committed_investors
      investor_accesses = model.entity.investor_accesses.joins(:investor).merge(investors).distinct
    when "CapitalDistribution"
      # For CapitalDistribution, fund-related data is accessed via model.fund
      capital_commitments = model.capital_commitments
      access_rights = model.fund.access_rights
      investors = model.investors
      investor_accesses = model.entity.investor_accesses.joins(:investor).merge(investors).distinct
    else
      # Handle unexpected model types or raise an error
      raise ArgumentError, "Unsupported model type: #{model.class.name}"
    end
    {
      capital_commitments: capital_commitments,
      access_rights: access_rights,
      investors: investors,
      investor_accesses: investor_accesses
    }
  end

  # Calculates statistics related to capital commitments (folios).
  #
  # @param capital_commitments [ActiveRecord::Relation] Collection of capital commitments.
  # @param access_rights [ActiveRecord::Relation] Collection of access rights.
  # @param investors [ActiveRecord::Relation] Collection of investors.
  # @return [Hash] A hash containing folio counts and specific commitment collections.
  def calculate_folio_stats(capital_commitments, access_rights, investors)
    # Commitments that do not have access rights for the investor in this fund
    commitments_wo_access_rights = capital_commitments.where.not(investor_id: access_rights.pluck(:access_to_investor_id)).includes(:investor).distinct
    # Commitments that do not have investor access for the investor in this fund
    commitment_wo_investor_accesses = capital_commitments.where(investor_id: investors.without_investor_accesses.select(:id)).includes(:investor).distinct

    # Total number of folios (capital commitments)
    no_of_folios = capital_commitments.count
    # Number of folios that do NOT have email access (union of commitments without access rights and without investor access)
    no_of_folios_no_email = (commitments_wo_access_rights.pluck(:id) | commitment_wo_investor_accesses.pluck(:id)).length
    # Number of folios that DO have email access
    no_of_folios_with_email = no_of_folios - no_of_folios_no_email

    {
      no_of_folios: no_of_folios,
      no_of_folios_no_email: no_of_folios_no_email,
      no_of_folios_with_email: no_of_folios_with_email,
      commitments_wo_access_rights: commitments_wo_access_rights,
      commitment_wo_investor_accesses: commitment_wo_investor_accesses
    }
  end

  # Calculates statistics related to investors.
  #
  # @param investors [ActiveRecord::Relation] Collection of investors.
  # @return [Hash] A hash containing investor counts.
  def calculate_investor_stats(investors)
    # Total number of investors
    no_of_investors = investors.count
    # Number of investors who will NOT receive emails (based on will_receive_email flag)
    no_of_investors_no_email = investors.where(will_receive_email: 0).count
    # Number of investors who WILL receive emails
    no_of_investors_with_email = no_of_investors - no_of_investors_no_email

    {
      no_of_investors: no_of_investors,
      no_of_investors_no_email: no_of_investors_no_email,
      no_of_investors_with_email: no_of_investors_with_email
    }
  end

  # Calculates statistics and filters investor accesses related to user email permissions.
  #
  # @param model [Object] An instance of Fund, CapitalCall, or CapitalDistribution (used for FundPolicy).
  # @param investor_accesses [ActiveRecord::Relation] Collection of investor accesses.
  # @return [Hash] A hash containing user access counts and specific investor access collections.
  def calculate_user_access_stats(model, investor_accesses)
    # Investor accesses that are not approved
    unapproved_investor_accesses = investor_accesses.unapproved.includes(:user, :granter).distinct
    # Investor accesses that are approved, have email enabled, and are not investor advisors
    approved_investor_access = investor_accesses.approved.email_enabled.not_investor_advisors.includes(:user, :granter).distinct
    # Investor accesses that are approved, have email enabled, and are investor advisors
    approved_investor_access_ia = investor_accesses.approved.email_enabled.investor_advisors.includes(:user, :granter).distinct

    # Filter Investor Advisors to ensure they have permission to the fund
    approved_investor_access_ia = approved_investor_access_ia.filter do |ia|
      FundPolicy.new(ia.user, model).permissioned_investor_advisor?(as_entity_id: model.entity_id)
    end

    # Number of users who either have email disabled or are not approved
    no_of_users_no_email = investor_accesses.where("email_enabled=? or approved = ?", false, false).count
    # Total number of users with investor access (approved + unapproved/email disabled)
    no_of_users = approved_investor_access.count + approved_investor_access_ia.count + no_of_users_no_email
    # Number of users who have email enabled and are approved
    no_of_users_with_email = no_of_users - no_of_users_no_email

    # Investor accesses that are email disabled
    email_disabled_investor_accesses = investor_accesses.email_disabled.includes(:user, :granter).distinct

    {
      unapproved_investor_accesses: unapproved_investor_accesses,
      approved_investor_access: approved_investor_access,
      approved_investor_access_count: approved_investor_access.count,
      approved_investor_access_ia: approved_investor_access_ia,
      approved_investor_access_ia_count: approved_investor_access_ia.count,
      no_of_users_no_email: no_of_users_no_email,
      no_of_users: no_of_users,
      no_of_users_with_email: no_of_users_with_email,
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
