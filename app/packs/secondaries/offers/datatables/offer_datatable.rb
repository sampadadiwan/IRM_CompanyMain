class OfferDatatable < AjaxDatatablesRails::ActiveRecord
  def view_columns
    @view_columns ||= {
      id: { source: "Offer.id", searchable: false },
      user: { source: "Offer.full_name", orderable: true },
      investor_name: { source: "Investor.investor_name", orderable: true },
      quantity: { source: "Offer.quantity", orderable: true },
      percentage: { source: "Offer.percentage", orderable: true },
      allocation_quantity: { source: "Offer.allocation_quantity", orderable: true },
      allocation_percentage: { source: "Offer.allocation_percentage", orderable: true },
      final_price: { source: "Offer.final_price", searchable: false },
      allocation_amount: { source: "Offer.allocation_amount_cents", searchable: false },
      notes: { source: "Offer.notes", searchable: false },
      approved: { source: "Offer.approved", searchable: false },
      verified: { source: "Offer.verified", searchable: false },
      dt_actions: { source: "", orderable: false, searchable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        user: record.user,
        investor_name: record.decorate.investor_link,
        quantity: record.quantity,
        percentage: record.decorate.percentage,
        allocation_quantity: record.allocation_quantity,
        allocation_percentage: record.decorate.allocation_percentage,
        final_price: record.final_price,
        allocation_amount: record.decorate.money_to_currency(record.allocation_amount, params),
        notes: record.notes,
        approved: record.decorate.display_boolean(record.approved),
        verified: record.decorate.display_boolean(record.verified),
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "offer_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def offers
    @offers ||= options[:offers]
  end

  def get_raw_records
    offers
  end
end
