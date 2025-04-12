class FundSnapshot < FundBase
  def self.primary_key
    %i[id snapshot_date]
  end

  before_create :set_default_snapshot_date

  # setup the snapshot_date to be the current date
  def set_default_snapshot_date
    self.snapshot_date ||= Time.zone.today
  end

  # Ensure the snapshot can never be modified
  def readonly?
    self.snapshot_date.present?
  end
end
