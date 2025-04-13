class ApplicationRecord < ActiveRecord::Base
  SAFE_EVAL_REGEX = /alter|truncate|drop|insert|select|destroy|delete|update|create|save|rollback|system|fork/

  primary_abstract_class
  include DatabaseRoleHelper

  # Currently we write and read from the primary database
  connects_to database: { writing: :primary, reading: :primary }

  # if Rails.env.production?
  #   connects_to database: { writing: :primary, reading: :primary }
  # else
  #   connects_to database: { writing: :primary, reading: :primary_replica }
  # end

  def investors
    investor_list = []
    access_rights.includes(:investor).find_each do |ar|
      investor_list += ar.investors
    end
    investor_list.uniq
  end

  # Check if we should save the record to ES or not
  def index_record?(index_class = nil)
    # For InvestorKyc we have STI, hence index_class is passed in as param, for all else we use the class name
    index_class ||= "#{self.class.name}Index".constantize
    # We need to check if the record is new or any of the searchable fields have changed
    previous_changes.empty? || previous_changes.keys.map(&:to_sym).intersect?(index_class::SEARCH_FIELDS)
    # Only if they have changed we index to ES
  end

  DEFAULT_DATA_TYPE = "String".freeze
  def self.ag_grids_default_columns
    self::STANDARD_COLUMNS.map do |label, key|
      data_type = if key.include?("custom_fields.")
                    DEFAULT_DATA_TYPE
                  else
                    columns_hash[key]&.type.to_s.capitalize.presence ||
                      columns_hash["#{key}_cents"]&.type.to_s.capitalize.presence ||
                      DEFAULT_DATA_TYPE
                  end

      { label: label, key: key, data_type: data_type }
    end
  end

  def default_currency_units
    currency == "INR" ? "Crores" : "Million"
  end

  # This method is used to find the record in the snapshot table or the main table
  # based on the id passed in. If the id is a composite key, we need to find the record in the snapshot table
  # If the id is not a composite key, we need to find the record in the main table
  # If the id is not found in either table, we return nil
  def self.find_or_snapshot(id)
    # Check if the id is a composite key i.e id_yyyymm-dd
    if id.to_s.include?("_")
      # Extract the base id and date from the composite key
      base_id, = id.split("_")
      # If the id is a composite key, we need to find the record in the snapshot table
      snapshot_class = "#{name}Snapshot".constantize
      snapshot_class.find_by(id: base_id)
    else
      # If the id is not a composite key, we need to find the record in the main table
      find_by(id: id)
    end
  end
end
