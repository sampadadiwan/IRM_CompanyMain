class ApplicationDataframe
  def df(sql, params)
    begin
      # Read the database and create a dataframe
      df = Polars.read_database(sql)

      # Enhance the dataframe, in case additional cols need to be added for processing
      df = enhance_df(df)

      # Group the dataframe if group fields are present
      if params[:group_fields].present?
        # sum/avg/count the field based on the agg_type
        params[:agg_type]
        # The list of fields to aggregate
        agg_field = params[:agg_field]
        aggregations = if agg_field.is_a?(Array)
                         # If the aggregation type is an array, sum the fields
                         agg_field.map do |field|
                           Polars.col(field).sum.alias("#{field}_total")
                         end
                       else
                         # If the aggregation field is a string, sum the field
                         [Polars.col(agg_field).sum.alias("#{agg_field}_total")]
                       end

        # Group the DF based on the group fields and aggregate the field
        df = df.group_by(params[:group_fields]).agg(aggregations)
      end
    rescue StandardError => e
      # Log the error and notify the exception
      Rails.logger.debug e.backtrace
      ExceptionNotifier.notify_exception(e, data: { message: "Error in generating account entries DF" })
    end

    # Return the dataframe
    df
  end

  # This is called by the ApplicationDataframe class to enhance the dataframe, override this method in the subclass, to add additional columns
  def enhance_df(_dataframe)
    raise "This method should be overridden in the subclass"
  end
end
