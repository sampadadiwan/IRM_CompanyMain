include ActionView::Helpers::NumberHelper

class AccountEntryDf
  def self.df(account_entries, current_user, params)
    CapitalCommitmentPolicy::Scope.new(current_user, CapitalCommitment).resolve
    FundPolicy::Scope.new(current_user, Fund).resolve.select(:name, :id)

    begin
      # The account entries DF.
      sql = account_entries.joins(:capital_commitment, :fund).select("account_entries.*, capital_commitments.*, funds.*", "funds.name AS fund_name", "account_entries.name as account_entry_name").to_sql
      df = Polars.read_database(sql)

      # Create an amount column by dividing 'amount_cents' by 100 and rounding to 2 decimal places
      df = df.with_column((Polars.col("amount_cents").cast(:f64) / 100).round(2).alias("amount"))

      if params[:group_fields].present?
        agg_field = params[:agg_field]
        agg_type = params[:agg_type]
        # Group the DF based on the group fields and aggregate the field
        df = df.group_by(params[:group_fields]).agg(Polars.col(agg_field).send(agg_type))
      end
    rescue Exception => e
      Rails.logger.debug e.backtrace
      ExceptionNotifier.notify_exception(e, data: { message: "Error in generating account entries DF" })
    end

    df
  end
end
