readonly EC2_INSTANCE_METADATA_URL="http://169.254.169.254/latest/meta-data"
readonly EC2_INSTANCE_DYNAMIC_DATA_URL="http://169.254.169.254/latest/dynamic"

function get_instance_region {
  lookup_path_in_instance_dynamic_data "instance-identity/document" | jq -r ".region"
}

function lookup_path_in_instance_dynamic_data {
  local -r path="$1"
  curl --silent --show-error --location "$EC2_INSTANCE_DYNAMIC_DATA_URL/$path/"
}

datacenter=$(get_instance_region)

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
HOSTNAME=`hostname`
LOCAL_IP=`curl http://169.254.169.254/latest/meta-data/public-ipv4`
echo "Installing Dnsmasq..."
sudo yum -y install dnsmasq dnsmasq-utils
echo "Configuring Dnsmasq..."
sudo bash -c 'echo "server=/consul/127.0.0.1#8600" >> /etc/dnsmasq.d/consul'
sudo bash -c 'echo "listen-address=0.0.0.0" >> /etc/dnsmasq.d/consul'
sudo bash -c 'echo "bind-interfaces" >> /etc/dnsmasq.d/consul'
echo "Restarting dnsmasq..."
sudo systemctl enable dnsmasq
sudo service dnsmasq restart
cat > /etc/consul/config/server.json <<EOF
{
  "server": true,
  "ui": true,
  "data_dir": "/opt/consul/data",
  "client_addr": "0.0.0.0",
  "advertise_addr": "$LOCAL_IP",
  "bootstrap_expect": 3,
  "retry_join": ["provider=aws region=ap-southeast-1 tag_key=server_type tag_value=new_nomad"]
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
sudo /bin/dd if=/dev/zero of=/var/swap.1 bs=1M count=1024
sudo /sbin/mkswap /var/swap.1
sudo chmod 600 /var/swap.1
sudo /sbin/swapon /var/swap.1
echo '/var/swap.1   swap    swap    defaults        0   0' | sudo tee -a /etc/fstab