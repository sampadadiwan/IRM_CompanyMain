class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def investors
    investor_list = []
    access_rights.includes(:investor).find_each do |ar|
      investor_list += ar.investors
    end
    investor_list.uniq
  end

  def index_record?
    index_class = "#{self.class.name}Index".constantize
    index_flag = previous_changes.empty? || previous_changes.keys.map(&:to_sym).intersect?(index_class::SEARCH_FIELDS)
    Rails.logger.debug { "#{previous_changes.keys.map(&:to_sym)} & #{index_class::SEARCH_FIELDS}  index_flag - #{index_flag}" }
    index_flag
  end
end
