module OptionCalculations
  extend ActiveSupport::Concern

  def vesting_schedule
    schedule = []
    schedule_struct = Struct.new(:date, :percentage, :quantity)
    vqty = 0
    count = option_pool.vesting_schedules.count
    option_pool.vesting_schedules.each_with_index do |pvs, idx|
      # The last one needs to be adjusted for any leftover quantity as the
      # vesting_percent may not yield round numbers
      qty = if idx == (count - 1)
              (orig_grant_quantity - vqty)
            else
              (orig_grant_quantity * pvs.vesting_percent / 100.0).floor(0)
            end
      vqty += qty
      schedule << schedule_struct.new(grant_date + pvs.months_from_grant.month, pvs.vesting_percent, qty)
    end
    schedule
  end

  def update_option_dilutes
    self.option_type ||= "Regular"
    self.option_dilutes = false if ["Phantom", "Cash SAR"].include?(self.option_type)
  end

  def compute_vested_quantity
    (orig_grant_quantity * allowed_percentage / 100).floor(0)
  end

  def lapse_date
    _lapsed_quantity, date = compute_lapsed_quantity
    date
  end

  def days_to_lapse
    lapse_date ? (lapse_date - Time.zone.today).to_i : -1
  end

  def lapsed?
    lapse_date ? Time.zone.today > lapse_date : false
  end

  def lapse
    lapsed_quantity, _date = compute_lapsed_quantity
    update(lapsed: true, lapsed_quantity:, audit_comment: "Holding lapsed") if lapsed?
  end

  def allowed_percentage
    option_pool.get_allowed_percentage(grant_date)
  end

  def excercisable?
    investment_instrument == "Options" &&
      vested_quantity.positive? &&
      !cancelled &&
      !lapsed
  end

  def vesting_breakdown
    schedules = option_pool.vesting_schedules.order(months_from_grant: :asc)
    vesting_breakdown = Struct.new(:vesting_date, :quantity, :lapsed_quantity, :excercised_quantity, :expiry_date)
    schedules.map do |vs|
      vesting_breakdown.new(grant_date + vs.months_from_grant.months,
                            (orig_grant_quantity * vs.vesting_percent) / 100, 0, 0)
    end
  end

  def compute_lapsed_quantity
    lapsed_breakdown = []
    first_expiry_date = nil

    vesting_breakdown.each do |struct|
      # excercise_period_months after the vesting date - the option expires
      struct.expiry_date = struct.vesting_date + option_pool.excercise_period_months.months

      if struct.expiry_date < Time.zone.today
        # But did we excercise it?
        struct.excercised_quantity = excercises.where("approved_on > ? and approved_on < ?",
                                                      struct.vesting_date, struct.expiry_date).sum(:quantity)
        # This has expired
        struct.lapsed_quantity += struct.quantity - struct.excercised_quantity

        first_expiry_date ||= struct.expiry_date if struct.lapsed_quantity.positive?
      end

      lapsed_breakdown << struct
    end

    Rails.logger.debug lapsed_breakdown
    qty = lapsed_breakdown.inject(0) { |sum, e| sum + e.lapsed_quantity }
    [qty, first_expiry_date]
  end

  def update_option_quantity
    self.cancelled_quantity = unexcercised_cancelled_quantity + unvested_cancelled_quantity
    self.uncancelled_quantity = orig_grant_quantity - cancelled_quantity - lapsed_quantity

    self.gross_avail_to_excercise_quantity = vested_quantity - excercised_quantity - lapsed_quantity
    self.net_avail_to_excercise_quantity = gross_avail_to_excercise_quantity - unexcercised_cancelled_quantity
    self.gross_unvested_quantity = orig_grant_quantity - vested_quantity
    self.net_unvested_quantity = gross_unvested_quantity - unvested_cancelled_quantity

    self.quantity = net_unvested_quantity + net_avail_to_excercise_quantity
  end
end
