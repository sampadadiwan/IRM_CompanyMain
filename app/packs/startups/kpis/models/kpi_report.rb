class KpiReport < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include WithFolder

  belongs_to :entity
  # This is in case the fund is uploading the kpis
  belongs_to :portfolio_company, class_name: "Investor", optional: true
  belongs_to :owner, class_name: "Entity", optional: true
  belongs_to :user
  has_many :kpis, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy

  validates :period, length: { maximum: 12 }
  validates :as_of, presence: true

  accepts_nested_attributes_for :kpis, reject_if: :all_blank, allow_destroy: true

  def self.custom_fields
    JSON.parse(ENV.fetch("KPIS", nil)).keys.map(&:titleize).sort
  end

  def custom_kpis
    if form_type
      my_kpis = kpis.to_a
      form_type.form_custom_fields.each do |custom_field|
        kpis << Kpi.new(name: custom_field.name, entity_id:) unless my_kpis.any? { |kpi| kpi.custom_form_field.id == custom_field.id }
      end
    end
    kpis
  end

  def name
    if portfolio_company_id.present?
      "#{portfolio_company.investor_name} - #{as_of}"
    else
      "#{entity.name} - #{as_of}"
    end
  end

  def for_name
    if portfolio_company_id.present?
      portfolio_company.investor_name
    else
      entity.name
    end
  end

  def to_s
    name
  end

  def document_list
    entity.entity_setting.kpi_doc_list
  end

  def folder_path
    "/KPIs/#{name.delete('/')}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[as_of period tag_list owner_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[kpis entity]
  end

  def self.grid(kpi_reports)
    Kpi.where(kpi_report_id: kpi_reports.pluck(:id)).group_by(&:name)
  end

  def investor_for(for_entity_id)
    if portfolio_company_id.present?
      portfolio_company
    else
      Investor.find_by(entity_id: for_entity_id, investor_entity_id: entity_id)
    end
  end
end
