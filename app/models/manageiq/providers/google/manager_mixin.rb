module ManageIQ::Providers::Google::ManagerMixin
  extend ActiveSupport::Concern

  def verify_credentials(auth_type = nil, options = {})
    options[:auth_type] = auth_type
    connect(options, true)

    capabilities["pubsub"] = verify_pubsub_credentials(options)

    save! if changed?

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

  private

  def verify_pubsub_credentials(options = {})
    !!connect(options.merge(:service => "pubsub")).subscriptions.all
  rescue Google::Apis::ClientError
    # If the Pub/Sub service isn't enabled on this project we cannot collect events
    false
  end

  module ClassMethods
    def params_for_create
      {
        :fields => [
          {
            :component  => "text-field",
            :id         => "project",
            :name       => "project",
            :label      => _("Project ID"),
            :isRequired => true,
            :validate   => [{:type => "required"}]
          },
          {
            :component => 'sub-form',
            :id        => 'endpoints-subform',
            :name      => 'endpoints-subform',
            :title     => _("Endpoint"),
            :fields    => [
              :component              => 'validate-provider-credentials',
              :id                     => 'authentications.default.valid',
              :name                   => 'authentications.default.valid',
              :skipSubmit             => true,
              :isRequired             => true,
              :validationDependencies => %w[type project zone_id],
              :fields                 => [
                {
                  :component      => "password-field",
                  :componentClass => 'textarea',
                  :rows           => 10,
                  :id             => "authentications.default.auth_key",
                  :name           => "authentications.default.auth_key",
                  :label          => _("Service Account JSON"),
                  :isRequired     => true,
                  :helperText     => _('Copy and paste the contents of your Service Account JSON file above.'),
                  :validate       => [{:type => "required"}]
                },
              ],
            ],
          },
        ],
      }.freeze
    end

    # Verify Credentials
    # args:
    # {
    #   "project"         => "",
    #   "authentications" => {
    #     "default" => {
    #       "auth_key" => "",
    #     }
    #   }
    # }
    def verify_credentials(args)
      project = args.dig("project")
      auth_key = args.dig("authentications", "default", "auth_key")
      auth_key = ManageIQ::Password.try_decrypt(auth_key)
      auth_key ||= find(args["id"]).authentication_token('default')

      !!raw_connect(project, auth_key, {:service => "compute"}, http_proxy_uri, true)
    end

    def raw_connect(google_project, google_json_key, options, proxy_uri = nil, validate = false)
      require "google/apis"
      ::Google::Apis.logger = $gce_log

      require 'fog/google'

      config = {
        :provider               => "Google",
        :google_project         => google_project,
        :google_json_key_string => ManageIQ::Password.try_decrypt(google_json_key),
        :app_name               => Vmdb::Appliance.PRODUCT_NAME,
        :app_version            => Vmdb::Appliance.VERSION,
        :google_client_options  => { :proxy_url => proxy_uri },
      }

      if proxy_uri
        require "faraday"
        Faraday.default_connection_options.proxy = proxy_uri
      end

      begin
        case options[:service]
          # specify Compute as the default
        when 'compute', nil
          connection = ::Fog::Compute.new(config)
        when 'pubsub'
          connection = ::Fog::Google::Pubsub.new(config.except(:provider))
        when 'monitoring'
          connection = ::Fog::Google::Monitoring.new(config.except(:provider))
        when 'sql'
          connection = ::Fog::Google::SQL.new(config.except(:provider))
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
