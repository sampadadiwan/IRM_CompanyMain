require 'faraday'
require 'json'

class OpenWebUiClient
  API_BASE = ENV['OPEN_WEB_UI_API_BASE'].freeze
  @logger = Logger.new($stdout) # Outputs logs to standard output

  def initialize(token = nil)
    @token = token
    @conn = Faraday.new(url: API_BASE) do |faraday|
      faraday.request :multipart
      faraday.request :url_encoded
      faraday.response :logger, @logger # , bodies: true # Enables logging of request/response
      faraday.headers['Content-Type'] = 'application/json'
      faraday.headers['Authorization'] = "Bearer #{token}" if token
      faraday.adapter Faraday.default_adapter
    end
  end

  def get(path, params = {})
    response = @conn.get(normalized_path(path), params)
    parse_response(response)
  end

  def post(path, payload = {})
    response = @conn.post(normalized_path(path), payload.to_json)
    parse_response(response)
  end

  def post_files(path, payload = {})
    conn = Faraday.new(url: API_BASE) do |faraday|
      faraday.request :multipart
      faraday.request :url_encoded
      faraday.response :logger, @logger, bodies: true
      faraday.headers['Authorization'] = "Bearer #{@token}" if @token # Preserve authorization
      faraday.adapter Faraday.default_adapter
    end

    response = conn.post(normalized_path(path), payload)
    parse_response(response)
  end

  def delete(path)
    response = @conn.delete(normalized_path(path))
    parse_response(response)
  end

  private

  # Helper method to normalize path
  def normalized_path(path)
    path.sub(%r{^/}, '') # Remove leading slash
  end

  def parse_response(response)
    case response.status
    when 200, 201
      JSON.parse(response.body, symbolize_names: true)
    else
      { error: response.status, message: response.body }
    end
  end
end

class OpenWebUiUsers
  def initialize(client)
    @client = client
  end

  def get_users(skip: nil, limit: nil)
    @client.get('/users/', { skip: skip, limit: limit })
  end

  def get_user(user_id)
    @client.get("/users/#{user_id}")
  end

  def update_user(user_id, data)
    @client.post("/users/#{user_id}/update", data)
  end

  def create_user(data)
    @client.post("/users/create", data)
  end

  def delete_user(user_id)
    @client.delete("/users/#{user_id}")
  end
end

class OpenWebUiGroups
  def initialize(client)
    @client = client
  end

  def get_groups
    @client.get('/groups/')
  end

  def create_group(data)
    @client.post('/groups/create', data)
  end

  def get_group(id)
    @client.get("/groups/id/#{id}")
  end

  def update_group(id, data)
    @client.post("/groups/id/#{id}/update", data)
  end

  def delete_group(id)
    @client.delete("/groups/id/#{id}/delete")
  end
end

class OpenWebUiAuths
  def initialize(client)
    @client = client
  end

  def get_session_user
    @client.get('/auths/')
  end

  def add(name, email, password)
    data = { name: name, email: email, password: password,
             profile_image_url: "/user.png", role: "user" }

    @client.post('/auths/add', data)
  end

  def update_profile(data)
    @client.post('/auths/update/profile', data)
  end

  def update_password(data)
    @client.post('/auths/update/password', data)
  end

  def ldap_auth(data)
    @client.post('/auths/ldap', data)
  end

  def signin(data)
    @client.post('/auths/signin', data)
  end

  def signup(data)
    @client.post('/auths/signup', data)
  end

  def signout
    @client.get('/auths/signout')
  end
end

class OpenWebUiKnowledge
  def initialize(client)
    @client = client
  end

  def list_knowledge
    @client.get('/knowledge/list')
  end

  def create_knowledge(data)
    @client.post('/knowledge/create', data)
  end

  def get_knowledge(id)
    @client.get("/knowledge/#{id}")
  end

  def update_knowledge(id, data)
    @client.post("/knowledge/#{id}/update", data)
  end

  def delete_knowledge(id)
    @client.delete("/knowledge/#{id}/delete")
  end

  def file_add(id, data)
    @client.post("/knowledge/#{id}/file/add", data)
  end
end

class OpenWebUiFiles
  @logger = Logger.new($stdout) # Outputs logs to standard output

  def initialize(client)
    @client = client
  end

  def list_files
    @client.get('/files/')
  end

  def upload_file(file_path, file_metadata: {})
    Rails.logger.debug { "Uploading file: #{file_path}" }
    Rails.logger.debug { "File metadata: #{file_metadata}" }

    # For a .docx file, you might use 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    # but 'application/octet-stream' is okay if your API is flexible
    file_part = Faraday::Multipart::FilePart.new(File.open(file_path), 'application/octet-stream')
    # If your server expects `file_metadata=` with no value, just pass an empty string or nil.
    payload = {
      file: file_part,
      file_metadata:
    }

    # Fire the POST request. DO NOT manually set 'Content-Type'—the multipart middleware will do it.
    @client.post_files('/files/', payload)
  end

  def get_file(id)
    @client.get("/files/#{id}")
  end

  def delete_file(id)
    @client.delete("/files/#{id}")
  end
end

# Usage Example
# client = OpenWebUiClient.new('your-access-token')
# users = OpenWebUiUsers.new(client)
# puts users.get_users
# puts users.get_user(1)
# puts users.update_user(1, { name: 'John Doe' })
# puts users.delete_user(1)
# puts auths.signin({ username: 'test', password: 'test123' })
