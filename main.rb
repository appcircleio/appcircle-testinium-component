# frozen_string_literal: true

require 'net/http'
require 'json'
require 'date'

def env_has_key(key)
  !ENV[key].nil? && ENV[key] != '' ? ENV[key] : abort("Missing #{key}.")
end

MINUTES_IN_A_DAY = 1440
file = env_has_key('AC_TESTINIUM_APP_PATH')
$file = file
$file_name = File.basename(file)
$file_name_str = $file_name.to_s
$extension = File.extname($file_name)
$username = env_has_key('AC_TESTINIUM_USERNAME')
$password = env_has_key('AC_TESTINIUM_PASSWORD')
$plan_id = env_has_key('AC_TESTINIUM_PLAN_ID')
$project_id = env_has_key('AC_TESTINIUM_PROJECT_ID')
$ac_max_failure_percentage = (ENV['AC_TESTINIUM_MAX_FAIL_PERCENTAGE'] || 0).to_i
$company_id = env_has_key('AC_TESTINIUM_COMPANY_ID')
$env_file_path = env_has_key('AC_ENV_FILE_PATH')
$each_api_max_retry_count = env_has_key('AC_TESTINIUM_MAX_API_RETRY_COUNT').to_i
timeout = env_has_key('AC_TESTINIUM_TIMEOUT').to_i
date_now = DateTime.now
$end_time = date_now + Rational(timeout, MINUTES_IN_A_DAY)
$time_period = 30

def get_parsed_response(response)
  JSON.parse(response, symbolize_names: true)
rescue JSON::ParserError, TypeError => e
  puts "\nJSON was expected from the response of Testinium API, but the received value is: (#{response})\n. Error Message: #{e}\n"
  exit(1)
end

def calc_percent(numerator, denominator)
  if !(denominator >= 0)
    puts "Invalid numerator or denominator numbers"
    exit(1)
  elsif denominator == 0
    return 0
  else
    return numerator.to_f / denominator.to_f * 100.0
  end
end

def check_timeout()
  puts "Checking timeout..."
  now = DateTime.now

  if(now > $end_time)
    puts 'The component is terminating due to a timeout exceeded.
     If you want to allow more time, please increase the AC_TESTINIUM_TIMEOUT input value.'
    exit(1)
  end
end

def is_count_less_than_max_api_retry(count)
  return count < $each_api_max_retry_count
end

def login()
  puts "Logging in to Testinium..."
  uri = URI.parse('https://account.testinium.com/uaa/oauth/token')
  token = 'dGVzdGluaXVtU3VpdGVUcnVzdGVkQ2xpZW50OnRlc3Rpbml1bVN1aXRlU2VjcmV0S2V5'
  count = 1

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Signing in. Number of attempts: #{count}")

    req = Net::HTTP::Post.new(uri.request_uri,
                              { 'Content-Type' => 'application/json', 'Authorization' => "Basic #{token}" })
    req.set_form_data({ 'grant_type' => 'password', 'username' => $username, 'password' => $password })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('Successfully logged in...')
      return get_parsed_response(res.body)[:access_token]
    elsif (res.kind_of? Net::HTTPUnauthorized)
      puts(get_parsed_response(res.body)[:error_description])
      count += 1
    else
      puts("Error while signing in. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def check_status(access_token)
  count = 1
  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/plans/#{$plan_id}/checkIsRunning")

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    req = Net::HTTP::Get.new(uri.request_uri,
                             { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      if get_parsed_response(res.body)[:running]
        puts('Plan is still running...')
        sleep($time_period)
      else
        puts('Plan is not running...')
        return
      end
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while checking plan status. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def find_project(access_token)
  count = 1
  puts("Starting to find the project...")

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Finding project. Number of attempts: #{count}")

    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/projects/#{$project_id}")
    req = Net::HTTP::Get.new(uri.request_uri,
                             { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('Project was found successfully...')
      return get_parsed_response(res.body)
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while finding project. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def upload(access_token)
  count = 1

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Uploading #{$file_name} to Testinium... Number of attempts: #{count}")

    uri = URI.parse('https://testinium.io/Testinium.RestApi/api/file/upload')
    req = Net::HTTP::Post.new(uri.request_uri,
                              { 'Accept' => '*/*', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    form_data = [
      ['file', File.open($file)],
      %w[isSignRequired true]
    ]
    req.set_form(form_data, 'multipart/form-data')
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('File uploaded successfully...')
      return get_parsed_response(res.body)
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while uploading File. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def update_project(project, file_response, access_token)
  count = 1

  file_token = file_response[:file_token]
  ios_meta = file_response[:meta_data]
  raise('Upload error. File token not found.') if file_token.nil?

  puts("File uploaded successfully #{file_token}")

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

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Testinium project is updating... Number of attempts: #{count}")
    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/projects/#{project[:id]}")
    req = Net::HTTP::Put.new(uri.request_uri,
                             { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    req.body = JSON.dump(dict)
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('Project updated successfully...')
      return get_parsed_response(res.body)
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while updating Project. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def start(access_token)
  count = 1

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Starting a new test plan... Number of attempts: #{count}")
    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/plans/#{$plan_id}/run")
    req = Net::HTTP::Get.new(uri.request_uri,
                             { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('Plan started successfully...')
      return get_parsed_response(res.body)[:execution_id]
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while starting Plan. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def get_report(execution_id, access_token)
  count = 1

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Starting to get the report...Number of attempts: #{count}")
    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/executions/#{execution_id}")
    req = Net::HTTP::Get.new(uri.request_uri,
                             { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('Report received successfully...')

      data = get_parsed_response(res.body)
      result_summary = data[:result_summary]
      result_failure_summary = result_summary[:FAILURE] || 0
      result_error_summary = result_summary[:ERROR] || 0
      result_success_summary = result_summary[:SUCCESS] || 0
      puts "Test result summary: #{result_summary}"
      total_summary = result_failure_summary + result_error_summary + result_success_summary

      open("#{$env_file_path}", 'a') { |f|
        f.puts "AC_TESTINIUM_RESULT_FAILURE_SUMMARY=#{result_failure_summary}"
        f.puts "AC_TESTINIUM_RESULT_ERROR_SUMMARY=#{result_error_summary}"
        f.puts "AC_TESTINIUM_RESULT_SUCCESS_SUMMARY=#{result_success_summary}"
      }

      if $ac_max_failure_percentage > 0 && result_failure_summary > 0
        failure_percentage = calc_percent(result_failure_summary, total_summary)
        max_failure_percentage = calc_percent($ac_max_failure_percentage, 100)

        if max_failure_percentage <= failure_percentage || !result_summary[:ERROR].nil?
          puts "The number of failures in the plan exceeded the maximum rate. The process is being stopped. #{data[:test_result_status_counts]}"
          exit(1)
        else
          puts("Number of failures is below the maximum rate. Process continues. #{data[:test_result_status_counts]}")
        end
      else
        warn_message = "To calculate the failure rate, the following values must be greater than 0:" \
          "\nAC_TESTINIUM_MAX_FAIL_PERCENTAGE: #{$ac_max_failure_percentage}" \
          "\nTestinium Result Failure Summary: #{result_failure_summary}"
        puts warn_message
      end

      return
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while starting Plan. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

access_token = login()
check_status(access_token)
project = find_project(access_token)
file_response = upload(access_token)
update_project(project, file_response, access_token)
execution_id = start(access_token)
check_status(access_token)
get_report(execution_id, access_token)