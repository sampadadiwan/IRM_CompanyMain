get "/health_check/redis_check", to: "health_check#redis_check"
get "/health_check/db_check", to: "health_check#db_check"
get "/health_check/elastic_check", to: "health_check#elastic_check"
get "/health_check/xirr_check", to: "health_check#xirr_check"
get "/health_check/replication_check", to: "health_check#replication_check"
get "/health_check/disk_check", to: "health_check#disk_check"

get '/oauth2callback', to: 'entities#dashboard'

case Rails.configuration.upload_server
when :s3
  # By default in production we use s3, including upload directly to S3 with
  # signed url.
  mount Shrine.presign_endpoint(:cache) => "/s3/params"
when :s3_multipart
  # Still upload directly to S3, but using Uppy's AwsS3Multipart plugin
  mount Shrine.uppy_s3_multipart(:cache) => "/s3/multipart"
when :app
  # In development and test environment by default we're using filesystem storage
  # for speed, so on the client side we'll upload files to our app.
  mount Shrine.upload_endpoint(:cache) => "/upload"
end

require 'sidekiq/web'
require 'sidekiq/cron/web'

authenticate :user, ->(user) { user.has_cached_role?(:super) } do
  mount Sidekiq::Web => '/sidekiq'
  mount Blazer::Engine, at: "blazer"
end

resources :boards do
  get 'owner_ids', on: :collection
  get 'archived_kanban_columns', on: :collection
end

resources :kanban_cards do
  patch 'move_kanban_card', on: :member
  get 'search', on: :collection
  patch 'update_sequence', on: :member
end

resources :kanban_columns do
  patch 'update_sequence', on: :member
  delete 'delete_column', on: :member
  patch 'restore_column', on: :member
end

resources :kanban_boards, controller: "boards"

resources :grid_view_preferences do
  patch 'update_column_sequence', on: :member
  get 'configure_grids', on: :collection
end

resources :events
resources :ticker_feeds
