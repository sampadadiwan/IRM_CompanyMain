module AccountEntryShared
  extend ActiveSupport::Concern

  included do
    include WithExchangeRate

    scope :for_folios, -> { where.not(folio_id: nil) }

    scope :for_aggregate_portfolio_investments, lambda {
      joins("INNER JOIN aggregate_portfolio_investments ON account_entries.parent_id = aggregate_portfolio_investments.id AND account_entries.parent_type = 'AggregatePortfolioInvestment'")
    }

    scope :for_portfolio_investments, lambda {
      joins("INNER JOIN portfolio_investments ON account_entries.parent_id = portfolio_investments.id AND account_entries.parent_type = 'PortfolioInvestment'")
    }

    scope :for_portfolio_companies, lambda {
      joins("INNER JOIN investors ON account_entries.parent_id = investors.id AND account_entries.parent_type = 'Investor'")
    }

    # Optional: Add a scope that filters by a field too
    scope :for_api_portfolio_company, lambda { |portfolio_company_id|
      where(aggregate_portfolio_investments: { portfolio_company_id: portfolio_company_id })
    }

    scope :for_pi_portfolio_company, lambda { |portfolio_company_id|
      where(portfolio_investments: { portfolio_company_id: portfolio_company_id })
    }

    scope :reporting_date_start, ->(reporting_date_start) { where(reporting_date: reporting_date_start..) }
    scope :reporting_date_end, ->(reporting_date_end) { where(reporting_date: ..reporting_date_end) }
    scope :entry_type, ->(entry_type) { where(entry_type:) }
    scope :folio_id, ->(folio_id) { where(folio_id:) }
    scope :cumulative, -> { where(cumulative: true) }
    scope :not_cumulative, -> { where(cumulative: false) }
    scope :generated, -> { where(generated: true) }
    scope :fund_entries, -> { where(capital_commitment_id: nil) }

    serialize :explanation, type: Array

    enum :rule_for, { accounting: "Accounting", reporting: "Reporting" }

    before_validation :setup_defaults

    before_save :setup_rule_for

    before_save :set_folio_amount, if: :capital_commitment
  end

  def set_folio_amount
    # Since the account entry amount is always in the fund currency, we compute the converted folio_amount based on exchange rates.
    if folio_amount_cents.zero?
      self.folio_amount_cents = convert_currency(fund.currency, capital_commitment.folio_currency,
                                                 amount_cents, reporting_date)
    end
  end

  def setup_rule_for
    if fund_formula.present?
      # Set rule_for based on the presence and type of fund_formula
      self.rule_for ||= fund_formula.reporting? ? "reporting" : "accounting"
    elsif rule_for.blank? || rule_for.downcase != "reporting"
      self.rule_for = "accounting"
    end
    # Set rule_for to accounting if it is blank or not "reporting"
  end

  class_methods do
    def total_amount(account_entries, name: nil, entry_type: nil, cumulative: false, start_date: nil, end_date: nil, group_by: nil)
      account_entries = account_entries.where(entry_type:) if entry_type
      account_entries = account_entries.where(name:) if name
      account_entries = account_entries.where(cumulative:)
      account_entries = account_entries.where(reporting_date: start_date..) if start_date
      account_entries = account_entries.where(reporting_date: ..end_date) if end_date

      if group_by.present?
        account_entries.group(group_by).sum(:amount_cents)
      else
        account_entries.sum(:amount_cents)
      end
    end
  end

  def setup_defaults
    self.period = "Q#{(reporting_date.month / 3.0).ceil}-#{reporting_date.year}"
    self.parent_name ||= parent.to_s[0..254] if parent_name.blank? && parent.present?
    self.commitment_name ||= capital_commitment.to_s[0..254] if capital_commitment.present?
  end

  def to_s
    "#{name} #{I18n.l(reporting_date)}"
  end
end
