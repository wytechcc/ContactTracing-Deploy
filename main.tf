terraform {
  required_version = "~>0.12.21"
}
provider "external" {
  version = "~> 1.2.0"
}
provider "template" {
  version = "~> 2.1.2"
}
provider "digitalocean" {
  token   = var.api_key
  version = "~> 1.14"
}
resource "digitalocean_ssh_key" "WTCC-Joe" {
  name       = "${var.nickname}-${var.domain}"
  public_key = file("secret/dev1.key")
}
resource "digitalocean_ssh_key" "WTCC-Paul" {
  name       = "${var.nickname}-${var.domain}"
  public_key = file("secret/dev2.key")
}
resource "digitalocean_domain" "domain" {
  name = var.domain
}
resource "digitalocean_record" "a" {
  depends_on = [digitalocean_domain.domain]
  domain     = digitalocean_domain.domain.name
  name       = "@"
  value      = digitalocean_droplet.public.0.ipv4_address
  type       = "A"
  ttl        = 3600
}
resource "digitalocean_firewall" "cluster" {
  name        = "${var.nickname}-cluster"
  droplet_ids = [digitalocean_droplet.cluster.0.id]
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"] // limit to maintaing dev's VPN box
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0", "::/0"] // external API outbound, limit to mailgun/auth0
  }
  outbound_rule { // BUG, can't lock to digitalocean NS yet.
    protocol              = "tcp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"] // could check resolution for bugs...
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"] // lock to digitalocean NS "67.207.67.2", "67.207.67.3"
  }
  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
resource "digitalocean_droplet" "cluster" {
  depends_on         = [digitalocean_droplet.bastion]
  ssh_keys           = [digitalocean_ssh_key.WTCC-Joe.fingerprint, digitalocean_ssh_key.WTCC-Paul.fingerprint]
  image              = "ubuntu-18-04-x64" //alpine is fine here. Change connection user.
  region             = "sfo2"
  size               = var.public_size
  private_networking = true
  backups            = false
  ipv6               = true
  tags               = [var.nickname]
  count              = "6"
  name               = var.domain
  # user_data          = data.template_file.cloud_config.rendered
  connection {
    type        = "ssh"
    host        = self.ipv4_address
    user        = "root"
    private_key = file("~/.ssh/id_rsa")
    timeout     = "2m"
    port        = "22"
  }
  # provisioner "local-exec" {
  #   working_dir = path.module
  #   command     = "./scripts/gencerts.sh ${var.domain}"
  # }
  #   //content     = "${data.template_file.join_cluster_as_worker.rendered}"
  provisioner "remote-exec" {
    inline = [
      "apt update -qy; apt install -yq fail2ban unattended-upgrades",
      "apt-get install -yq apt-transport-https ca-certificates curl gnupg-agent software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -",
      "add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"",
      "apt-get install -yq docker-ce docker-ce-cli containerd.io",
      "curl -L \"https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose",
      "chmod +x /usr/local/bin/docker-compose"
    ]
    # "/tmp/provision-first-manager.sh ${self.ipv4_address_private}",
  }
  # Pull mailu online from config
  provisioner "remote-exec" {
    when = destroy
    inline = [
      "./backup-email",
    ]
    on_failure = continue
  }
}
