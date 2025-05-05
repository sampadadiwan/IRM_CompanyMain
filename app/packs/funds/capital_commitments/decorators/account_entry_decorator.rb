class AccountEntryDecorator < ApplicationDecorator
  def folio_id
    h.link_to object.folio_id, object.capital_commitment if object.folio_id.present?
  end

  def parent_name
    h.link_to object.parent_name, "/#{object.parent_type.underscore.pluralize}/#{object.parent_id}" if object.parent_type.present? && object.parent_id.present?
  end

  def entry_type
    if account_entry.cumulative
      h.raw "#{object.entry_type} <br> <span class='badge bg-success'>Cumulative<span>"
    else
      object.entry_type
    end
  end

  def amount
    if object&.name&.include?("Percentage")
      "#{object.amount_cents} %"
    else
      h.money_to_currency object.amount
    end
  end

  # Just an example of a complex method you can add to you decorator
  # To render it in a datatable just add a column 'dt_actions' in
  # 'view_columns' and 'data' methods and call record.decorate.dt_actions
  def dt_actions
    links = []
    links << h.link_to('Show', h.account_entry_path(object), class: "btn btn-outline-primary ti ti-eye")
    links << h.link_to('Edit', h.edit_account_entry_path(object), class: "btn btn-outline-success ti ti-edit") if h.policy(object).update?
    h.safe_join(links, '')
  end
end
