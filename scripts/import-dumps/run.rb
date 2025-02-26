#!/usr/bin/env ruby
require 'bundler/inline'
require 'yaml'
require 'uri'
require 'net/http'
require 'json'
require 'tty-prompt'
require 'securerandom'
require 'date'

$stdout.sync = true
print "installing ruby dependencies..."
gemfile do
  source 'https://rubygems.org'
  gem 'ruby-odbc'
  gem 'typhoeus'
  gem 'tty-progressbar'
  gem 'logger'
end
puts "done"

require 'odbc'
require 'typhoeus'

ENV['LOG_SPARQL_ALL']='false'
ENV['MU_SPARQL_ENDPOINT']='http://database:8890/sparql'
ENV['JENA_HOME']='/opt/jena'

# using jena riot because we need streaming validation because of large files
puts "installing jena riot for turtle validation"
`apt-get update && apt-get install -y openjdk-17-jdk wget unzip`
`wget -qO- https://downloads.apache.org/jena/binaries/apache-jena-5.3.0.tar.gz | tar xz -C /opt && \
    mv /opt/apache-jena-5.3.0 $JENA_HOME && \
    ln -s $JENA_HOME/bin/riot /usr/local/bin/riot`


require 'odbc'
require 'tty-prompt'

DSN_NAME = "VirtuosoDSN"
ODBC_INI_PATH = "/etc/odbc.ini"
DRIVER_PATH = File.expand_path('./virtodbcu_r.so')
JOBS_GRAPH="http://mu.semte.ch/graphs/system/jobs"

class DateTime
  def sparql_escape
    '"' + self.xmlschema + '"^^xsd:dateTime'
  end
end

def dsn_exists?
  return false unless File.exist?(ODBC_INI_PATH)

  File.readlines(ODBC_INI_PATH).any? { |line| line.strip == "[#{DSN_NAME}]" }
end

# somewhat silly, but the only way I got a workign dsn set up
def write_dsn_config
  dsn_config = <<~DSN
    [#{DSN_NAME}]
    Driver=#{DRIVER_PATH}
    Address=triplestore:1111
  DSN

  unless dsn_exists?
    File.open(ODBC_INI_PATH, "a") do |file|
      file.puts "\n" + dsn_config
    end
  end
end

def get_db_connection
  write_dsn_config
  begin
    dbh = ODBC.connect(DSN_NAME, 'dba', 'dba')
    dbh.autocommit = true
    puts "Connected successfully to DSN: #{DSN_NAME}"
    return dbh
  rescue ODBC::Error => e
    puts "ODBC Error: #{e.message}"
    return nil
  end
end

def get_latest_dump_file(sync_base_url, subject)
  sync_base_url = sync_base_url.end_with?("/") ? sync_base_url : "#{sync_base_url}/"
  sync_dataset_endpoint = "#{sync_base_url}datasets"
  begin
    url_to_call = "#{sync_dataset_endpoint}?filter[subject]=#{subject}&filter[:has-no:next-version]=yes"
    puts "Retrieving latest dataset from #{url_to_call}"

    response_dataset = Typhoeus.get(url_to_call, headers: { 'Accept' => 'application/vnd.api+json' })
    dataset = JSON.parse(response_dataset.body)

    if dataset['data'].any?
      distribution_metadata = dataset['data'][0]['attributes']
      distribution_related_link = dataset['data'][0]['relationships']['distributions']['links']['related']
      distribution_uri = "#{sync_base_url}#{distribution_related_link}"

      puts "Retrieving distribution from #{distribution_uri}"
      result_distribution = Typhoeus.get("#{distribution_uri}?include=subject", headers: { 'Accept' => 'application/vnd.api+json' })
      distribution = JSON.parse(result_distribution.body)
      return [distribution['data'][0].dig('relationships','subject','data'), distribution_metadata]
    else
      raise 'No dataset was found at the producing endpoint.'
    end
  rescue => e
    puts "Unable to retrieve dataset from #{sync_dataset_endpoint}"
    raise e
  end
end


prompt = TTY::Prompt.new
prompt.say ""
sync_base_url = prompt.ask('Enter the SYNC_BASE_URL:', default: "https://lokaalbeslist-harvester-0.s.redhost.be/")
default_subject = "http://data.lblod.info/datasets/delta-producer/dumps/lblod-harvester/BesluitenCacheGraphDump"
sync_dataset_subject = prompt.ask("Enter the dataset URI:", default: default_subject)
ingest_graph = prompt.ask("Enter the INGEST_GRAPH", default: "http://mu.semte.ch/graphs/public")
job_creator_uri = prompt.ask("Enter the JOB_CREATOR_URI", default: "http://data.lblod.info/services/id/besluiten-consumer")

distribution, distribution_metadata = get_latest_dump_file(sync_base_url, sync_dataset_subject)

distribution_url = "#{sync_base_url}files/#{distribution["id"]}/download"
start=DateTime.now
progressbar = nil
filename="dataset-#{SecureRandom.uuid}.ttl"
tmp_file_path = "/project/tmp-#{filename}"
prompt.say "Downloading file from #{distribution_url} to #{tmp_file_path}"
progressbar = TTY::ProgressBar.new("Downloading: :byte_rate/s :current_byte :elapsed")

file = File.open(tmp_file_path, 'wb')
request = Typhoeus::Request.new(distribution_url, followlocation: true, accept_encoding: 'deflate,gzip')
request.on_headers do |response|
  if response.code != 200
    raise "Failed to download file, response code #{response.code}"
  end
  puts response.headers["Content-Encoding"]
end
request.on_body do |chunk|
  file.write(chunk)
  progressbar.advance(chunk.bytesize) if progressbar
end
request.on_complete do
  file.close
  progressbar.finish
  prompt.say "Validating file #{tmp_file_path}"
  system("/usr/local/bin/riot --validate #{tmp_file_path}")
  unless $?.success?
    raise "Downloaded turtle file is not a valid turtle file"
  end
  File.rename(tmp_file_path,"/project/data/db/toLoad/#{filename}")
  prompt.say("Moved validated ttl to data/db/toLoad/#{filename}")
  load_file = prompt.yes?("Load file via virtuoso odbc")
  if load_file
    begin
      connection = get_db_connection
      progressbar = TTY::ProgressBar.new("Loading file [:bar] :elapsed")
      connection.do("ld_dir('toLoad', '#{filename}', '#{ingest_graph}' )")
      connection.do("rdf_loader_run()")
      connection.do("checkpoint()")
      progressbar.finish
      prompt.say("File successfully loaded into #{ingest_graph}.")
    rescue => e
      puts e.trace
      exit(1)
    end
  end
  end_time = DateTime.now
  prompt.say("Adding initial starting point for delta sync")
  begin
    job_operation = prompt.ask("What is the job operation you want to use in the metadata", default: "http://redpencil.data.gift/id/jobs/concept/JobOperation/deltas/consumer/initialSync/besluiten")
    container_id = SecureRandom.uuid
    container_uri = "http://data.lblod.info/id/dataContainers/#{container_id}";
    job_id = SecureRandom.uuid
    job_uri = "http://redpencil.data.gift/id/job/#{job_id}"
    task_id = SecureRandom.uuid
    task_uri = "http://redpencil.data.gift/id/task/#{task_id}"
    task_1_id = SecureRandom.uuid
    task_1_uri = "http://redpencil.data.gift/id/task/#{task_1_id}"
    metadata_query = <<~QUERY
                    SPARQL
  PREFIX mu: <http://mu.semte.ch/vocabularies/core/>
  PREFIX task: <http://redpencil.data.gift/vocabularies/tasks/>
  PREFIX dct: <http://purl.org/dc/terms/>
  PREFIX prov: <http://www.w3.org/ns/prov#>
  PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>
  PREFIX oslc: <http://open-services.net/ns/core#>
  PREFIX cogs: <http://vocab.deri.ie/cogs#>
  PREFIX adms: <http://www.w3.org/ns/adms#>
  PREFIX nfo: <http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#>
 INSERT DATA {
     GRAPH <JOBS_GRAPH> {
       <#{job_uri}> a cogs:Job;
                    mu:uuid "#{job_id}";
                    dct:creator <#{job_creator_uri}>;
                dct:created #{start.sparql_escape};
                dct:modified #{end_time.sparql_escape};
                adms:status <http://redpencil.data.gift/id/concept/JobStatus/success>;
          task:operation <#{job_operation}>.
       <#{task_uri}> a task:Task;
                mu:uuid "#{task_id}";
                dct:isPartOf <#{job_uri}>;
                dct:created #{start.sparql_escape};
                dct:modified #{end_time.sparql_escape};
                adms:status <http://redpencil.data.gift/id/concept/JobStatus/success>;
                task:index 0;
                task:operation <http://redpencil.data.gift/id/jobs/concept/TaskOperation/deltas/consumer/initialSyncing>.
       <#{task_1_uri}> a task:Task;
                mu:uuid "#{task_1_id}";
                dct:isPartOf <#{job_uri}>;
                dct:created #{start.sparql_escape};
                dct:modified #{end_time.sparql_escape};
                adms:status <http://redpencil.data.gift/id/concept/JobStatus/success>;
                task:index 1;
                task:operation <http://redpencil.data.gift/id/jobs/concept/TaskOperation/deltas/consumer/deltaSyncing>.
      <#{container_uri}> a nfo:DataContainer;
                          dct:subject <http://redpencil.data.gift/id/concept/DeltaSync/DeltafileInfo>;
                          mu:uuid "#{container_id}";
                          ext:hasDeltafileTimestamp "#{distribution_metadata["created"]}"^^xsd:dateTime.
                          ext:hasDeltafileId "#{distribution["id"]}".
                          ext:hasDeltafileName "#{filename}".
      <#{task_1_uri}> task:resultsContainer <#{container_uri}>.
      <#{task_1_uri}> task:inputContainer  <#{container_uri}>.
     }
    }
                    }
QUERY
    connection = get_db_connection
    prompt.say("Executing query: \n #{metadata_query}")
    connection.do(metadata_query)
  end
end

request.run
