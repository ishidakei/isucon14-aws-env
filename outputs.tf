output "public_ips" {
  description = "各サーバのパブリックIP"
  value       = { for k, v in aws_instance.node : k => v.public_ip }
}

output "private_ips" {
  description = "各サーバのプライベートIP（サーバ間通信・ベンチ対象指定に使う）"
  value       = { for k, v in aws_instance.node : k => v.private_ip }
}

output "ssh_config_path" {
  description = "生成されたssh_config。~/.ssh/config から Include する"
  value       = local_file.ssh_config.filename
}

locals {
  bench_targets = [for n in var.node_names : n if n != "bench"]

  # bench ノードが無い構成では、ベンチ対象サーバ自身で回す前提で決済モックを 127.0.0.1 に向ける
  payment_host = try(aws_instance.node["bench"].private_ip, "127.0.0.1")

  bench_commands = {
    for n in local.bench_targets : n => format(
      "cd /home/isucon && ./bench run --addr %s:443 --target https://isuride.xiv.isucon.net --payment-url http://%s:12346 --payment-bind-port 12346",
      aws_instance.node[n].private_ip,
      local.payment_host,
    )
  }
}

output "bench_commands" {
  description = "ベンチ対象サーバごとのベンチ実行コマンド（benchサーバ上で isucon ユーザとして実行）。bin/bench が使う"
  value       = local.bench_commands
}

output "bench_command" {
  description = "既定のベンチ対象（node_names の先頭）向けのベンチ実行コマンド"
  value       = local.bench_commands[local.bench_targets[0]]
}
