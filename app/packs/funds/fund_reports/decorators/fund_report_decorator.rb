class FundReportDecorator < ApplicationDecorator
  def name_of_scheme
    h.link_to object.name_of_scheme, object.fund
  end

  def name
    h.link_to object.name, h.fund_report_path(fund_report, view: "report_view")
  end

  # Just an example of a complex method you can add to you decorator
  # To render it in a datatable just add a column 'dt_actions' in
  # 'view_columns' and 'data' methods and call record.decorate.dt_actions
  def dt_actions
    links = []
    links << h.link_to('Show', h.fund_report_path(fund_report, view: "report_view"), class: "btn btn-outline-primary")
    links << h.link_to('Edit', h.edit_fund_report_path(object), class: "btn btn-outline-success") if h.policy(object).update?
    h.safe_join(links, '')
  end
end
