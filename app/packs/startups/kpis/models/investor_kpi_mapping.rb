class InvestorKpiMapping < ApplicationRecord
  belongs_to :entity
  belongs_to :investor

  has_one :investor_entity, class_name: "Entity", through: :investor
  has_many :kpis, through: :investor_entity

  scope :show_in_report, -> { where(show_in_report: true) }

  before_create :setup_standard_kpi_name
  def setup_standard_kpi_name
    self.reported_kpi_name = reported_kpi_name.strip
    self.standard_kpi_name = reported_kpi_name if standard_kpi_name.blank?
    self.standard_kpi_name = standard_kpi_name.strip
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[reported_kpi_name standard_kpi_name]
  end

  def self.create_from(entity, kpi_report)
    investor = if kpi_report.portfolio_company_id.present?
                 kpi_report.portfolio_company
               else
                 entity.investors.where(investor_entity_id: kpi_report.entity_id).first
               end
    kpi_report.kpis.each do |kpi|
      ikm = InvestorKpiMapping.find_or_initialize_by(entity:, investor:, reported_kpi_name: kpi.name, standard_kpi_name: kpi.name)
      if ikm.new_record?
        ikm.show_in_report = true
        ikm.save
      end
    end
  end

  def to_s
    reported_kpi_name
  end
end
