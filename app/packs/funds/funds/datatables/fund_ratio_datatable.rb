class FundRatioDatatable < ApplicationDatatable
  def view_columns
    @view_columns ||= {
      id: { source: "FundRatio.id", searchable: false },
      fund_name: { source: "Fund.name", searchable: true, orderable: true },
      owner_name: { source: "", searchable: false, orderable: false },
      owner_type: { source: "FundRatio.owner_type", searchable: true, orderable: true },
      name: { source: "FundRatio.name", searchable: true, orderable: true },
      display_value: { source: "FundRatio.display_value", searchable: false, orderable: false },
      end_date: { source: "FundRatio.end_date", orderable: true },
      scenario: { source: "FundRatio.scenario", searchable: true, orderable: true },
      dt_actions: { source: "", orderable: false, searchable: false }
    }
  end

  def data
    records.decorate.map do |record|
      {
        id: record.id,
        fund_name: record.fund_name,
        owner_name: record.owner_name,
        owner_type: record.owner_type,
        name: record.name,
        display_value: record.display_value,
        end_date: record.display_date(record.end_date),
        scenario: record.scenario,
        dt_actions: record.dt_actions,
        DT_RowId: "fund_ratio_#{record.id}"
      }
    end
  end

  def fund_ratios
    @fund_ratios ||= options[:fund_ratios]
  end

  def get_raw_records
    fund_ratios.joins(:fund)
  end
end
