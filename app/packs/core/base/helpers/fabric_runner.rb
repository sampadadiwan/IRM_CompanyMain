class FabricRunner
  def run_extract_answers(cmd)
    # Define the command
    cmd ||= "cat /home/thimmaiah/tools/Fabric/Test.txt /home/thimmaiah/tools/Fabric/TestQ.txt | fabric --pattern extract_answers"

    Rails.logger.debug { "Running command: #{cmd}" }
    # Execute the command using Open3.capture3
    stdout, stderr, status = Open3.capture3(cmd)

    # Check if the command was successful
    if status.success?
      # Process the standard output as needed
      Rails.logger.debug { "Command Output:\n#{stdout}" }
      stdout
    else
      # Handle errors appropriately
      Rails.logger.debug { "Command failed with error:\n#{stderr}" }
      # You can choose to raise an exception or handle it as per your requirements
      raise "Fabric command failed: #{stderr}"
    end
  end
end
