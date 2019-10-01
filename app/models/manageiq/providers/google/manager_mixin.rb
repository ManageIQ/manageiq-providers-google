module ManageIQ::Providers::Google::ManagerMixin
  extend ActiveSupport::Concern

  def verify_credentials(auth_type = nil, options = {})
    options[:auth_type] = auth_type
    connect(options, true)

    true
  end

  def connect(options = {}, validate = false)
    raise MiqException::MiqHostError, "No credentials defined" if missing_credentials?(options[:auth_type])

    auth_token = authentication_token(options[:auth_type])
    self.class.raw_connect(project, auth_token, options, options[:proxy_uri] || http_proxy_uri, validate)
  end

  def gce
    @gce ||= connect(:service => "compute")
  end

  module ClassMethods
    def params_for_create
      @params_for_create ||= {
        :title  => "Configure #{description}",
        :fields => [
          {
            :component  => "text-field",
            :name       => "endpoints.default.google_project",
            :label      => "Project",
            :isRequired => true,
            :validate   => [{:type => "required-validator"}]
          },
          {
            :component  => "text-field",
            :name       => "endpoints.default.google_json_key",
            :label      => "JSON Key",
            :type       => "password",
            :isRequired => true,
            :validate   => [{:type => "required-validator"}]
          }
        ]
      }.freeze
    end

    # Verify Credentials
    # args:
    # {
    #   "endpoints" => {
    #     "default" => {
    #       "google_project"  => "",
    #       "google_json_key" => "",
    #     }
    #   }
    # }
    def verify_credentials(args)
      default_endpoint = args.dig("endpoints", "default")

      google_project, google_json_key = default_endpoint&.values_at("google_project", "google_json_key")

      !!raw_connect(google_project, google_json_key, {:service => "compute"}, http_proxy_uri, true)
    end

    def raw_connect(google_project, google_json_key, options, proxy_uri = nil, validate = false)
      require 'fog/google'

      config = {
        :provider               => "Google",
        :google_project         => google_project,
        :google_json_key_string => ManageIQ::Password.try_decrypt(google_json_key),
        :app_name               => Vmdb::Appliance.PRODUCT_NAME,
        :app_version            => Vmdb::Appliance.VERSION,
        :google_client_options  => { :proxy_url => proxy_uri },
      }

      begin
        case options[:service]
          # specify Compute as the default
        when 'compute', nil
          connection = ::Fog::Compute.new(config)
        when 'pubsub'
          connection = ::Fog::Google::Pubsub.new(config.except(:provider))
        when 'monitoring'
          connection = ::Fog::Google::Monitoring.new(config.except(:provider))
        else
          raise ArgumentError, "Unknown service: #{options[:service]}"
        end

        # Not all errors will cause Fog to raise an exception,
        # for example an error in the google_project id will
        # succeed to connect but the first API call will raise
        # an exception, so make a simple call to the API to
        # confirm everything is working
        connection.regions.all if validate
      rescue => err
        raise MiqException::MiqInvalidCredentialsError, err.message
      end

      connection
    end
  end
end
