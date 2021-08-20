job "nginx" {
  datacenters = ["dc1"]
  type = "service"

  group "web" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx:latest"
        ports = ["http"]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    service {
      name = "nginx"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.nginx-demo.rule=Host(\"nginx.nomad.kowlon.my.id\")",
      ]
      check {
        port        = "http"
        type        = "tcp"
        interval    = "15s"
        timeout     = "14s"
      }
    }

  }
}