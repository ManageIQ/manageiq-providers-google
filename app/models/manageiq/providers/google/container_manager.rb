ManageIQ::Providers::Kubernetes::ContainerManager.include(ActsAsStiLeafClass)

class ManageIQ::Providers::Google::ContainerManager < ManageIQ::Providers::Kubernetes::ContainerManager
  require_nested :Container
  require_nested :ContainerGroup
  require_nested :ContainerNode
  require_nested :EventCatcher
  require_nested :EventParser
  require_nested :Refresher
  require_nested :RefreshWorker

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

    client_email, private_key, project_id, quota_project_id =
      JSON.parse(json_key).values_at("client_email", "private_key", "project_id", "quota_project_id")

    private_key = OpenSSL::PKey::RSA.new(private_key)
    scope       = ["https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/userinfo.email"]

    credentials = ::Google::Auth::ServiceAccountCredentials.new(
      :token_credential_uri => Google::Auth::ServiceAccountCredentials::TOKEN_CRED_URI,
      :audience             => Google::Auth::ServiceAccountCredentials::TOKEN_CRED_URI,
      :scope                => scope,
      :issuer               => client_email,
      :project_id           => project_id,
      :quota_project_id     => quota_project_id,
      :signing_key          => private_key
    )

    credentials.apply({})

    credentials.access_token
  end
end
