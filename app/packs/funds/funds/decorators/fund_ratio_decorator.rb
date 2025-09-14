class FundRatioDecorator < ApplicationDecorator
  def owner_name
    h.link_to object.owner if object.owner
  end

  def fund_name
    h.link_to object.fund.name, h.fund_path(object.fund)
  end

  def name
    h.link_to object.name, h.fund_ratio_path(object)
  end

  def scenario
    if object.portfolio_scenario_id.nil?
      object.scenario
    else
      h.link_to(
        object.scenario,
        h.portfolio_scenario_path(object.portfolio_scenario_id),
        class: 'mb-1 badge bg-primary-subtle text-primary'
      )
    end
  end

  def dt_actions
    links = []
    links << h.link_to('Show', h.fund_ratio_path(object), class: "btn btn-outline-primary ti ti-eye")
    links << h.link_to('Edit', h.edit_fund_ratio_path(object), class: "btn btn-outline-success ti ti-trash") if object.import_upload_id.present?
    h.safe_join(links, '')
  end
end
