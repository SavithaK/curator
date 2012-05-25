require 'riak'
require 'yaml'

module Curator
  module Riak
    class DataStore
      def self.client
        return @client if @client
        yml_config = YAML.load(File.read(Curator.config.riak_config_file))[Curator.config.environment]
        @client = ::Riak::Client.new(yml_config)
      end

      def self.delete(bucket_name, key)
        bucket = _bucket(bucket_name)
        object = bucket.get(key)
        object.delete
      end

      def self.ping
        client.ping
      end

      def self.save(options)
        bucket = _bucket(options[:collection_name])
        object = ::Riak::RObject.new(bucket, options[:key])
        object.content_type = options.fetch(:content_type, "application/json")
        object.data = options[:value]
        options.fetch(:index, {}).each do |index_name, index_data|
          object.indexes["#{index_name}_bin"] << _normalized_index_data(index_data)
        end
        result = object.store
        result.key
      end

      def self.find_by_key(bucket_name, key)
        bucket = _bucket(bucket_name)
        begin
          object = bucket.get(key)
          { :key => object.key, :data => object.data } unless object.data.empty?
        rescue ::Riak::HTTPFailedRequest => failed_request
          raise failed_request unless failed_request.not_found?
        end
      end

      def self.find_by_attribute(bucket_name, index_name, query)
        return [] if query.nil?

        bucket = _bucket(bucket_name)
        begin
          keys = _find_key_by_index(bucket, index_name.to_s, query)
          keys.map { |key| find_by_key(bucket_name, key) }
        rescue ::Riak::HTTPFailedRequest => failed_request
          raise failed_request unless failed_request.not_found?
        end
      end

      def self._bucket(name)
        client.bucket(_bucket_name(name))
      end

      def self._bucket_name(name)
        bucket_prefix + ":" + name
      end

      def self.bucket_prefix
        "#{Curator.config.bucket_prefix}:#{Curator.config.environment}"
      end

      def self._find_key_by_index(bucket, index_name, query)
        bucket.get_index("#{index_name}_bin", query)
      end

      def self._normalized_index_data(index_data)
        if index_data.is_a?(Array)
          index_data.join(", ")
        else
          index_data
        end
      end
    end
  end
end
