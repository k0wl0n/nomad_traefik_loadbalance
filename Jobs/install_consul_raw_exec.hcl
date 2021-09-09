job "consul" {
  datacenters = ["dc1"]
  group "consul" {
    count = 1
    task "consul" {
      driver = "raw_exec"
            
      config {
        command = "consul"
        args    = ["agent", "-dev"]
      }
      resources {
        cpu    = 128
        memory = 128
      }
      artifact {
        source = "https://releases.hashicorp.com/consul/1.10.1/consul_1.10.1_linux_amd64.zip"
      }
    }
  }
}