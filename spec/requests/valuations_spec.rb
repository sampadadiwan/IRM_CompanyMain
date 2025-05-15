require 'swagger_helper'

RSpec.describe 'valuations', type: :request do
  let(:user) { 
    entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
    FactoryBot.create(:user, entity:) 
  }


  let(:access_token) { 
    token = user.access_tokens.new(
      access_token: SecureRandom.hex(32),
      refresh_token: SecureRandom.hex(32),
      expires_in: 2.hours.to_i
    )
    token.save!  # This should now work
    token.access_token
   }

  

  path '/valuations.json' do
    get('list valuations') do
      security [BearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, 'successful') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end

    post('create valuation') do
      security [BearerAuth: []]
      consumes 'application/json'
      produces 'application/json'

      parameter name: :Authorization, in: :header, type: :string, required: true

      parameter name: :valuation, in: :body, required: true, schema: {
        type: :object,
        additionalProperties: true
      }

      let(:Authorization) { "Bearer #{access_token}" }
      let(:valuation) { {valuation: FactoryBot.build(:valuation).as_json} }

      response(200, 'successful') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end

  path '/valuations/new.json' do

    get('new valuation') do
      response(200, 'successful') do

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end

  path '/valuations/{id}.json/edit' do
    # You'll want to customize the parameter types...
    parameter name: 'id', in: :path, type: :string, description: 'id'

    get('edit valuation') do
      response(200, 'successful') do
        let(:id) { '123' }

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end

  path '/valuations/{id}.json' do
    # You'll want to customize the parameter types...
    parameter name: 'id', in: :path, type: :string, description: 'id'

    get('show valuation') do
      response(200, 'successful') do
        let(:id) { '123' }

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end

    patch('update valuation') do
      response(200, 'successful') do
        let(:id) { '123' }

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end

    put('update valuation') do
      response(200, 'successful') do
        let(:id) { '123' }

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end

    delete('delete valuation') do
      response(200, 'successful') do
        let(:id) { '123' }

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end
end
