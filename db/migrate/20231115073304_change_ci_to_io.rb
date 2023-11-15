class ChangeCiToIo < ActiveRecord::Migration[7.1]
  def change
    CiWidget.delete_all
    CiTrackRecord.delete_all
    remove_reference :ci_widgets, :ci_profile, index: true, foreign_key: true
    add_reference :ci_widgets, :investment_opportunity, index: true, foreign_key: true
    remove_reference :ci_track_records, :ci_profile, index: true, foreign_key: true
    add_reference :ci_track_records, :investment_opportunity, index: true, foreign_key: true
  end
end
