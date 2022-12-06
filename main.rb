# frozen_string_literal: true

require 'net/http'
require 'json'

def env_has_key(key)
  !ENV[key].nil? && ENV[key] != '' ? ENV[key] : abort("Missing #{key}.")
end

def login(username, password)
  uri = URI.parse('https://account.testinium.com/uaa/oauth/token')
  token = 'dGVzdGluaXVtU3VpdGVUcnVzdGVkQ2xpZW50OnRlc3Rpbml1bVN1aXRlU2VjcmV0S2V5'
  req = Net::HTTP::Post.new(uri.request_uri,
                            { 'Content-Type' => 'application/json', 'Authorization' => "Basic #{token}" })
  req.set_form_data({ 'grant_type' => 'password', 'username' => username, 'password' => password })
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  JSON.parse(res.body, symbolize_names: true)[:access_token]
end

def upload(file, access_token)
  uri = URI.parse('https://testinium.io/Testinium.RestApi/api/file/upload')
  req = Net::HTTP::Post.new(uri.request_uri,
                            { 'Accept' => '*/*', 'Authorization' => "Bearer #{access_token}" })
  form_data = [
    ['file', File.open(file)],
    %w[isSignRequired true]
  ]
  req.set_form(form_data, 'multipart/form-data')
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  JSON.parse(res.body, symbolize_names: true)[:file_token]
end

def find_project(project_id, access_token)
  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/projects/#{project_id}")
  req = Net::HTTP::Get.new(uri.request_uri,
                           { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}" })
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  JSON.parse(res.body, symbolize_names: true)
end

def update_project(project, file_name, file_token, access_token)
  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/projects/#{project[:id]}")

  dict = {
    'android_mobile_app' => file_name.to_s,
    'enabled' => true,
    'test_framework' => project[:test_framework],
    'android_file_token' => file_token,
    'test_runner_tool' => project[:test_runner_tool],
    'repository_path' => project[:repository_path],
    'test_file_type' => project[:test_file_type],
    'project_name' => project[:project_name]
  }

  req = Net::HTTP::Put.new(uri.request_uri,
                           { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}" })
  req.body = JSON.dump(dict)
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  JSON.parse(res.body, symbolize_names: true)
end

def start(plan_id, access_token)
  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/plans/#{plan_id}/run")
  req = Net::HTTP::Get.new(uri.request_uri,
                           { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}" })
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  case res
  when Net::HTTPClientError, Net::HTTPServerError
    puts(res.body)
    abort "\nError starting plan: #{res.code} (#{res.message})\n\n"
  end
  JSON.parse(res.body, symbolize_names: true)[:execution_id]
end

def get_report(execution_id, access_token)
  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/executions/#{execution_id}")
  req = Net::HTTP::Get.new(uri.request_uri,
                           { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}" })
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  case res
  when Net::HTTPClientError, Net::HTTPServerError
    puts(res.body)
    abort "\nError getting report: #{res.code} (#{res.message})\n\n"
  end
  data = JSON.parse(res.body, symbolize_names: true)
  result_summary = data[:result_summary]
  if !result_summary[:FAILURE].nil? || !result_summary[:ERROR].nil?
    puts("Plan execution was not successful #{data[:test_result_status_counts]}")
    exit(1)
  else
    puts("Plan execution was successful #{data[:test_result_status_counts]}")
  end
end

def check_status(plan_id, execution_id, test_timeout, access_token)
  if test_timeout <= 0
    puts('Plan timed out')
    exit(1)
  end
  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/plans/#{plan_id}/checkIsRunning")
  req = Net::HTTP::Get.new(uri.request_uri,
                           { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}" })
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  case res
  when Net::HTTPClientError, Net::HTTPServerError
    abort "\nError checking status: #{res.code} (#{res.message})\n\n"
  end
  is_running = JSON.parse(res.body, symbolize_names: true)[:running]
  if is_running
    puts('Plan is still running...')
    sleep(10)
    check_status(plan_id, execution_id, test_timeout - 10, access_token)
  else
    puts('Execution finished')
    true
  end
end

platform = ENV['AC_PLATFORM_TYPE']
type = platform == 'ObjectiveCSwift' ? 'ios' : 'android'

file =  env_has_key('AC_TESTINIUM_APP_PATH')
file_name = File.basename(file)
username = env_has_key('AC_TESTINIUM_USERNAME')
password = env_has_key('AC_TESTINIUM_PASSWORD')
plan_id = env_has_key('AC_TESTINIUM_PLAN_ID')
project_id = env_has_key('AC_TESTINIUM_PROJECT_ID')
test_timeout = env_has_key('AC_TESTINIUM_TIMEOUT').to_i
access_token = login(username, password)
raise("Can't login with given credentials") if access_token.nil?

project = find_project(project_id, access_token)
puts "Uploading #{file_name}..."
file_token = upload(file, access_token)
raise('Upload error') if file_token.nil?

puts "File uploaded successfully #{file_token}"
update_status = update_project(project, file_name, file_token, access_token)
puts 'Project updated successfully'
execution_id = start(plan_id, access_token)
puts("Plan started successfully. Execution Id: #{execution_id}")
puts('Checking the status of plan...')
status = check_status(plan_id, execution_id, test_timeout, access_token)
get_report(execution_id, access_token) if status
