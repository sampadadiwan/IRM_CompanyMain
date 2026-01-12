class GenerateHorizontalCapTable < Trailblazer::Operation
  step :initialize_params
  step :fetch_metadata
  step :initialize_table_data
  step :process_rounds
  step :format_result

  def initialize_params(options, params:, **)
    options[:portfolio_company_id] = params[:portfolio_company_id]
  end

  def fetch_metadata(options, portfolio_company_id:, **)
    investments = Investment.where(portfolio_company_id: portfolio_company_id)
    options[:all_investments] = investments.to_a # Fetch everything once to avoid N+1
    options[:all_funding_rounds] = investments.order(investment_date: :asc).pluck(:funding_round).uniq
    options[:all_investors] = investments.select(:investor_name, :category).distinct.to_a

    portfolio_company = Investor.find(portfolio_company_id)
    options[:portfolio_company_name] = portfolio_company.entity.name
  end

  def initialize_table_data(options, all_investors:, portfolio_company_name:, **)
    # Replace investor_name with portfolio_company_name for "Self" records in the grouping
    investors = all_investors.map do |i|
      name = i.category == "Self" ? portfolio_company_name : i.investor_name
      OpenStruct.new(investor_name: name, category: i.category)
    end

    options[:investors_by_category] = investors.group_by(&:category)
    options[:table_data] = {}
    options[:round_data] = {}
  end

  def process_rounds(_options, all_funding_rounds:, portfolio_company_id:, all_investors:, table_data:, round_data:, **)
    cumulative_rounds = []

    all_funding_rounds.each do |round|
      cumulative_rounds << round

      result = GenerateCapTable.call(params: {
                                       funding_rounds: cumulative_rounds,
                                       portfolio_company_id: portfolio_company_id
                                     })

      cap_round = result[:model]
      next if cap_round.blank?

      # Extract total for this round
      total_row = cap_round.find { |r| r[:grouping_field] == "Total" }
      round_data[round] = {
        total_equity: total_row[:quantity],
        total_fully_diluted: total_row[:fully_diluted]
      }

      # Fill table_data
      cap_round.each do |row|
        next if row[:grouping_field] == "Total"

        # Special handling for "Self"
        if row[:is_self] || row[:grouping_field] == _options[:portfolio_company_name]
          category = "Self"
          investor_name = _options[:portfolio_company_name]
        else
          # Find investor to get category
          investor = all_investors.find { |i| i.investor_name == row[:grouping_field] }
          if investor
            category = investor.category
            investor_name = investor.investor_name
          else
            next
          end
        end

        table_data[category] ||= {}
        table_data[category][investor_name] ||= {}
        table_data[category][investor_name][round] = {
          fully_diluted_percentage: row[:fully_diluted_percentage],
          quantity: row[:quantity],
          fully_diluted: row[:fully_diluted]
        }
      end
    end
  end

  def format_result(options, all_funding_rounds:, investors_by_category:, table_data:, round_data:, **)
    options[:model] = {
      funding_rounds: all_funding_rounds,
      categories: investors_by_category.keys.sort,
      investors_by_category: investors_by_category,
      table_data: table_data,
      round_data: round_data
    }
  end
end
