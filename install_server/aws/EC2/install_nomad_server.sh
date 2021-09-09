#!/bin/bash
readonly EC2_INSTANCE_METADATA_URL="http://169.254.169.254/latest/meta-data"
readonly EC2_INSTANCE_DYNAMIC_DATA_URL="http://169.254.169.254/latest/dynamic"

sudo yum -y install jq

function lookup_path_in_instance_metadata {
  local readonly path="$1"
  curl --silent --location "$EC2_INSTANCE_METADATA_URL/$path/"
}

function get_instance_availability_zone {
  lookup_path_in_instance_metadata "placement/availability-zone"
}

function get_instance_region {
  lookup_path_in_instance_dynamic_data "instance-identity/document" | jq -r ".region"
}

function get_instance_ip_address {
  lookup_path_in_instance_metadata "local-ipv4"
}

function get_instance_id {
  lookup_path_in_instance_metadata "instance-id"
}

instance_id=$(get_instance_id)
instance_region=$(get_instance_region)
availability_zone=$(get_instance_availability_zone)
instance_ip_address=$(get_instance_ip_address)

echo "Installing Nomad..."
NOMAD_VERSION=1.1.4
cd /tmp/
curl -sSL https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip -o nomad.zip
unzip nomad.zip
sudo install nomad /usr/bin/nomad
sudo mkdir -p /etc/nomad/config
sudo chmod -R a+w /etc/nomad

echo "Installing Consul..."
CONSUL_VERSION=1.10.2
curl -sSL https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip > /tmp/consul.zip
unzip /tmp/consul.zip
sudo install consul /usr/bin/consul
sudo mkdir -p /etc/consul
sudo chmod a+w /etc/consul
sudo mkdir -p /etc/consul/data
sudo chmod a+w /etc/consul/data
sudo mkdir -p /etc/consul/config
sudo chmod a+w /etc/consul/config

cat > /etc/nomad/config/server.hcl <<EOF
bind_addr = "0.0.0.0"
log_level = "DEBUG"
data_dir = "/etc/nomad"
name       = "$instance_id"
datacenter = "$instance_region"
region     = "$availability_zone"
server {
  enabled = true
  bootstrap_expect = 3
}
advertise {
  http = "$instance_ip_address"
  rpc = "$instance_ip_address"
  serf = "$instance_ip_address"
}
server_join {
	retry_join = ["provider=aws tag_key=server_type tag_value=new_nomad"]
}
EOF
sudo bash -c 'cat > /etc/systemd/system/nomad.service <<EOF
[Unit]
Description=Nomad
Requires=network-online.target
After=network-online.target

[Service]
Restart=on-failure
ExecStart=/usr/bin/nomad agent -config=/etc/nomad/config
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF'

sudo systemctl enable nomad
sudo systemctl start nomad
echo "Installing Dnsmasq..."
sudo yum -y install dnsmasq dnsmasq-utils
echo "Configuring Dnsmasq..."
sudo bash -c 'echo "server=/consul/127.0.0.1#8600" >> /etc/dnsmasq.d/consul'
sudo bash -c 'echo "listen-address=0.0.0.0" >> /etc/dnsmasq.d/consul'
sudo bash -c 'echo "bind-interfaces" >> /etc/dnsmasq.d/consul'
echo "Restarting dnsmasq..."
sudo systemctl enable dnsmasq
sudo service dnsmasq restart
cat > /etc/consul/config/client.json <<EOF
{
  "server": false,
  "ui": true,
  "data_dir": "/opt/consul/data",
  "client_addr": "0.0.0.0",
  "datacenter": "$instance_region",
  "advertise_addr": "$instance_ip_address",
  "retry_join": ["provider=aws tag_key=server_type tag_value=new_nomad"]
}
EOF
sudo bash -c 'cat > /etc/systemd/system/consul.service <<EOF
[Unit]
Description=Consul
Requires=network-online.target
After=network-online.target

[Service]
Restart=on-failure
ExecStart=/usr/bin/consul agent -config-dir=/etc/consul/config
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGTERM
RestartSec=30
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF'
sudo systemctl enable consul
sudo systemctl start consul