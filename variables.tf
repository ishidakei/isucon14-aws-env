variable "region" {
  description = "AMIが東京リージョンにあるため ap-northeast-1 固定"
  type        = string
  default     = "ap-northeast-1"
}

variable "availability_zone" {
  description = "3台を置くAZ。キャパシティ不足なら 1c / 1d に変更する"
  type        = string
  default     = "ap-northeast-1a"
}

variable "prefix" {
  description = "リソース名の接頭辞"
  type        = string
  default     = "isucon14"
}

variable "ami_id" {
  description = "matsuu/aws-isucon が公開しているISUCON14用AMI（東京リージョン）"
  type        = string
  default     = "ami-0fcf9e8e8675a9ee4"
}

variable "instance_type" {
  description = "本番競技環境に合わせる場合は c5.large"
  type        = string
  default     = "c5.large"
}

variable "node_names" {
  description = <<-EOT
    立てるサーバのホスト名。AGENTS.md の役割表とこの名前を対応させる。
    本番同様にベンチを別サーバで動かす場合は bench を含める。
    1台目（先頭要素）が既定のベンチ対象サーバとして扱われる。
  EOT
  type        = list(string)
  default     = ["isu1", "isu2", "isu3", "bench"]
}

variable "volume_size" {
  description = "EBSサイズ(GB)。最低16GB、競技環境は20GiB。ログ増加を見て余裕を持たせる"
  type        = number
  default     = 30
}

variable "github_users" {
  description = <<-EOT
    SSH 公開鍵を取り込む GitHub ユーザ名。https://github.com/<name>.keys の鍵を
    ubuntu / isucon 両ユーザの authorized_keys に入れる。
    本番の ISUCON と同じく、チームメンバー全員分を列挙する。
  EOT
  type        = list(string)
  default     = []
}

variable "ssh_public_keys" {
  description = "GitHub に登録していない公開鍵を直接渡す場合に使う。github_users と併用できる"
  type        = list(string)
  default     = []
}

variable "ssh_user" {
  description = "生成される ssh_config のログインユーザ。isucon は NOPASSWD sudo を持つ"
  type        = string
  default     = "isucon"
}

variable "allowed_cidrs" {
  description = <<-EOT
    22/443 を許可する送信元。
    空のままなら terraform を実行しているホストのグローバルIP /32 だけを許可する。
    チームメンバーと練習する場合は全員分を /32 で列挙する。
  EOT
  type        = list(string)
  default     = []
}

variable "use_spot" {
  description = <<-EOT
    true にするとスポットインスタンスで起動し費用を抑えられるが、
    中断されると練習が途中で終わる。本番想定の通し練習では false 推奨。
  EOT
  type        = bool
  default     = false
}
