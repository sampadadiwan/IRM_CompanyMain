  
  Given('there is a kyc {string}') do |args|
    @investor_kyc = FactoryBot.create(:investor_kyc, entity: @entity, investor: @investor)
    key_values(@investor_kyc, args)
    @investor_kyc.save!
  end
  
  Given('there is a kyc document {string} {string}') do |document_name, file_name|
    Document.create!(entity_id: @investor_kyc.entity_id, name: document_name, owner: @investor_kyc, file: File.new("public/sample_uploads/#{file_name}", "r"), user: @user)    
  end
  
  Given('the doc questions {string}') do |doc_questions_file|
    # Read the XL and create the questions
    doc_questions = Roo::Spreadsheet.open("public/sample_uploads/#{doc_questions_file}")
    doc_questions.each_with_index do |row, index|
      puts "#{doc_questions_file} Row: #{row}"
      next if index == 0 || row[2].blank?
      doc_question = DocQuestion.new
      doc_question.entity_id = @investor_kyc.entity_id
      doc_question.owner = @investor_kyc.entity
      doc_question.tags = row[1]
      doc_question.question = row[2]
      doc_question.for_class = row[3]
      doc_question.document_name = row[4]
      doc_question.qtype = row[5]
      doc_question.save!
    end
  end
  
  Then('when I run the document validation for the kyc') do
    @investor_kyc.validate_all_documents
  end
  
  Then('the kyc validation doc questions answers must be {string}') do |answer|

    validations = DocQuestion.validations
    VariableInterpolation.replace_variables(validations, @investor_kyc)
    validation_questions = validations.collect(&:interpolated_question).uniq
    count = 0

    @investor_kyc.doc_question_answers.each do |document_name, qna|
      ap qna
      qna.each do |question, response|
        # binding.pry
        next unless response["question_type"] == "Validation"
        puts "Document: #{document_name}, Question: #{question}, Checking Response #{response["answer"]} to #{answer}"
        response["answer"].downcase.should == answer.downcase
        count += 1
      end
    end    

    count.should == validation_questions.size
  end

  Then('the kyc extraction doc questions answers must be {string}') do |answers|

    extractions = DocQuestion.extractions
    VariableInterpolation.replace_variables(extractions, @investor_kyc)
    extraction_questions = extractions.collect(&:interpolated_question).uniq.map{|q| q.downcase}
    count = 0

    key_val = answers.split(";").map { |kv| kv.split("=") }.to_h
    key_val.each do |k, v|
      @investor_kyc.doc_question_answers.each do |document_name, qna|
        qna.each do |question, response|
          next unless question.downcase.include?( k.gsub("Question: ", "").downcase ) && response["question_type"] == "Extraction" 
          puts "Document: #{document_name}, #{k} #{question}, Checking Response #{response["answer"]} to #{v}"  
          response["answer"].downcase.should == v.downcase
          count += 1
        end
      end
    end

    count.should == extraction_questions.size
  end