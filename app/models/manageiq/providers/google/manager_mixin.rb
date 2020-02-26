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

  def edit_with_params(params)
    default_endpoint = params.delete("endpoints")&.dig("default") || {}
    default_authentication = params.delete("authentications")&.dig("default") || {}

    tap do |ems|
      ems.default_authentication.assign_attributes(default_authentication)
      ems.default_endpoint.assign_attributes(default_endpoint)

      ems.assign_attributes(params)

      ems.save!
    end
  end

  module ClassMethods
    def params_for_create
      @params_for_create ||= {
        :fields => [
          {
            :component  => "text-field",
            :name       => "project",
            :label      => _("Project ID"),
            :isRequired => true,
            :validate   => [{:type => "required-validator"}]
          },
          {
            :component => 'sub-form',
            :name      => 'endpoints',
            :title     => _("Endpoint"),
            :fields    => [
              :component              => 'validate-provider-credentials',
              :name                   => 'authentications.default.valid',
              :validationDependencies => %w[type project zone_name],
              :fields                 => [
                {
                  :component      => "password-field",
                  :componentClass => 'textarea',
                  :rows           => 10,
                  :name           => "authentications.default.auth_key",
                  :label          => _("Service Account JSON"),
                  :isRequired     => true,
                  :helperText     => _('Copy and paste the contents of your Service Account JSON file above.'),
                  :validate       => [{:type => "required-validator"}]
                },
              ],
            ],
          },
        ],
      }.freeze
    end

    def create_from_params(params)
      endpoints = params.delete("endpoints") || {'default' => {}} # Fall back to an empty default endpoint
      authentications = params.delete("authentications")

      params[:zone] = Zone.find_by(:name => params.delete("zone_name"))
      new(params).tap do |ems|
        endpoints.each do |authtype, endpoint|
          ems.endpoints.new(endpoint.merge(:role => authtype))
        end

        authentications.each do |authtype, authentication|
          ems.authentications << AuthToken.new(authentication.merge(:authtype => authtype))
        end

        ems.save!
      end
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
      auth_key = MiqPassword.try_decrypt(auth_key)
      auth_key ||= find(args["id"]).authentication_token('default')

      !!raw_connect(project, auth_key, {:service => "compute"}, http_proxy_uri, true)
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
