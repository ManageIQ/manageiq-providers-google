# Load KubernetesEventCatcherBase from the manageiq-providers-kubernetes gem.
# In production the gem is installed via the inline gemfile in the worker binary.
# In development/test the local checkout is used via the path gem in Gemfile.
k8s_base = if (spec = Gem.loaded_specs['manageiq-providers-kubernetes'])
             File.join(spec.gem_dir, 'lib/manageiq/providers/kubernetes/workers/event_catcher_base')
           else
             File.expand_path('../../../manageiq-providers-kubernetes/lib/manageiq/providers/kubernetes/workers/event_catcher_base', __dir__)
           end
require k8s_base

require 'googleauth'

class EventCatcher < KubernetesEventCatcherBase
  attr_reader :token_expiry

  private

  def auth_options
    json_key_io = StringIO.new(authentication['auth_key'])
    scope = %w[
      https://www.googleapis.com/auth/cloud-platform
      https://www.googleapis.com/auth/userinfo.email
    ]
    credentials = Google::Auth::ServiceAccountCredentials.make_creds(
      :json_key_io => json_key_io,
      :scope       => scope
    )
    credentials.apply({})
    @token_expiry = credentials.expires_at
    {:bearer_token => credentials.access_token}
  end

  def log_prefix
    'MIQ(ManageIQ::Providers::Google::ContainerManager::EventCatcher)'
  end
end
