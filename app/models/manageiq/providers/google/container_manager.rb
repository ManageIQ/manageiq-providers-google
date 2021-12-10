ManageIQ::Providers::Kubernetes::ContainerManager.include(ActsAsStiLeafClass)

class ManageIQ::Providers::Google::ContainerManager < ManageIQ::Providers::Kubernetes::ContainerManager
  require_nested :Container
  require_nested :ContainerGroup
  require_nested :ContainerNode
  require_nested :EventCatcher
  require_nested :EventParser
  require_nested :Refresher
  require_nested :RefreshWorker

  supports :create

  def self.ems_type
    @ems_type ||= "gke".freeze
  end

  def self.description
    @description ||= "Google Kubernetes Engine".freeze
  end

  def self.display_name(number = 1)
    n_('Container Provider (Google)', 'Container Providers (Google)', number)
  end

  def self.default_port
    443
  end

  def self.kubernetes_auth_options(options)
    {
      :bearer_token => google_access_token(options[:bearer])
    }
  end

  def self.google_access_token(json_key)
    require "googleauth"

    json_key_io = StringIO.new(json_key)
    scope       = ["https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/userinfo.email"]

    credentials = ::Google::Auth::ServiceAccountCredentials.make_creds(:json_key_io => json_key_io, :scope => scope)
    credentials.apply({})

    credentials.access_token
  end

  def self.params_for_create
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
                :component    => "select",
                :id           => "endpoints.default.security_protocol",
                :name         => "endpoints.default.security_protocol",
                :label        => _("Security Protocol"),
                :isRequired   => true,
                :validate     => [{:type => "required"}],
                :initialValue => 'ssl-with-validation',
                :options      => [
                  {
                    :label => _("SSL"),
                    :value => "ssl-with-validation"
                  },
                  {
                    :label => _("SSL trusting custom CA"),
                    :value => "ssl-with-validation-custom-ca"
                  },
                  {
                    :label => _("SSL without validation"),
                    :value => "ssl-without-validation",
                  },
                ]
              },
              {
                :component  => "text-field",
                :id         => "endpoints.default.hostname",
                :name       => "endpoints.default.hostname",
                :label      => _("Hostname (or IPv4 or IPv6 address)"),
                :isRequired => true,
                :validate   => [{:type => "required"}],
              },
              {
                :component    => "text-field",
                :id           => "endpoints.default.port",
                :name         => "endpoints.default.port",
                :label        => _("API Port"),
                :type         => "number",
                :initialValue => default_port,
                :isRequired   => true,
                :validate     => [{:type => "required"}],
              },
              {
                :component  => "textarea",
                :id         => "endpoints.default.certificate_authority",
                :name       => "endpoints.default.certificate_authority",
                :label      => _("Trusted CA Certificates"),
                :rows       => 10,
                :isRequired => true,
                :validate   => [{:type => "required"}],
                :condition  => {
                  :when => 'endpoints.default.security_protocol',
                  :is   => 'ssl-with-validation-custom-ca',
                },
              },
              {
                :component      => "password-field",
                :componentClass => 'textarea',
                :rows           => 10,
                :id             => "authentications.bearer.auth_key",
                :name           => "authentications.bearer.auth_key",
                :label          => _("Service Account JSON"),
                :isRequired     => true,
                :helperText     => _('Copy and paste the contents of your Service Account JSON file above.'),
                :validate       => [{:type => "required"}]
              },
            ],
          ],
        },
      ],
    }
  end
end
