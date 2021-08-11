ManageIQ::Providers::Kubernetes::ContainerManager.include(ActsAsStiLeafClass)

class ManageIQ::Providers::Google::ContainerManager < ManageIQ::Providers::Kubernetes::ContainerManager
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
    auth_options = {}
    auth_options[:bearer_token] = google_access_token(options[:bearer])
    auth_options
  end

  def self.google_access_token(google_json_key)
    require "googleauth"
    credentials = ::Google::Auth::ServiceAccountCredentials.make_creds(
      :json_key_io => StringIO.new(google_json_key),
      :scope       => [
        'https://www.googleapis.com/auth/cloud-platform',
        'https://www.googleapis.com/auth/userinfo.email'
      ]
    )

    credentials.apply({})

    credentials.access_token
  end
end
