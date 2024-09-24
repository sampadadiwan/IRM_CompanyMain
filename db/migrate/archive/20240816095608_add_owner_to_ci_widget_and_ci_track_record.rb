class AddOwnerToCiWidgetAndCiTrackRecord < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:ci_widgets, :owner_id)
      add_reference :ci_widgets, :owner, polymorphic: true
    end
    unless column_exists?(:ci_track_records, :owner_id)
      add_reference :ci_track_records, :owner, polymorphic: true
    end
    CiWidget.all.each do |cw|
      Rails.logger.debug { "Updating owner for CiWidget #{cw.id}" }
      cw.update!(owner: cw.investment_opportunity) if cw.investment_opportunity.present?
    end
    CiTrackRecord.all.each do |ctr|
      ctr.update!(owner: ctr.investment_opportunity) if ctr.investment_opportunity.present?
    end
  end
end
