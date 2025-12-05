require 'rails_helper'
require_relative '../../../../../app/packs/core/documents/helpers/doc_gen_context'

RSpec.describe DocGenContext do
  describe '#print_keys' do
    it 'returns a hash of all keys from a nested hash' do
      nested_hash = {
        key1: 'value1',
        key2: {
          key3: 'value3',
          key4: {
            key5: 'value5'
          }
        },
        key6: [
          { item_key1: 'item_value1' },
          OpenStruct.new(item_key2: 'item_value2'),
          double('ActiveRecordObject', as_json: { item_key3: 'item_value3' }),
          Draper::CollectionDecorator.new([OpenStruct.new(item_key4: 'item_value4')]),
          Draper::Decorator.new(OpenStruct.new(item_key5: 'item_value5'))
        ]
      }
      doc_gen_context = DocGenContext.new(nested_hash)
      expected_keys = {
        'key1' => nil,
        'key2.key3' => nil,
        'key2.key4.key5' => nil,
        'key6.item_key1' => nil,
        'key6.item_key2' => nil,
        'key6.item_key3' => nil,
        'key6.item_key4' => nil,
        'key6.item_key5' => nil
      }
      expect(doc_gen_context.print_keys).to eq(expected_keys)
    end
  end
end