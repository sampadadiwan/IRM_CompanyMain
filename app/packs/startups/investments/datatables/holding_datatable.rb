class HoldingDatatable < AjaxDatatablesRails::ActiveRecord
  def view_columns
    @view_columns ||= {
      id: { source: "Holding.id" },
      funding_round_name: { source: "FundingRound.name", orderable: true },
      holding_type: { source: "Holding.holding_type", orderable: true },
      user_name: { source: "User.name", orderable: true },
      employee_id: { source: "Holding.employee_id", orderable: true },
      investment_instrument: { source: "Holding.investment_instrument", orderable: true },
      quantity: { source: "Holding.quantity" },
      vested_quantity: { source: "Holding.vested_quantity" },
      excercised_quantity: { source: "Holding.excercised_quantity" },
      net_avail_to_excercise_quantity: { source: "Holding.net_avail_to_excercise_quantity" },
      net_unvested_quantity: { source: "Holding.net_unvested_quantity" },
      grant_date: { source: "Holding.grant_date" },
      created_at: { source: "Holding.created_at" },
      manual_vesting: { source: "Holding.manual_vesting" },
      price: { source: "Holding.price" },
      dt_actions: { source: "", orderable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        holding_type: record.holding_type,
        funding_round_name: record.funding_round_name,
        user_name: record.user_name,
        investor_name: record.decorate.investor_link,
        employee_id: record.decorate.employee_id_link,
        investment_instrument: record.decorate.fund_link,
        quantity: record.decorate.custom_format_number(record.quantity, params),
        status: record.decorate.status,
        vested_quantity: record.decorate..custom_format_number(record.vested_quantity, params),
        excercised_quantity: record.decorate..custom_format_number(record.excercised_quantity, params),
        net_avail_to_excercise_quantity: record.decorate..custom_format_number(record.net_avail_to_excercise_quantity, params),
        net_unvested_quantity: record.decorate..custom_format_number(record.net_unvested_quantity, params),

        grant_date: record.decorate.display_date(record.grant_date, params),
        manual_vesting: record.decorate.display_boolean(manual_vesting),
        created_at: record.decorate.display_date(record.created_at, params),

        price: record.price,
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "holding_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def holdings
    @holdings ||= options[:holdings]
  end

  def get_raw_records
    # insert query here
    if params[:show_docs]
      # Dont load the docs unless we need them
      holdings.left_joins(:investor_kyc).includes(:documents)
    else
      holdings.left_joins(:investor_kyc)
    end
  end

  def search_for
    []
  end
end
