require 'open3'
require 'erb'
require 'logger'
require 'colorize'

require_relative 'tsb_config'

Config = TsbConfig.new

Log ||= Logger.new(STDOUT, level: Logger::INFO, formatter: proc {|severity, datetime, progname, msg|
  color = if severity == "DEBUG"
      :white
    elsif severity == "INFO"
      :green
    elsif severity == "WARN"
      :yellow
    elsif severity == "ERROR"
      :red
    else
      :light_blue
    end
  sprintf("%s: %s\n", datetime.strftime('%Y-%m-%d %H:%M:%S'), msg.colorize(color: color, mode: :bold))
})


task :default => :deploy_scenario

desc "Create host k3d cluster"
task :create_cluster do
  output, status = Open3.capture2("k3d cluster get tsb-cluster 2>/dev/null")
  if status.success?
    Log.warn "K3d host cluster already exists, skipping."
    next
  end

  Log.info("Creating host k3d cluster..")

  sh %Q[k3d cluster create tsb-cluster \
    --image rancher/k3s:v#{Config.params['k8s_version']}-k3s1 \
    --k3s-arg "--disable=traefik,servicelb@server:0" \
    --no-lb \
    --registry-create #{k3d_reg_create(Config.params['registry'])} \
    --wait]
end

def k3d_reg_create(registry)
  reg_host, reg_port = registry.split(":")
  "#{reg_host}:0.0.0.0:#{reg_port}"
end

desc "Deploy metallb to host cluster and configure the address pool"
task :deploy_metallb => :create_cluster do
  output, status = Open3.capture2("kubectl --context k3d-tsb-cluster get ns metallb-system 2>/dev/null")
  if status.success?
    Log.warn "Metallb seems to already be deployed, skipping."
    next
  end

  Log.info("Deploying metallb..")

  sh "kubectl --context k3d-tsb-cluster apply -f addons/metallb-0.12.1.yaml"

  ip_prefix = `docker network inspect k3d-tsb-cluster | jq -r ".[0].IPAM.Config[0].Gateway" | awk -F . '{ print $1 "." $2 }'`.strip

  template_file = File.read('addons/metallb-poolconfig.yaml')
  metallb_startip = "#{ip_prefix}.100.100"
  metallb_stopip = "#{ip_prefix}.100.200"
  template = ERB.new(template_file)
  Open3.capture2("kubectl --context k3d-tsb-cluster apply -f -", stdin_data: template.result(binding))
end

desc "Synchronize TSB container images to local registry"
task :sync_images => :create_cluster do
  Log.info("Sync'ing images..")

  sh "tctl install image-sync \
    --username #{Config.params['tsb_repo']['username']} \
    --apikey #{Config.params['tsb_repo']['apikey']} \
    --registry localhost:5000 \
    --accept-eula \
    --parallel"
end

Config.params['clusters'].each do |cluster_entry|
  cluster = cluster_entry['name']

  task "create_#{cluster}_vcluster" => :create_cluster do
    output, status = Open3.capture2("vcluster list | grep #{cluster}")
    if status.success?
      Log.warn "vcluster #{cluster} already exists, skipping."
      next
    end

    sh "vcluster create #{cluster} --kube-config-context-name #{cluster}"
    sh "kubectl config use-context k3d-tsb-cluster"
  end

  task "label_#{cluster}_locality" => "create_#{cluster}_vcluster" do
    if !( cluster_entry['region'] || cluster_entry['zone'] )
      Log.warn "no region or zone information, skipping node labeling for cluster #{cluster}"
      next
    end

    Log.info "Labeling nodes for #{cluster} with region and zone information.."
    context_name = cluster
    nodes = `kubectl --context #{context_name} get node -ojsonpath='{.items[].metadata.name}'`.split("\n")
    for node in nodes
      if cluster_entry['region']
        sh "kubectl --context #{context_name} label node #{node} topology.kubernetes.io/region=#{cluster_entry['region']} --overwrite=true"
      end
      if cluster_entry['zone']
        sh "kubectl --context #{context_name} label node #{node} topology.kubernetes.io/zone=#{cluster_entry['zone']} --overwrite=true"
      end
    end
  end

end

desc "Create vclusters"
task :create_vclusters => Config.cluster_names.map { |cluster| "create_#{cluster}_vcluster" }

desc "Label cluster nodes with region and zone information"
task :label_node_localities => Config.cluster_names.map { |cluster| "label_#{cluster}_locality" }

desc "Add and update TSB Helm Charts repository"
task :add_helm_repo do
  sh "helm repo add tetrate-tsb-helm 'https://charts.dl.tetrate.io/public/helm/charts/'"
  sh "helm repo update"
end

directory 'generated-artifacts'

file "generated-artifacts/mp-values.yaml" => ['generated-artifacts'] do
  template_file = File.read('templates/mp-values.yaml')

  registry = Config.params['registry']
  tsb_version = Config.params['tsb_version']
  admin_pwd = Config.params['admin_pwd']
  org = Config.params['org']

  template = ERB.new(template_file, trim_mode: '-')
  File.write("generated-artifacts/mp-values.yaml", template.result(binding))
end

desc "Install the TSB management plane"
multitask :install_mp => ["label_#{Config.mp_cluster['name']}_locality", :deploy_metallb, :sync_images, :add_helm_repo, 'generated-artifacts/mp-values.yaml'] do
  mp_context = Config.mp_cluster['name']

  output, status = Open3.capture2("kubectl --context #{mp_context} get -n tsb managementplane managementplane 2>/dev/null")
  if status.success?
    Log.warn "managementplane appears to be installed, skipping."
    next
  end

  sh "kubectl config use-context #{Config.mp_cluster['name']"

  patch_affinity

  sh "helm install mp tetrate-tsb-helm/managementplane \
    --namespace tsb --create-namespace \
    --values generated-artifacts/mp-values.yaml \
    --kube-context #{mp_context}"

  wait_until(:tsb_ready, "TSB installation is complete")

  expose_tsb_gui

  configure_tctl

  sh "kubectl config use-context k3d-tsb-cluster"
end

directory 'certs'

file 'certs/tsb-ca-cert.pem' => ["certs", :install_mp] do
  mp_context = Config.mp_cluster['name']
  sh "kubectl --context #{mp_context} get -n tsb secret tsb-certs -o jsonpath='{.data.ca\\.crt}' | base64 --decode > certs/tsb-ca-cert.pem"
end

file 'certs/es-ca-cert.pem' => ["certs/tsb-ca-cert.pem", :install_mp] do
  cd('certs') do
    cp 'tsb-ca-cert.pem', 'es-ca-cert.pem'
  end
end

file 'certs/xcp-ca-cert.pem' => ["certs/tsb-ca-cert.pem", :install_mp] do
  cd('certs') do
    cp 'tsb-ca-cert.pem', 'xcp-ca-cert.pem'
  end
end

Config.cp_clusters.each do |cluster_entry|
  cluster = cluster_entry['name']

  directory "generated-artifacts/#{cluster}"

  file "generated-artifacts/#{cluster}/service-account.jwk" => ["generated-artifacts/#{cluster}"] do
    cd("generated-artifacts/#{cluster}") do
      `tctl install cluster-service-account --cluster #{cluster} > service-account.jwk`
    end
  end

  file "generated-artifacts/#{cluster}/cluster.yaml" do
    template_file = File.read('templates/cluster.yaml')

    org = Config.params['org']
    is_mp = cluster_entry['is_mp']

    template = ERB.new(template_file, trim_mode: '-')
    File.write("generated-artifacts/#{cluster}/cluster.yaml", template.result(binding))
  end

  file "generated-artifacts/#{cluster}/cp-values.yaml" => ["generated-artifacts/#{cluster}/service-account.jwk", "certs/es-ca-cert.pem", "certs/tsb-ca-cert.pem", "certs/xcp-ca-cert.pem"] do
    template_file = File.read('templates/cp-values.yaml')
    mp_context = Config.mp_cluster['name']

    registry = Config.params['registry']
    tsb_version = Config.params['tsb_version']
    org = Config.params['org']

    tsb_api_endpoint = `kubectl --context #{mp_context} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}'`

    template = ERB.new(template_file, trim_mode: '-')
    File.write("generated-artifacts/#{cluster}/cp-values.yaml", template.result(binding))
  end

  task "install_cp_#{cluster}" => [:install_mp, "label_#{cluster}_locality", "generated-artifacts/#{cluster}/cp-values.yaml", "generated-artifacts/#{cluster}/cluster.yaml"] do
    cp_context = cluster

    output, status = Open3.capture2("kubectl --context #{cp_context} get -n istio-system controlplane controlplane 2>/dev/null")
    if status.success?
      Log.warn "Controlplane appears to be installed on cluster #{cluster}, skipping."
      next
    end

    if !cluster_entry['onboard_cluster']
      Log.info("Skipping onboarding of cluster #{cluster} ('onboard_cluster' is set to false)")
      next
    end

    Log.info("Installing control plane on #{cluster}..")

    sh "tctl apply -f generated-artifacts/#{cluster}/cluster.yaml"
    sleep 1

    sh "helm install cp tetrate-tsb-helm/controlplane \
      --namespace istio-system --create-namespace \
      --values generated-artifacts/#{cluster}/cp-values.yaml \
      --kube-context #{cp_context}"

    wait_for "tctl x status cluster #{cluster} | grep -i 'cluster onboarded'", "Cluster #{cluster} to be onboarded"
  end
end

desc "Install the TSB control planes"
task :install_controlplanes => Config.cp_clusters.map { |cluster| "install_cp_#{cluster['name']}" }

desc "Deploy and print TSB scenario"
task :deploy_scenario => :install_controlplanes do
  Log.info "Deploying scenario '#{Config.params['scenario']}'.."

  cd("scenarios/#{Config.params['scenario']}") do
    sh "./deploy.sh"
    sh "./info.sh"
  end
  public_ip = `curl -s ifconfig.me`
  puts "Management plane GUI can be accessed at: https://#{public_ip}:8443/"
  Log.info("..provisioning complete.")
end




def patch_affinity
  Thread.new {
    wait_for "kubectl get -n tsb managementplane managementplane -ojsonpath='{.spec.components.apiServer.kubeSpec.deployment.affinity.podAntiAffinity}' --allow-missing-template-keys=false 2>/dev/null", "ManagementPlane object to exist"

    for tsb_component in ['apiServer', 'collector', 'frontEnvoy', 'iamServer', 'mpc', 'ngac', 'oap', 'webUI']
      sh %Q[kubectl patch managementplane managementplane -n tsb --type=json \
        -p="[{'op': 'replace', 'path': '/spec/components/#{tsb_component}/kubeSpec/deployment/affinity/podAntiAffinity/requiredDuringSchedulingIgnoredDuringExecution/0/labelSelector/matchExpressions/0/key', 'value': 'platform.tsb.tetrate.io/demo-dummy'}]"]
    end
  }
end

def tsb_ready
  for tsb_deployment in ['tsb-operator-management-plane', 'ldap', 'web', 'otel-collector', 'xcp-operator-central', 'oap', 'tsb', 'iam', 'central', 'mpc', 'envoy']
    readyReplicas, status = Open3.capture2("kubectl get deploy -n tsb #{tsb_deployment} -ojsonpath='{.status.readyReplicas}' 2>/dev/null")
    return false unless status.success?
    replicas, status = Open3.capture2("kubectl get deploy -n tsb #{tsb_deployment} -ojsonpath='{.spec.replicas}' 2>/dev/null")
    return false unless status.success?
    return false unless readyReplicas == replicas
  end
  return true
end

def configure_tctl
  mp_context = Config.mp_cluster['name']
  tsb_api_endpoint = `kubectl --context #{mp_context} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}'`

  sh "tctl config clusters set tsb-cluster --tls-insecure --bridge-address #{tsb_api_endpoint}:8443"
  sh "tctl config users set tsb-admin --username admin --password #{Config.params['admin_pwd']} --org #{Config.params['org']}"
  sh "tctl config profiles set tsb-profile --cluster tsb-cluster --username tsb-admin"
  sh "tctl config profiles set-current tsb-profile"
end

def expose_tsb_gui
  cluster_ctx = Config.mp_cluster['name']

  kubectl_fullpath=`which kubectl`.strip

  `sudo tee /etc/systemd/system/tsb-gui.service << EOF
  [Unit]
  Description=TSB GUI Exposure

  [Service]
  ExecStart=#{kubectl_fullpath} --kubeconfig #{Dir.home}/.kube/config --context #{cluster_ctx} port-forward -n tsb service/envoy 8443:8443 --address 0.0.0.0
  Restart=always

  [Install]
  WantedBy=multi-user.target
  EOF`

  sh "sudo systemctl enable tsb-gui"
  sh "sudo systemctl start tsb-gui"
end

def wait_for(command, msg=nil)
  if msg
    Log.info "waiting for #{msg}.."
  end

  output, status = Open3.capture2(command)
  until status.success?
    sleep 1
    print "."
    output, status = Open3.capture2(command)
  end

  Log.info "..condition passed"
end

def wait_until(func, msg=nil)
  if msg
    Log.info "waiting until #{msg}.."
  end

  until method(func).call == true
    sleep 1
    print "."
  end

  if msg
    Log.info "..done: #{msg}"
  end
end
