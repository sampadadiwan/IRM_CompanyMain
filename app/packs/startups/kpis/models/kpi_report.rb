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
    JSON.parse(ENV.fetch("KPIS", nil)).keys.map(&:titleize).sort
  end

  def self.custom_fields_map
    JSON.parse(ENV.fetch("KPIS", nil))
  end

  def custom_kpis
    my_kpis = kpis.to_a
    form_type.form_custom_fields.each do |custom_field|
      kpis << Kpi.new(name: custom_field.name, entity_id:) unless my_kpis.any? { |kpi| kpi.custom_form_field.id == custom_field.id }
    end
    kpis
  end

  def name
    "#{entity.name} KPI - #{as_of}"
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
