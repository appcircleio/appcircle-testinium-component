# frozen_string_literal: true

require 'net/http'
require 'json'

def env_has_key(key)
  !ENV[key].nil? && ENV[key] != '' ? ENV[key] : abort("Missing #{key}.")
end

file = env_has_key('AC_TESTINIUM_APP_PATH')
$file = file
$file_name = File.basename(file)
$file_name_str= $file_name.to_s
$extension = File.extname($file_name)
$username = env_has_key('AC_TESTINIUM_USERNAME')
$password = env_has_key('AC_TESTINIUM_PASSWORD')
$plan_id = env_has_key('AC_TESTINIUM_PLAN_ID')
$project_id = env_has_key('AC_TESTINIUM_PROJECT_ID')
$test_timeout = env_has_key('AC_TESTINIUM_TIMEOUT').to_i
$ac_max_failure_percentage = (ENV['AC_TESTINIUM_MAX_FAIL_PERCENTAGE'] || 0).to_i
$company_id = env_has_key('AC_TESTINIUM_COMPANY_ID')

def calc_percent(numerator, denominator)
  if !(denominator>=0)
    puts "Invalid numerator or denominator numbers"
    exit(1)
  elsif denominator==0
    return 0
  else
    return numerator.to_f / denominator.to_f * 100.0
  end
end

def login()
  uri = URI.parse('https://account.testinium.com/uaa/oauth/token')
  token = 'dGVzdGluaXVtU3VpdGVUcnVzdGVkQ2xpZW50OnRlc3Rpbml1bVN1aXRlU2VjcmV0S2V5'
  req = Net::HTTP::Post.new(uri.request_uri,
                            { 'Content-Type' => 'application/json', 'Authorization' => "Basic #{token}" })
  req.set_form_data({ 'grant_type' => 'password', 'username' => $username, 'password' => $password })
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  JSON.parse(res.body, symbolize_names: true)[:access_token]
end

def upload(access_token)
  uri = URI.parse('https://testinium.io/Testinium.RestApi/api/file/upload')
  req = Net::HTTP::Post.new(uri.request_uri,
                            { 'Accept' => '*/*', 'Authorization' => "Bearer #{access_token}" })
  form_data = [
    ['file', File.open($file)],
    %w[isSignRequired true]
  ]
  req.set_form(form_data, 'multipart/form-data')
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  JSON.parse(res.body, symbolize_names: true)
end

def find_project(access_token)
  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/projects/#{$project_id}")
  req = Net::HTTP::Get.new(uri.request_uri,
                           { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}" })
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  JSON.parse(res.body, symbolize_names: true)
end

def update_project(project, file_response, access_token)
  file_token = file_response[:file_token]
  ios_meta= file_response[:meta_data]
  raise('Upload error. File token not found.') if file_token.nil?

  puts "File uploaded successfully #{file_token}"

  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/projects/#{project[:id]}")

  dict = {
    'enabled' => true,
    'test_framework' => project[:test_framework],
    'test_runner_tool' => project[:test_runner_tool],
    'repository_path' => project[:repository_path],
    'test_file_type' => project[:test_file_type],
    'project_name' => project[:project_name]
  }

  case $extension
  when '.ipa'
    puts "iOS app uploading."
    dict[:ios_mobile_app] = $file_name_str
    dict[:ios_app_hash] = project[:ios_app_hash]
    dict[:ios_mobile_app] = $file_name_str
    dict[:ios_file_token] = file_token
    dict[:ios_meta] = ios_meta
  when '.apk'
    puts "Android app uploading."
    dict[:android_mobile_app] = $file_name_str
    dict[:android_file_token] = file_token
  else
    raise 'Error: Only can resign .apk files and .ipa files.'
  end

  req = Net::HTTP::Put.new(uri.request_uri,
                           { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}" })
  req.body = JSON.dump(dict)
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  JSON.parse(res.body, symbolize_names: true)
end

def start(access_token)
  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/plans/#{$plan_id}/run")
  req = Net::HTTP::Get.new(uri.request_uri,
                           { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}"})
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  case res
  when Net::HTTPClientError, Net::HTTPServerError
    puts(res.body)
    puts "\nError starting plan: #{res.code} (#{res.message})\n\n"
    exit(1)
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
    puts "\nError getting report: #{res.code} (#{res.message})\n\n"
    exit(1)
  end

  data = JSON.parse(res.body, symbolize_names: true)
  result_summary = data[:result_summary]
  result_failure_summary = result_summary[:FAILURE] || 0
  result_error_summary = result_summary[:ERROR] || 0
  result_success_summary = result_summary[:SUCCESS] || 0
  puts "Test result summary: #{result_summary}"
  total_summary=result_failure_summary+result_error_summary+result_success_summary

  open(ENV['AC_ENV_FILE_PATH'], 'a') { |f|
    f.puts "AC_TESTINIUM_RESULT_FAILURE_SUMMARY=#{result_failure_summary}"
    f.puts "AC_TESTINIUM_RESULT_ERROR_SUMMARY=#{result_error_summary}"
    f.puts "AC_TESTINIUM_RESULT_SUCCESS_SUMMARY=#{result_success_summary}"
  }

  if ac_max_failure_percentage > 0 && result_failure_summary > 0
    failure_percentage= calc_percent(result_failure_summary, total_summary)
    max_failure_percentage = calc_percent($ac_max_failure_percentage, 100)

    if max_failure_percentage <= failure_percentage || !result_summary[:ERROR].nil?
      puts "The number of failures in the plan exceeded the maximum rate. The process is being stopped. #{data[:test_result_status_counts]}"
      exit(1)
    else
      puts("Number of failures is below the maximum rate. Process continues. #{data[:test_result_status_counts]}")
    end
  else
    warn_message = 'To calculate the failure rate, the following values must be greater than 0:'\
    '\nAC_TESTINIUM_MAX_FAIL_PERCENTAGE: #{AC_TESTINIUM_MAX_FAIL_PERCENTAGE}'\
    '\nTestinium Result Failure Summary: #{result_failure_summary}'
    puts warn_message
  end
end

def check_status(test_timeout, access_token)
  if test_timeout <= 0
    puts('Plan timed out')
    exit(1)
  end
  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/plans/#{$plan_id}/checkIsRunning")
  req = Net::HTTP::Get.new(uri.request_uri,
                           { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}"})
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  case res
  when Net::HTTPClientError, Net::HTTPServerError
    puts "\nError checking status: #{res.code} (#{res.body})\n\n"
    exit(1)
  end
  is_running = JSON.parse(res.body, symbolize_names: true)[:running]
  if is_running
    puts('Plan is still running...')
    sleep(10)
    check_status(test_timeout - 30, access_token)
  else
    puts('Execution finished')
    true
  end
end

access_token = login()
raise("Cannot login to Testinium with given credentials") if access_token.nil?

project = find_project(access_token)
raise("Cannot find projects in Testinium") if project.nil?

puts "Uploading #{$file_name} to Testinium..."
file_response = upload(access_token)
raise("File cannot upload to Testinium successfully") if file_response.nil?

puts "Testinium project is updating..."
update_status = update_project(project, file_response, access_token)
raise("Cannot update project successfully") if update_status.nil?
puts 'Project updated successfully'

puts('Checking the plan status to start a new test plan...')
check_status($test_timeout, access_token)

puts('Starting a new test plan...')
execution_id = start(access_token)
raise("Cannot start Testinium plan successfully") if execution_id.nil?
puts("Plan started successfully. Execution Id: #{execution_id}")

puts('Checking the status of plan...')
status = check_status($test_timeout, access_token)
get_report(execution_id, access_token) if status