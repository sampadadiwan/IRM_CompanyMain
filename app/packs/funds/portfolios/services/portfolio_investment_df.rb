class PortfolioInvestmentDf < ApplicationDataframe
  def df(portfolio_investments, _current_user, params)
    # The account entries DF.
    sql = portfolio_investments.joins(:fund, :investment_instrument, :portfolio_company).select("portfolio_investments.*, investment_instruments.*, funds.*, investors.*", "funds.name AS fund_name", "investment_instruments.name AS instrument_name", "investment_instruments.category AS instrument_category", "investment_instruments.currency AS instrument_currency", "investors.investor_name AS portfolio_company_name").to_sql
    # Create the dataframe and return it
    super(sql, params)
  end

  # This is called by the ApplicationDataframe class to enhance the dataframe
  def enhance_df(dataframe)
    # Create an amount column by dividing 'amount_cents' by 100 and rounding to 2 decimal places
    dataframe = dataframe.with_column((Polars.col("amount_cents").cast(:f64) / 100).alias("amount"))
    dataframe = dataframe.with_column((Polars.col("cost_of_sold_cents").cast(:f64) / 100).alias("cost_of_sold"))
    dataframe.with_column((Polars.col("gain_cents").cast(:f64) / 100).alias("gain"))
  end
end
