# frozen_string_literal: true

# for controller in FundsController AccountEntriesController InvestorsController CapitalDistributionPaymentsController DocumentsController CapitalCommitmentsController CapitalCallsController CapitalRemittancesController CapitalRemittancePaymentsController CapitalDistributionsController CapitalDistributionsPaymentsController FundUnitSettingsController FundRatiosController PortfolioInvestmentsController FundUnitsController SessionsController AggregatePortfolioInvestmentsController ValuationsController InvestmentsInstrumentsController; do
# yes | rails generate rspec:swagger $controller
# done

# bin/rswag_add_json_suffix.rb

require 'rails_helper'

RSpec.configure do |config|
  # Specify a root folder where Swagger JSON files are generated
  # NOTE: If you're using the rswag-api to serve API descriptions, you'll need
  # to ensure that it's configured to serve Swagger from the same folder
  config.openapi_root = Rails.root.join('swagger').to_s

  # Define one or more Swagger documents and provide global metadata for each one
  # When you run the 'rswag:specs:swaggerize' rake task, the complete Swagger will
  # be generated at the provided relative path under openapi_root
  # By default, the operations defined in spec files are added to the first
  # document below. You can override this behavior by adding a openapi_spec tag to the
  # the root example_group in your specs, e.g. describe '...', openapi_spec: 'v2/swagger.json'
  config.openapi_specs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.1',
      info: {
        title: 'API V1',
        version: 'v1'
      },
      components: {
        securitySchemes: {
          BearerAuth: {
            type: :http,
            scheme: :bearer,
            bearerFormat: 'JWT' # Optional: describes the token format
          }
        }
      },
      security: [
        {
          BearerAuth: []
        }
      ],
      paths: {},
      servers: [
        {
          url: 'https://app.caphive.com',
          description: 'Production server'
        },
        {
          url: 'https://dev.altconnects.com',
          description: 'Staging server'
        },
        {
          url: 'http://localhost:3001',
          description: 'Local server'
        }
      ]
    }
  }

  # Specify the format of the output Swagger file when running 'rswag:specs:swaggerize'.
  # The openapi_specs configuration option has the filename including format in
  # the key, this may want to be changed to avoid putting yaml in json files.
  # Defaults to json. Accepts ':json' and ':yaml'.
  config.openapi_format = :yaml
end
