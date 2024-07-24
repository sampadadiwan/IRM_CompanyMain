require 'aws-sdk-s3'

namespace :s3 do
  desc 'Check if the latest file in the source bucket is present in the destination bucket'
  task :check_latest_file do
    S3CheckJob.perform_now
  end
end