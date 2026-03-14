require 'rails_helper'

RSpec.describe InvestorEmailMatcher do
  let(:entity) { FactoryBot.create(:entity) }
  let(:investor) { FactoryBot.create(:investor, entity: entity) }
  let!(:investor_access) { FactoryBot.create(:investor_access, investor: investor, entity: entity, email: 'john@example.com', approved: true) }

  describe '#match' do
    it 'matches a single investor by from_email' do
      matcher = InvestorEmailMatcher.new(from_email: 'john@example.com')
      result = matcher.match
      expect(result[:match_type]).to eq('single')
      expect(result[:investors]).to include(investor)
    end

    it 'matches by to_emails' do
      matcher = InvestorEmailMatcher.new(from_email: 'other@example.com', to_emails: ['john@example.com'])
      result = matcher.match
      expect(result[:match_type]).to eq('single')
      expect(result[:investors]).to include(investor)
    end

    it 'returns multiple matches if different investors match' do
      investor2 = FactoryBot.create(:investor, entity: entity)
      FactoryBot.create(:investor_access, investor: investor2, entity: entity, email: 'jane@example.com', approved: true)

      matcher = InvestorEmailMatcher.new(from_email: 'john@example.com', to_emails: ['jane@example.com'])
      result = matcher.match
      expect(result[:match_type]).to eq('multiple')
      expect(result[:investors]).to include(investor, investor2)
    end

    it 'returns single match if multiple emails match same investor' do
      FactoryBot.create(:investor_access, investor: investor, entity: entity, email: 'john.work@example.com', approved: true)

      matcher = InvestorEmailMatcher.new(from_email: 'john@example.com', to_emails: ['john.work@example.com'])
      result = matcher.match
      expect(result[:match_type]).to eq('single')
      expect(result[:investors]).to eq([investor])
    end

    it 'returns none if no matches' do
      matcher = InvestorEmailMatcher.new(from_email: 'none@example.com')
      result = matcher.match
      expect(result[:match_type]).to eq('none')
      expect(result[:investors]).to be_empty
    end
  end
end
