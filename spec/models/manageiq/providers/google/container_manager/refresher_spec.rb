describe ManageIQ::Providers::Google::ContainerManager::Refresher do
  let(:ems) { FactoryBot.create(:ems_google_gke_with_vcr_authentication) }

  it "will perform a full refresh" do
    2.times do # Run twice to verify that a second run with existing data does not change anything
      ems.reload
      VCR.use_cassette(described_class.name.underscore) do
        EmsRefresh.refresh(ems)
      end
      ems.reload

      assert_table_counts
      assert_ems
      assert_specific_container_project
      assert_specific_container_node
      assert_specific_container_group
      assert_specific_container
    end
  end

  def assert_table_counts
    expect(ContainerProject.count).to eq(4)
    expect(ContainerNode.count).to    eq(3)
    expect(ContainerGroup.count).to   eq(11)
    expect(Container.count).to        eq(19)
  end

  def assert_ems
    expect(ems.container_projects.count).to eq(4)
    expect(ems.container_nodes.count).to    eq(3)
    expect(ems.container_groups.count).to   eq(11)
    expect(ems.containers.count).to         eq(19)
  end

  def assert_specific_container_project
    project = ems.container_projects.find_by(:ems_ref => "aeffa329-adfe-44ff-b915-c5ed0ad784b9")
    expect(project).to have_attributes(
      :ems_ref => "aeffa329-adfe-44ff-b915-c5ed0ad784b9",
      :name    => "default"
    )
  end

  def assert_specific_container_node
    node = ems.container_nodes.find_by(:ems_ref => "4078d36e-1ec7-44c2-bc92-335850657c73")
    expect(node).to have_attributes(
      :ems_ref                    => "4078d36e-1ec7-44c2-bc92-335850657c73",
      :name                       => "gke-my-first-cluster-1-default-pool-d2b25767-llng",
      :identity_machine           => "2a4e7c198c3ff3726f5fe30b3195247f",
      :identity_system            => "2a4e7c19-8c3f-f372-6f5f-e30b3195247f",
      :type                       => "ManageIQ::Providers::Google::ContainerManager::ContainerNode",
      :kubernetes_kubelet_version => "v1.20.8-gke.900",
      :kubernetes_proxy_version   => "v1.20.8-gke.900",
      :container_runtime_version  => "containerd://1.4.3"
    )
  end

  def assert_specific_container_group
    pod = ems.container_groups.find_by(:ems_ref => "c360915d-4960-4086-97b7-28483134ce0d")
    expect(pod).to have_attributes(
      :ems_ref           => "c360915d-4960-4086-97b7-28483134ce0d",
      :name              => "kube-dns-56646bfd69-mz5dv",
      :restart_policy    => "Always",
      :dns_policy        => "Default",
      :container_node    => ems.container_nodes.find_by(:ems_ref => "4078d36e-1ec7-44c2-bc92-335850657c73"),
      :ipaddress         => "10.104.0.3",
      :type              => "ManageIQ::Providers::Google::ContainerManager::ContainerGroup",
      :container_project => ems.container_projects.find_by(:ems_ref => "6327f30a-bb10-44e1-82c0-9fcb57d8036d"),
      :phase             => "Running",
    )
  end

  def assert_specific_container
    container = ems.containers.find_by(:ems_ref => "c360915d-4960-4086-97b7-28483134ce0d_kubedns_gke.gcr.io/k8s-dns-kube-dns-amd64:1.17.3-gke.0")
    expect(container).to have_attributes(
      :ems_ref              => "c360915d-4960-4086-97b7-28483134ce0d_kubedns_gke.gcr.io/k8s-dns-kube-dns-amd64:1.17.3-gke.0",
      :name                 => "kubedns",
      :restart_count        => 0,
      :state                => "running",
      :backing_ref          => "containerd://398a8c2949c324840ec2d09fb9de1d5b049d881f66425df13b67598402aca59b",
      :type                 => "ManageIQ::Providers::Google::ContainerManager::Container",
      :container_image      => ems.container_images.find_by(:image_ref => "docker://gke.gcr.io/k8s-dns-kube-dns-amd64@sha256:f5210cf47c3d04c72835499fdade27f176ebedb7316172c560251d3dbd5180fb"),
      :request_memory_bytes => 73400320,
      :limit_memory_bytes   => 220200960,
      :image                => "gke.gcr.io/k8s-dns-kube-dns-amd64:1.17.3-gke.0",
      :image_pull_policy    => "IfNotPresent",
      :container_group      => ems.container_groups.find_by(:ems_ref => "c360915d-4960-4086-97b7-28483134ce0d")
    )
  end
end
