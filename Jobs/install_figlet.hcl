job "figlet" {
  datacenters = ["dc1"]
  type        = "batch"

  group "figlet" {
    task "figlet" {
      driver = "raw_exec"
      user   = "root"

      template {
        data = <<EOF
#!/bin/bash
figlet OpenInfraDays
EOF
        destination = "local/runme.bash"
        perms       = "755"
      }

      config {
        command = "local/runme.bash"
      }

      resources {
        cpu    = 128
        memory = 128
      }
    }
  }
}