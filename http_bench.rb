#!/usr/bin/env ruby

require 'typhoeus'
require 'pp'
require 'mixlib/cli'
require 'json'

#########
class ResultSet
  Unit=''
  attr_reader :name, :data

  def initialize name
    @name = name
    @data = Hash.new
  end
  
  def push(key, value)
    @data[key] = value
  end

  def print_formatted
    @data.each do |key, value|
      puts "#{key}:\t#{value}"
    end
    puts
  end
  
  def print_csv
  end
end

##########
class TimeResultSet < ResultSet
  Unit = 's'
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
    super
    @data = []
  end

  def push element
    @data.push element
  end

  def print_formatted
    puts "#{@name}:\t#{self.total} #{Unit}"
    puts "\tAvg:\t#{self.avg} #{Unit}"
    puts "\tMin:\t#{self.min} #{Unit}"
    puts "\tMax:\t#{self.max} #{Unit}"
    puts
  end

end

############
class DataResultSet < TimeResultSet
  Unit = 'b'
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


  def calculate_results requests, begining_time, ending_time  
    # Calculate results from requests
    requests.each do |request|
      output = Array.new
      # total_time: the total time in seconds for the previous transfer, including name resolving, TCP connect etc.
      @results[:total_time].push request.response.total_time.to_f
      # starttransfer_time: the time, in seconds, it took from the start until the first byte is received by libcurl.
      @results[:starttransfer_time].push request.response.starttransfer_time.to_f
      # appconnect_time: the time, in seconds, it took from the start until the SSL/SSH connect/handshake to the remote host was completed.
      @results[:appconnect_time].push request.response.appconnect_time.to_f
      # pretransfer_time: the time, in seconds, it took from the start until the file transfer is just about to begin.
      @results[:pretransfer_time].push request.response.pretransfer_time.to_f
      # connect_time: the time, in seconds, it took from the start until the connect to the remote host (or proxy) was completed.
      @results[:connect_time].push request.response.connect_time.to_f
      # namelookup time: the time, in seconds, it took from the start until the name resolving was completed.
      @results[:namelookup_time].push request.response.namelookup_time.to_f
      # redirect_time: the time, in seconds, it took for all redirection steps include name lookup, connect, pretransfer and transfer before the
      # final transaction was started.
      @results[:redirect_time].push request.response.redirect_time.to_f
      # effective_urls: Uniq URL requests
      @results[:effective_urls][request.response.effective_url] += 1
      # response_codes: HTTP response codes
      @results[:response_codes][request.response.response_code] += 1
      # request_size: Size of the HTTP response, includes header and body
      @results[:request_size].push request.response.request_size
    end
    # Common results
    test_total_time = ending_time - begining_time
    @results[:common].push("Test time", test_total_time)
    @results[:common].push("Requests", @config[:requests])
    @results[:common].push("Requests / s", @config[:requests].to_f / test_total_time.to_f)
    @results[:common].push("Concurrency", @config[:concurrency])
  end

  def print_formatted
    @results[:common].print_formatted
    puts "Effective URLs count:\t#{@results[:effective_urls].count}"
    puts "Response codes"
    @results[:response_codes].each { |code, count| puts "\t#{code}:\t#{count}"}
    puts 
    @results[:total_time].print_formatted
    @results[:starttransfer_time].print_formatted
    @results[:appconnect_time].print_formatted
    @results[:pretransfer_time].print_formatted
    @results[:connect_time].print_formatted
    @results[:namelookup_time].print_formatted
    @results[:redirect_time].print_formatted
    @results[:request_size].print_formatted
  end 

  def initialize
    super
    # results: hash to store the results
    @results = Hash.new
    @results[:total_time] = TimeResultSet.new "Total time"
    @results[:starttransfer_time] = TimeResultSet.new "Start transfer time"
    @results[:appconnect_time] = TimeResultSet.new "App connect time"
    @results[:pretransfer_time] = TimeResultSet.new "Pretransfer time"
    @results[:connect_time] = TimeResultSet.new "Connect time"
    @results[:namelookup_time] = TimeResultSet.new "Name lookup time"
    @results[:redirect_time] = TimeResultSet.new "Redirect time"
    @results[:request_size] = DataResultSet.new "Request_size"
    @results[:response_codes] = Hash.new(0)
    @results[:effective_urls] = Hash.new(0) 
    @results[:common] = ResultSet.new "Overview"
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
    calculate_results queue, begining_time, ending_time
    print_formatted
  end

end




if $0 == __FILE__
  cli = HttpBench.new
  cli.parse_options
  cli.run
end

