#!/usr/bin/env ruby

require 'typhoeus'
require 'pp'
require 'mixlib/cli'
require 'json'

#########
class ResultSet

  attr_accessor :name, :data, 

  def initialize name
    @name = name
  end
end

##########
class TimeResultSet < ResultSet
#  Unit = 's'
  def min
    @data.min.to_f
  end

  def max
    @data.max.to_f
  end

  def total
    @data.inject(0, :+)
  end

  def avg
    (self.total / @data.count).to_f
  end

  def initialize name
#    super name
    @data = []
  end

  def push element
    @data.push element
  end
end

############
class DataResultSet < TimeResultSet
  #Unit = 'b'
  def initialize name
  #  super
    @data = []
  end



end

###########
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
    description:         'Number of requests to perform for the benchmarking session. If not set, it will be equal to the lines in the params file.',
    default:      -1


  def get_requests
    params = load_params
    # If reqests not set in args then run the requests will be equal to the number of lines
    @config[:requests] = params.count if @config[:requests] == -1 
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
    results[:total_time] = TimeResultSet.new "Total time"
    results[:start_transfer_time] = TimeResultSet.new "Start transfer time"
    results[:app_connect_time] = TimeResultSet.new "App connect time"
    results[:pretransfer_time] = TimeResultSet.new "Pretransfer time"
    results[:connect_time] = TimeResultSet.new "Connect time"
    results[:name_lookup_time] = TimeResultSet.new "Name lookup time"
    results[:redirect_time] = TimeResultSet.new "Redirect time"
    results[:request_size] = DataResultSet.new "Request_size"
    response_codes = Hash.new(0)
    effective_urls = Hash.new(0)
    requests.each do |request|
      output = Array.new
      # Total time: the total time in seconds for the previous transfer, including name resolving, TCP connect etc.
      results[:total_time].push request.response.total_time.to_f
      # Start transfer time: the time, in seconds, it took from the start until the first byte is received by libcurl.
      results[:start_transfer_time].push request.response.starttransfer_time.to_f
      # App connect time: the time, in seconds, it took from the start until the SSL/SSH connect/handshake to the remote host was completed.
      results[:app_connect_time].push request.response.appconnect_time.to_f
      # Pretransfer time: the time, in seconds, it took from the start until the file transfer is just about to begin.
      results[:pretransfer_time].push request.response.pretransfer_time.to_f
      # Connect time: the time, in seconds, it took from the start until the connect to the remote host (or proxy) was completed.
      results[:connect_time].push request.response.connect_time.to_f
      # Name lookup time: the time, in seconds, it took from the start until the name resolving was completed.
      results[:name_lookup_time].push request.response.namelookup_time.to_f
      # redirect time: the time, in seconds, it took for all redirection steps include name lookup, connect, pretransfer and transfer before the
      # final transaction was started.
      results[:redirect_time].push request.response.redirect_time.to_f
      effective_urls[request.response.effective_url] += 1
      response_codes[request.response.response_code] += 1
      results[:request_size].push request.response.request_size
    end
    puts "Test time: #{test_total_time} s"
    puts "Requests:\t#{@config[:requests]}"
    puts "Requests / s:\t#{@config[:requests].to_f / test_total_time.to_f}"
    puts "Concurrency:\t#{@config[:concurrency]}"
    puts "Effective URLs count:\t#{effective_urls.count}"
    puts "Response codes"
    response_codes.each { |code, count| puts "\t#{code}:\t#{count}"}
    puts 

      puts "#{results[:total_time].name}: #{results[:total_time].total}"
      puts "\tAvg:\t#{results[:total_time].avg}"
      puts "\tMin:\t#{results[:total_time].min}"
      puts "\tMax:\t#{results[:total_time].max}"
      puts
    #results.each do |name, times|
    #  time_taken = times.inject(0, :+)
    #  time_avg = time_taken / @config[:requests].to_i
    #  time_min = times.min
    #  time_max = times.max
    #  puts "#{name}: #{time_taken}"
    #  puts "\tAvg:\t#{time_avg.to_f}"
    #  puts "\tMin:\t#{time_min.to_f}"
    #  puts "\tMax:\t#{time_max.to_f}"
    #  puts
    #end  
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

