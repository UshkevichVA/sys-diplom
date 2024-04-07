terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  token     = "TOKEN"
  cloud_id  = "b1gvj0u1ihj2rappt0st"
  folder_id = "b1g1m36lkp471cmnldc4"
  zone      = "ru-central1-a"
}

resource "yandex_vpc_network" "dyplom-ushkevich" {
  name = "dyplom-ushkevich"

}

resource "yandex_vpc_gateway" "nat-gateway" {
  name = "nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "route-table" {
  network_id = yandex_vpc_network.dyplom-ushkevich.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat-gateway.id
  }
}

resource "yandex_vpc_subnet" "private-subnet-1" {
  name           = "private-subnet-1"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.dyplom-ushkevich.id
  v4_cidr_blocks = ["192.168.1.0/24"]
  route_table_id = yandex_vpc_route_table.route-table.id
}

resource "yandex_vpc_subnet" "private-subnet-2" {
  name           = "private-subnet-2"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.dyplom-ushkevich.id
  v4_cidr_blocks = ["192.168.2.0/24"]
  route_table_id = yandex_vpc_route_table.route-table.id
}

resource "yandex_vpc_subnet" "private-subnet-3" {
  name           = "private-subnet-3"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.dyplom-ushkevich.id
  v4_cidr_blocks = ["192.168.3.0/24"]
  route_table_id = yandex_vpc_route_table.route-table.id
}

resource "yandex_vpc_subnet" "public" {
  name           = "public-subnet"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.dyplom-ushkevich.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_alb_target_group" "target-group" {
  name = "target-group"

  target {
    ip_address = yandex_compute_instance.web-1.network_interface.0.ip_address
    subnet_id  = yandex_vpc_subnet.private-subnet-1.id
  }

  target {
    ip_address = yandex_compute_instance.web-2.network_interface.0.ip_address
    subnet_id  = yandex_vpc_subnet.private-subnet-2.id
  }
}

resource "yandex_alb_backend_group" "backend-group" {
  name = "backend-group"

  http_backend {
    name             = "backend"
    weight           = 1
    port             = 80
    target_group_ids = [yandex_alb_target_group.target-group.id]
    load_balancing_config {
      panic_threshold = 90
    }
    healthcheck {
      timeout             = "10s"
      interval            = "2s"
      healthy_threshold   = 10
      unhealthy_threshold = 15
      http_healthcheck {
        path = "/"
      }
    }
  }
}

resource "yandex_alb_http_router" "router" {
  name = "router"
}

resource "yandex_alb_virtual_host" "router-host" {
  name           = "router-host"
  http_router_id = yandex_alb_http_router.router.id
  route {
    name = "route"
    http_route {
      http_match {
        path {
          prefix = "/"
        }
      }
      http_route_action {
        backend_group_id = yandex_alb_backend_group.backend-group.id
        timeout          = "3s"
      }
    }
  }
}

resource "yandex_alb_load_balancer" "load-balancer" {
  name               = "load-balancer"
  network_id         = yandex_vpc_network.dyplom-ushkevich.id
  security_group_ids = [yandex_vpc_security_group.load-balancer-sg.id, yandex_vpc_security_group.private-sg.id]

  allocation_policy {
    location {
      zone_id   = "ru-central1-b"
      subnet_id = yandex_vpc_subnet.private-subnet-3.id
    }
  }

  listener {
    name = "listener-1"
    endpoint {
      address {
        external_ipv4_address {
        }
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.router.id
      }
    }
  }
}

resource "yandex_vpc_security_group" "private-sg" {
  name       = "private-sg"
  network_id = yandex_vpc_network.dyplom-ushkevich.id

  ingress {
    protocol       = "ANY"
    v4_cidr_blocks = ["192.168.1.0/24", "192.168.2.0/24", "192.168.3.0/24", "192.168.10.0/24"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "load-balancer-sg" {
  name       = "load-balancer-sg"
  network_id = yandex_vpc_network.dyplom-ushkevich.id

  ingress {
    protocol          = "ANY"
    v4_cidr_blocks    = ["0.0.0.0/0"]
    predefined_target = "loadbalancer_healthchecks"
  }

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "ICMP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "bastion-sg" {
  name       = "bastion-sg"
  network_id = yandex_vpc_network.dyplom-ushkevich.id

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  ingress {
    protocol       = "ICMP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "kibana-sg" {
  name       = "kibana-sg"
  network_id = yandex_vpc_network.dyplom-ushkevich.id

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 5601
  }

  ingress {
    protocol       = "ICMP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "zabbix-sg" {
  name       = "zabbix-sg"
  network_id = yandex_vpc_network.dyplom-ushkevich.id

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 8080
  }

  ingress {
    protocol       = "ICMP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "elasticsearch-sg" {
  name       = "elasticsearch-sg"
  network_id = yandex_vpc_network.dyplom-ushkevich.id

  ingress {
    protocol          = "TCP"
    security_group_id = yandex_vpc_security_group.kibana-sg.id
    port              = 9200
  }

  ingress {
    protocol          = "TCP"
    security_group_id = yandex_vpc_security_group.private-sg.id
    port              = 9200
  }

  ingress {
    protocol          = "TCP"
    security_group_id = yandex_vpc_security_group.bastion-sg.id
    port              = 22
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

#VM

resource "yandex_compute_instance" "web-1" {
  name     = "web-1"
  hostname = "web-1"
  zone     = "ru-central1-a"

  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd833v6c5tb0udvk4jo6"
      size     = 15
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private-subnet-1.id
    security_group_ids = [yandex_vpc_security_group.private-sg.id]
    ip_address         = "192.168.1.3"
  }

  metadata = {
    user-data = "${file("/home/ushkevichva/meta.txt")}"

  }
}


resource "yandex_compute_instance" "web-2" {
  name     = "web-2"
  hostname = "web-2"
  zone     = "ru-central1-b"

  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd833v6c5tb0udvk4jo6"
      size     = 15
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private-subnet-2.id
    security_group_ids = [yandex_vpc_security_group.private-sg.id]
    ip_address         = "192.168.2.3"
  }

  metadata = {
    user-data = "${file("/home/ushkevichva/meta.txt")}"

  }
}

resource "yandex_compute_instance" "zabbix" {
  name     = "zabbix"
  hostname = "zabbix"
  zone     = "ru-central1-b"

  resources {
    cores  = 2
    memory = 6
  }

  boot_disk {
    initialize_params {
      image_id = "fd8pnse1rshdvced0u8h"
      size     = 15
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    security_group_ids = [yandex_vpc_security_group.private-sg.id, yandex_vpc_security_group.zabbix-sg.id]
    ip_address         = "192.168.10.3"
    nat                = true

  }

  metadata = {
    user-data = "${file("/home/ushkevichva/meta.txt")}"
  }
}

resource "yandex_compute_instance" "elasticsearch" {
  name     = "elasticsearch"
  hostname = "elasticsearch"
  zone     = "ru-central1-b"

  resources {
    cores  = 4
    memory = 8
  }

  boot_disk {
    initialize_params {
      image_id = "fd833v6c5tb0udvk4jo6"
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private-subnet-3.id
    security_group_ids = [yandex_vpc_security_group.private-sg.id, yandex_vpc_security_group.elasticsearch-sg.id]
    ip_address         = "192.168.3.3"
  }

  metadata = {
    user-data = "${file("/home/ushkevichva/meta.txt")}"
  }


}

resource "yandex_compute_instance" "kibana" {
  name     = "kibana"
  hostname = "kibana"
  zone     = "ru-central1-b"

  resources {
    cores = 2
    #    core_fraction = 20
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = "fd833v6c5tb0udvk4jo6"
      size     = 15
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    security_group_ids = [yandex_vpc_security_group.private-sg.id, yandex_vpc_security_group.kibana-sg.id]
    ip_address         = "192.168.10.4"
    nat                = true

  }

  metadata = {
    user-data = "${file("/home/ushkevichva/meta.txt")}"
  }
}

resource "yandex_compute_instance" "bastion" {
  name     = "bastion"
  hostname = "bastion"
  zone     = "ru-central1-b"

  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd833v6c5tb0udvk4jo6"
      size     = "15"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    security_group_ids = [yandex_vpc_security_group.bastion-sg.id]
    ip_address         = "192.168.10.5"
    nat                = true
  }

  metadata = {
    user-data = "${file("/home/ushkevichva/meta.txt")}"
  }
}

resource "yandex_compute_snapshot_schedule" "snapshots" {
  name = "snapshots"

  schedule_policy {
    expression = "0 12 * * *"
  }

  snapshot_count = 7

  snapshot_spec {
    description = "snapshot"
    labels = {
      environment = "production"
    }
  }

  disk_ids = ["${yandex_compute_instance.bastion.boot_disk.0.disk_id}",
    "${yandex_compute_instance.web-1.boot_disk.0.disk_id}",
    "${yandex_compute_instance.web-2.boot_disk.0.disk_id}",
    "${yandex_compute_instance.zabbix.boot_disk.0.disk_id}",
    "${yandex_compute_instance.elasticsearch.boot_disk.0.disk_id}",
  "${yandex_compute_instance.kibana.boot_disk.0.disk_id}", ]
}
