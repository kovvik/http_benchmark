#!/usr/bin/env ruby

require 'typhoeus'
require 'pp'
require 'mixlib/cli'
require 'json'

class HttpBench
  include Mixlib::CLI
  
  option :url,
    short:        '-u URL',
    long:         '--url URL',
    description:  'Base URL',
    required:     true


  option :paramsfile,
    short:        '-f {filename}',
    long:         '--params-file {filename}',
    description:  'The JSON encoded file with get and post parameters',
    required:     true

  option :concurrency,
    short:        '-c {concurrency}',
    long:         '--concurrency {concurrency}',
    description:  'Number of multiple requests to perform at a time. Default is one request at a time.',
    default:      1

  option :requests,
    short:        '-n {requests}',
    long:         '--requests {requests}',
    description:         'Number of requests to perform for the benchmarking session.',
    default:      1


  def get_requests
    params = load_params
    requests = Array.new(@config[:requests].to_i)
    params_position = 0
    requests.map! do |request|
      request = Typhoeus::Request.new(
        "#{@config[:url]}#{params[params_position][:get]}",
        method: :post,
        followlocation: true,
        body: params[params_position]["post"]
      )
      params_position < params.length-1 ? params_position += 1 : params_position = 0
      request
    end 
    requests
  end

  def load_params
    obj = Array.new
    File.open(@config[:paramsfile], "r").each do |line|
      splitted = line.split("|")
      temp_obj = Hash.new
      temp_obj[:get] = splitted[0]
      temp_obj[:post] = JSON.parse splitted[1]
      obj.push temp_obj
    end
    obj
  end


  def print_results requests, test_total_time
    results = Hash.new
    results["Total time"] = Array.new
    results["Start transfer time"] = Array.new
    results["App connect time"] = Array.new
    results["Pretransfer time"] = Array.new
    results["Connect time"] = Array.new
    results["Name lookup time"] = Array.new
    results["Redirect time"] = Array.new
    results["Request size"] = Array.new
    response_codes = Hash.new(0)
    effective_urls = Hash.new(0)
    requests.each do |request|
      output = Array.new
      # Total time: the total time in seconds for the previous transfer, including name resolving, TCP connect etc.
      results["Total time"].push request.response.total_time.to_f
      # Start transfer time: the time, in seconds, it took from the start until the first byte is received by libcurl.
      results["Start transfer time"].push request.response.starttransfer_time.to_f
      # App connect time: the time, in seconds, it took from the start until the SSL/SSH connect/handshake to the remote host was completed.
      results["App connect time"].push request.response.appconnect_time.to_f
      # Pretransfer time: the time, in seconds, it took from the start until the file transfer is just about to begin.
      results["Pretransfer time"].push request.response.pretransfer_time.to_f
      # Connect time: the time, in seconds, it took from the start until the connect to the remote host (or proxy) was completed.
      results["Connect time"].push request.response.connect_time.to_f
      # Name lookup time: the time, in seconds, it took from the start until the name resolving was completed.
      results["Name lookup time"].push request.response.namelookup_time.to_f
      # redirect time: the time, in seconds, it took for all redirection steps include name lookup, connect, pretransfer and transfer before the
      # final transaction was started.
      results["Redirect time"].push request.response.redirect_time.to_f
      effective_urls[request.response.effective_url] += 1
      response_codes[request.response.response_code] += 1
      results["Request size"].push request.response.request_size
    end
    puts "Test time: #{test_total_time} s"
    puts "Requests:\t#{@config[:requests]}"
    puts "Requests / s:\t#{@config[:requests].to_f / test_total_time.to_f}"
    puts "Concurrency:\t#{@config[:concurrency]}"
    puts "Effective URLs count:\t#{effective_urls.count}"
    puts "Response codes"
    response_codes.each { |code, count| puts "\t#{code}:\t#{count}"}
    puts 
    results.each do |name, times|
      time_taken = times.inject(0, :+)
      time_avg = time_taken / @config[:requests].to_i
      time_min = times.min
      time_max = times.max
      puts "#{name}: #{time_taken}"
      puts "\tAvg:\t#{time_avg.to_f}"
      puts "\tMin:\t#{time_min.to_f}"
      puts "\tMax:\t#{time_max.to_f}"
      puts
    end  
#    count_times("Total time",results["Total time"]) 
  end

  def run
    hydra = Typhoeus::Hydra.new(max_concurrency: @config[:concurrency])
    queue = get_requests
    queue.map do |item|
      hydra.queue(item)
    end
    begining_time = Time.now
    hydra.run
    ending_time = Time.now
    test_total_time = ending_time - begining_time
    print_results queue, test_total_time
  end

end




if $0 == __FILE__
  cli = HttpBench.new
  cli.parse_options
  cli.run
end

