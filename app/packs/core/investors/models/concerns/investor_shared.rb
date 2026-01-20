module InvestorShared
  extend ActiveSupport::Concern

  included do
    scope :advisors, -> { where(category: "Investor Advisor") }
    scope :rms, -> { where(category: ["RM", "Wealth Manager"]) }
    scope :portfolio_companies, -> { where(category: "Portfolio Company") }
    scope :not_portfolio_companies, -> { where.not(category: "Portfolio Company") }
    scope :not_advisors, -> { where.not(category: "Investor Advisor") }
    scope :not_rms, -> { where.not(category: "RM") }

    scope :with_tag_list, lambda { |tags|
      tags = tags.split(",").map(&:strip) unless tags.is_a?(Array)
      where(
        tags.map { "tag_list LIKE ?" }.join(" OR "),
        *tags.map { |t| "%#{t}%" }
      )
    }

    scope :with_any_tags, lambda { |tags|
      next none if tags.blank?

      tag_list = tags.split(",").map(&:strip).compact_blank
      tag_list.inject(nil) do |scope, tag|
        condition = where("tag_list LIKE ?", "%#{tag}%")
        scope ? scope.or(condition) : condition
      end
    }
  end

  def to_s
    "#{investor_name} : #{category}"
  end

  def for_friendly_id
    "#{investor_name}-#{id}"
  end
end
