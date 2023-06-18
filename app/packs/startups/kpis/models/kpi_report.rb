class KpiReport < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include WithFolder

  belongs_to :entity
  belongs_to :user
  has_many :kpis, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy

  accepts_nested_attributes_for :kpis, reject_if: :all_blank, allow_destroy: true

  def self.custom_fields
    JSON.parse(ENV.fetch("KPIS", nil)).keys.sort
  end

  def custom_kpis
    my_kpis = kpis.to_a
    form_type.form_custom_fields.each do |custom_field|
      kpis << Kpi.new(name: custom_field.name, entity_id:) unless my_kpis.any? { |kpi| kpi.name == custom_field.name }
    end
    kpis
  end

  def name
    "KPI - #{as_of}"
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
end
