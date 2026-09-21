require 'kubeclient'
require 'recursive-open-struct'
require 'googleauth'

require_relative '../../../workers/container_event_catcher/event_catcher'

RSpec.describe EventCatcher do
  let(:ems)            { {'id' => 1, 'uid_ems' => 'my-gke-cluster', 'type' => 'ManageIQ::Providers::Google::ContainerManager'} }
  let(:endpoint)       { {'hostname' => 'gke.example.com', 'port' => 443, 'security_protocol' => 'ssl-with-validation'} }
  let(:authentication) { {'authtype' => 'bearer', 'auth_key' => '{"type":"service_account"}'} }
  let(:settings)       { {'ems' => {'ems_gke' => {'blacklisted_event_names' => []}}} }
  let(:logger)         { instance_double('Logger', :info => nil, :warn => nil) }
  let(:catcher)        { described_class.new(ems, endpoint, authentication, settings, {}, logger) }

  describe '#log_prefix' do
    it 'returns the Google ContainerManager class name' do
      expect(catcher.send(:log_prefix)).to eq('MIQ(ManageIQ::Providers::Google::ContainerManager::EventCatcher)')
    end
  end

  describe '#auth_options' do
    let(:fake_token)      { 'ya29.fake-google-token' }
    let(:fake_expiry)     { Time.now.utc + 3600 }
    let(:fake_credentials) do
      instance_double('Google::Auth::ServiceAccountCredentials',
                      :access_token => fake_token,
                      :expires_at   => fake_expiry)
    end

    before do
      allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(fake_credentials)
      allow(fake_credentials).to receive(:apply)
    end

    it 'calls make_creds with the service account JSON and correct scopes' do
      expect(Google::Auth::ServiceAccountCredentials).to receive(:make_creds) do |opts|
        expect(opts[:json_key_io].read).to eq('{"type":"service_account"}')
        expect(opts[:scope]).to include('https://www.googleapis.com/auth/cloud-platform')
        expect(opts[:scope]).to include('https://www.googleapis.com/auth/userinfo.email')
        fake_credentials
      end

      catcher.send(:auth_options)
    end

    it 'returns a bearer_token hash' do
      expect(catcher.send(:auth_options)).to eq(:bearer_token => fake_token)
    end

    it 'sets @token_expiry to the expiry time from the credentials' do
      catcher.send(:auth_options)
      expect(catcher.send(:token_expiry)).to eq(fake_expiry)
    end
  end

  describe '#token_expiry' do
    it 'returns nil before auth_options is called' do
      expect(catcher.send(:token_expiry)).to be_nil
    end
  end

  describe '#build_client' do
    let(:fake_token)       { 'ya29.fresh-google-token' }
    let(:fake_expiry)      { Time.now.utc + 3600 }
    let(:fake_credentials) do
      instance_double('Google::Auth::ServiceAccountCredentials',
                      :access_token => fake_token,
                      :expires_at   => fake_expiry)
    end
    let(:client) { instance_double('Kubeclient::Client', :discover => nil) }

    before do
      allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(fake_credentials)
      allow(fake_credentials).to receive(:apply)
    end

    it 'passes auth_options result to Kubeclient::Client' do
      expect(Kubeclient::Client).to receive(:new) do |_uri, _version, opts|
        expect(opts[:auth_options]).to eq(:bearer_token => fake_token)
        client
      end

      catcher.send(:build_client)
    end

    it 'fetches a fresh token on every build_client call' do
      allow(Kubeclient::Client).to receive(:new).and_return(client)
      expect(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).twice.and_return(fake_credentials)

      catcher.send(:build_client)
      catcher.send(:build_client)
    end
  end
end
