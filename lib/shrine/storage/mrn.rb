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
        secret_key = options[:secret_key]
        ip_address = options[:ip_address]

        raise "Username missing" if @username.blank?
        raise "Secret key missing" if secret_key.blank?
        raise "IP address missing" if ip_address.blank?

        unix_timestamp = Time.now.to_i.to_s
        hashed_secret_key = Digest::MD5.hexdigest(secret_key)

        @token = Digest::MD5.hexdigest(unix_timestamp + @username + hashed_secret_key + ip_address)
      end

      def upload(io, id, shrine_metadata: {}, **_options)
        uri = URI.parse(@upload_host)

        path = @prefix ? "/#{@prefix}/" : ""
        pretty_path = "#{path}#{Pathname(id).dirname.to_s}/"

        if io.is_a?(UploadedFile)
          file = io.download
          # type = io.mime_type
        elsif io.is_a?(Tempfile)
          file = io
        else
          file = io.tempfile
          # type = io.content_type
        end

        req = Net::HTTP::Post::Multipart.new(uri.path, {
          "filename" => UploadIO.new(file, "image/*", id),
          "path" => pretty_path,
          "username" => @username,
          "token" => @token
        })

        http = Net::HTTP.start(uri.host, uri.port)
        response = http.request(req)

        puts "Upload Response Body: #{response.body}"

        response.error! if (400..599).cover?(response.code.to_i)
        response
      end

      def download(id)
        open(id)
      end

      def open(id)
        uri = URI.parse("#{@host}/#{object_name(id)}")
        response = Net::HTTP.get_response(uri)
        image = StringIO.new(Base64.decode64(response.body))
        image
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
