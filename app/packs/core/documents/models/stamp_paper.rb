class StampPaper < ApplicationRecord
  belongs_to :entity
  # Is the offer, commitment etc whose document needs to be signed
  belongs_to :owner, polymorphic: true

  before_validation :setup_entity
  def setup_entity
    self.entity_id = owner.entity_id
  end

  validate :tags_format
  def tags_format
    all_tags = tags&.split(',')&.map(&:strip)
    if tags.present?
      if all_tags.size == all_tags.uniq.size
        errors.add(:tags, "cannot be repeated") unless all_tags.map { |tag| tag.split(':').first } == all_tags.map { |tag| tag.split(':').first }.uniq
      else
        errors.add(:tags, "should be comma separated")
      end
      all_tags.each do |tag|
        errors.add(:tags, "should be in format `tag:quantity`") unless tag.split(':').last.to_i.positive?
        # errors.add(:tags, "quantity should be greater than 0") if tag.split(':').last.to_i <= 0
      end
      validate_tags_with_entity
    end
  end

  def validate_tags_with_entity
    tags.split(',').map(&:strip).map { |tg| tg.split(':').first }.each do |tag|
      errors.add(:tags, "should be one of #{entity.entity_setting.stamp_paper_tags}") unless entity.entity_setting.stamp_paper_tags&.split(',')&.map(&:strip)&.include?(tag)
    end
  end

  after_save :update_owner
  def update_owner
    owner.template = true
    owner.save
  end
end
