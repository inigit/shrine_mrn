require "net/http"
require 'net/http/post/multipart'

class Shrine
  module Storage
    class Mrn
      attr_reader :prefix, :host, :upload_host

      def initialize(host:, upload_host:, prefix: nil, **options)
        @prefix = prefix
        @host = host
        @upload_host = upload_host
        @username = options[:username]
        @secret_key = options[:secret_key]
        @ip_address = options[:ip_address]

        raise "upload_host is required" if @upload_host.blank?
        raise "host is required" if @host.blank?

        raise "Username missing" if @username.blank?
        raise "Secret key missing" if @secret_key.blank?
        raise "IP address missing" if @ip_address.blank?
      end

      def upload(io, id, shrine_metadata: {}, **_options)
        unix_timestamp = Time.now.to_i.to_s
        hashed_secret_key = Digest::MD5.hexdigest(@secret_key)
        @token = Digest::MD5.hexdigest(unix_timestamp + @username + hashed_secret_key + @ip_address)

        uri = URI.parse(@upload_host)
        path = @prefix ? "/#{@prefix}/" : ""
        pretty_path = "#{path}#{Pathname(id).dirname.to_s}/"
        if io.is_a?(UploadedFile)
          file = io.download
        elsif io.is_a?(Tempfile)
          file = io
        else
          file = io.tempfile
        end

        Rails.logger.info("[File]: #{file.inspect}")

        req = Net::HTTP::Post::Multipart.new(uri.path, {
          "filename" => UploadIO.new(file, "image/*", id),
          "path" => pretty_path,
          "username" => @username,
          "token" => @token
        })

        if uri.scheme == "https"
          OpenSSL::SSL.const_set(:VERIFY_PEER, OpenSSL::SSL::VERIFY_NONE)
          http = Net::HTTP.start(uri.host, uri.port, :use_ssl => true)
        else
          http = Net::HTTP.start(uri.host, uri.port)
        end

        Rails.logger.info("[Uploading from]: #{@ip_address}")

        response = http.request(req)

        Rails.logger.info("[Upload response code]: #{response.code}")
        Rails.logger.info("[Upload response body]: #{response.body}")

        response.error! if (400..599).cover?(response.code.to_i)
        response
      end

      # def download(id)
      #   puts "*********Downloading...**********"
      #   open(id)
      # end

      def open(id)
        # puts "*********Opening...**********"
        uri = URI.parse("#{@host}/#{object_name(id)}")
        # puts "*********URI: #{uri}**********"
        response = Net::HTTP.get_response(uri)
        # puts "*********RESPONSE: #{response.inspect}**********"
        io = StringIO.new(response.body)
        # io = StringIO.new(Base64.decode64(response))
        io
        # image = StringIO.new(Base64.decode64(response.body))
        # puts "*********IMAGE: #{image.inspect}**********"
        # image
        # open(uri) {|f|
        #   puts "*********F: #{f}**********"
        #   File.open(object_name(id),"wb") do |file|
        #     puts "*********FILE: #{file}**********"
        #     file.puts f.read
        #   end
        # }
        # uri
      end

      def exists?(id)
        uri = URI.parse("#{@host}/#{object_name(id)}")
        response = Net::HTTP.get_response(uri)
        (200..299).cover?(response.code.to_i)
      end

      def url(id, **options)
        url = "#{@host}/#{object_name(id)}"
        url
      end

      def delete(id)
        true
      end

      def object_name(id)
        @prefix ? "#{@prefix}/#{id}" : id
      end

      private

      # def request(method, url)
      #   response = nil
      #   uri = URI(url)
      #
      #   Net::HTTP.start(uri.host, uri.port) do |http|
      #     request = Net::HTTP.const_get(method.to_s.capitalize).new(uri.request_uri)
      #     yield request if block_given?
      #     response = http.request(request)
      #   end
      #
      #   response
      # end
    end
  end
end
