# http_benchmark

## Install
Requirements: Ruby, Bundler

```
git clone https://github.com/kovvik/http_benchmark.git
bundle install
```
## Usage
```
Usage: ./http_bench.rb (options)
    -c, --concurrency {concurrency}  Number of multiple requests to perform at a time. Default is one request at a time.
    -f, --params-file {filename}     The JSON encoded file with get and post parameters (required)
    -n, --requests {requests}        Number of requests to perform for the benchmarking session.
    -u, --url URL                    Base URL (required)
```
