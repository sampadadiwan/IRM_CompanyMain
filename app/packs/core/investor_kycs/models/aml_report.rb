class AmlReport < ApplicationRecord
  belongs_to :investor_kyc
  belongs_to :entity
  belongs_to :investor
  belongs_to :approved_by, class_name: "User", optional: true

  AML_URL = "https://api.idfy.com/v3/tasks/sync/verify_with_source/aml".freeze

  enum :match_status, { potential_match: "Potential Match", no_match: "No Match" }

  validates :approved_by_id, presence: true, if: :approved?
  validates :name, presence: true

  before_save :set_approved_on, if: :approved_changed?
  def set_approved_on
    self.approved_on = Time.zone.now if approved?
  end

  AML_TYPES = {
    "pep" => "pep",
    "pep_class_1" => "pep-class-1",
    "pep_class_2" => "pep-class-2",
    "pep_class_3" => "pep-class-3",
    "pep_class_4" => "pep-class-4",
    "adverse_media" => "adverse-media",
    "sanction" => "sanction"
  }.freeze

  # create fuzziness hash with high medium low and exact Match
  FUZZINESS = {
    "high" => "high",
    "medium" => "medium",
    "low" => "low",
    "exact_match" => "exact-match"
  }.freeze

  AML_ENTITY_TYPES = {
    "person" => "person",
    "company" => "company"
  }.freeze

  scope :approved, -> { where(approved: true) }

  scope :for_advisor, lambda { |user|
    # Ensure the access rghts for Document
    joins(entity: :investors)
      .where("investors.category=? and investors.investor_entity_id=?", 'Advisor', user.entity_id)
  }

  # accepts specific types as well as all and pep_all
  def self.aml_types(types)
    types_result = []
    if types.include?("all")
      types_result = AML_TYPES.values
      return types_result
    end
    if types.include?("pep_all")
      types_result << AML_TYPES.values_at("pep", "pep_class_1", "pep_class_2", "pep_class_3", "pep_class_4")
      types.delete("pep_all")
    end
    types_result << AML_TYPES.values_at(*types)
    types_result.flatten.uniq
  end

  def generate(options = {})
    json_response = AmlApiResponseService.new.get_response(name, options)
    store_data(json_response)
  end

  def store_data(json_response)
    # Store data in DB
    self.response = json_response
    return if json_response['hits'].blank?

    self.match_status = json_response['match_status'].titleize
    association = {}
    # populate association hash
    json_response['hits'].map { |arr_element| arr_element['doc']['associates'] }&.flatten&.map { |associates_hash| association[associates_hash['name']] = associates_hash['association'] if associates_hash.is_a?(Hash) }
    self.associates = association
    # populate aml types and any additional fields
    self.types = json_response['hits'].map { |arr| arr['doc']['types'] }.flatten.compact.uniq.join(', ')
    self.fields = json_response['hits'].map { |arr| arr['doc']['fields'] }.flatten.compact.group_by { |ff| ff['name'] }
    self.source_notes = json_response['hits'].map { |arr| arr['doc']['source_notes'] }.flatten.compact
    self.media = json_response['hits'].map { |arr| arr['doc']['media'] }.flatten.compact
  end

  def get_source_notes_array
    source_notes_array = []
    return source_notes_array if source_notes.blank?

    source_notes.each do |element|
      source_notes_array << element.values.flatten
    end
    source_notes_array.flatten
  end
end
