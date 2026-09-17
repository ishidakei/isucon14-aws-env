terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = var.prefix
    }
  }
}

# ---------------------------------------------------------------------------
# Network: デフォルトVPCの、指定AZのデフォルトサブネットを使う
# （3台を必ず同一サブネット・同一AZに置く）
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "this" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = var.availability_zone
  default_for_az    = true
}

# ---------------------------------------------------------------------------
# Security Group
#   - 22/443 は自分のIPからのみ。allowed_cidrs が空なら terraform 実行ホストの
#     グローバルIPを取得して /32 で許可する（IPが変わったら apply し直せば追従する）
#   - サーバ間は自己参照ルールで全許可（bench->443, app->payment:12346,
#     mysql:3306, app:8080 などをまとめて通す）
# ---------------------------------------------------------------------------

data "http" "my_ip" {
  count = length(var.allowed_cidrs) == 0 ? 1 : 0

  url = "https://checkip.amazonaws.com"
}

locals {
  allowed_cidrs = (
    length(var.allowed_cidrs) > 0
    ? var.allowed_cidrs
    : ["${chomp(data.http.my_ip[0].response_body)}/32"]
  )
}

resource "aws_security_group" "this" {
  name        = "${var.prefix}-sg"
  description = "ISUCON14 practice environment"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.prefix}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(local.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "SSH from operator"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = toset(local.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "HTTPS from operator"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "intra" {
  security_group_id            = aws_security_group.this.id
  description                  = "intra-cluster (bench/app/db/payment)"
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "all outbound (apt, GitHub, agent API)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# SSH 公開鍵
#   本番の ISUCON と同じく、GitHub に登録した公開鍵をサーバに入れる。
#   EC2 キーペアは使わず、cloud-init で ubuntu / isucon の authorized_keys に書く。
# ---------------------------------------------------------------------------

data "http" "github_keys" {
  for_each = toset(var.github_users)

  url = "https://github.com/${each.value}.keys"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "GitHub ユーザ ${each.value} の公開鍵を取得できない (HTTP ${self.status_code})"
    }
  }
}

locals {
  authorized_keys = distinct(concat(
    flatten([for u, r in data.http.github_keys : compact(split("\n", r.response_body))]),
    var.ssh_public_keys,
  ))
}

# ---------------------------------------------------------------------------
# Instances
#   node_names の各要素がそのままホスト名になる（isu1 / isu2 / isu3 / bench）
# ---------------------------------------------------------------------------

resource "aws_instance" "node" {
  for_each = toset(var.node_names)

  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = data.aws_subnet.this.id

  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    hostname        = each.value
    authorized_keys = local.authorized_keys
  })
  user_data_replace_on_change = true

  lifecycle {
    precondition {
      condition     = length(local.authorized_keys) > 0
      error_message = "SSH 公開鍵がない。github_users か ssh_public_keys のどちらかを指定する"
    }
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.volume_size
    delete_on_termination = true
  }

  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []

    content {
      market_type = "spot"

      spot_options {
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  tags = {
    Name = "${var.prefix}-${each.value}"
    Role = each.value
  }
}

# ---------------------------------------------------------------------------
# 手元で使う補助ファイルを生成する
#   generated/ssh_config : VSCode Remote SSH / ssh から使う
#   generated/hosts      : /etc/hosts に貼る行
# ---------------------------------------------------------------------------

resource "local_file" "ssh_config" {
  filename        = "${path.module}/generated/ssh_config"
  file_permission = "0600"

  content = templatefile("${path.module}/templates/ssh_config.tftpl", {
    nodes    = { for k, v in aws_instance.node : k => v.public_ip }
    ssh_user = var.ssh_user
  })
}

resource "local_file" "hosts" {
  filename        = "${path.module}/generated/hosts"
  file_permission = "0644"

  content = <<-EOT
    # ローカルPCの /etc/hosts に追記（ブラウザでの動作確認用）
    ${try(aws_instance.node[var.node_names[0]].public_ip, "")} isuride.xiv.isucon.net

    # ベンチを別サーバから実行する場合、そのサーバの /etc/hosts に追記
    # ${try(aws_instance.node[var.node_names[0]].private_ip, "")} isuride.xiv.isucon.net
  EOT
}
