Sidekiq.configure_server do |config|
    # edits the default capsule
    config.queues = %w[critical default low chewy]
    config.concurrency = 5
  
    # define a new capsule which processes jobs from the `serial and doc_gen` queue one at a time
    config.capsule("serial") do |cap|
      cap.concurrency = 1
      cap.queues = %w[serial doc_gen]
    end
end