# ISUCON14 練習環境 (Terraform)

[matsuu/aws-isucon](https://github.com/matsuu/aws-isucon) が公開している ISUCON14 用 AMI から、
アプリ3台＋ベンチ1台を同一サブネットに立てる。サーバ内の構築は AMI が済ませているので、
Terraform はインスタンスとネットワークだけを扱う。

AMI の中身（構築手順、ベンチの使い方、本来の競技環境との差分）は
[matsuu/aws-isucon の isucon14](https://github.com/matsuu/aws-isucon/tree/main/isucon14) を参照。

## 作るもの

| リソース | 内容 |
|---|---|
| EC2 × 4 | `isu1` `isu2` `isu3` `bench`（ホスト名を cloud-init で固定） |
| Security Group × 1 | 22/443 は terraform 実行ホストのIP（または `allowed_cidrs`）のみ。サーバ間は自己参照ルールで全許可 |
| 生成ファイル | `generated/ssh_config`、`generated/hosts` |

VPC・サブネットはデフォルトVPCのものを流用する（練習環境のため）。

## 前提

- Terraform 1.6 以上
- jq（`bin/bench` が使う）
- AWS 認証情報（`aws sts get-caller-identity` が通ること）
- GitHub に SSH 公開鍵を登録してあること（`https://github.com/<user>.keys` で見える鍵が使われる）
- vCPU クォータ: c5.large × 4 = 8 vCPU

## 使い方

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars          # github_users を自分（とチームメンバー）の GitHub ユーザ名にする

# AWS プロファイル として `default` 以外のプロファイルを使う場合は、
# `terraform` と `aws` の両方に効くよう `AWS_PROFILE` を環境変数で渡す。
# 例: export AWS_PROFILE=isucon14

terraform init
terraform apply
```

上記を行うと、GitHub に登録した公開鍵が terraform で構築される EC2 の `isucon` と `ubuntu`
というユーザ用の鍵として入る。

22/443 の許可元は、既定では `terraform apply` を実行したホストのグローバルIPだけになる。
別のホストからも接続する場合や複数人で使う場合は `allowed_cidrs` に列挙する。
自分のIPが変わったら `terraform apply` をもう一度実行すると追従する。

`~/.ssh/config` に一度だけ以下を追記しておく。

```
Include /path/to/isucon14-aws-env/generated/ssh_config
```

以降 `ssh isu1` で `isucon` ユーザとして入れる。VSCode の Remote-SSH でもこのホスト名が出る。
秘密鍵は `ssh_config` に書いていないので、ssh-agent か `~/.ssh` の既定の鍵が GitHub に登録したものと
一致している必要がある。

`generated/hosts` の行をローカルPCの `/etc/hosts` に貼ると、
ブラウザで `https://isuride.xiv.isucon.net` を開いて動作確認できる。

### AWS プロファイル

プロファイルを指定するための環境変数 `AWS_PROFILE` を毎回設定するのが面倒なら `.envrc`（direnv）などに
書いても良い。

リージョンは `variables.tf` の `region` の既定値 `ap-northeast-1` を `main.tf` の provider に
渡しているので、プロファイルの既定リージョンは関係ない。`ap-northeast-1` にしている理由は、
matsuu/aws-isucon が AMI を東京リージョンにしか公開していないため。
AMI はリージョンをまたいで参照できないので、他のリージョンに立てるには AMI を自分でコピーするか
Packer で作り直す必要がある。

## ベンチマークの実行

`terraform apply` を実行したのと同じPC（このリポジトリのディレクトリ）で `bin/bench` を実行する。
本番ポータルの「ベンチ実行」に相当する。

```bash
bin/bench          # isu1（node_names の先頭）をベンチ対象にする
bin/bench isu2     # 対象を指定する
```

`bin/bench` は `terraform output` で得たコマンドを `ssh bench` に渡し、ベンチ自体は `bench` サーバ上で
動く。`ssh bench` でログインして手で打っても同じ。対象ごとのコマンドは `terraform output bench_commands` で見える。

参考実装（Go）は AMI の初期状態で起動済みなので、構築直後にそのまま回せる。
初期スコアの目安は 1000 前後。

## 片付け

```bash
terraform destroy
```

練習を中断するだけなら、コンソールまたは CLI で停止する（EBS代のみ発生）。

```bash
aws ec2 stop-instances --instance-ids $(terraform output -json public_ips >/dev/null; \
  aws ec2 describe-instances --filters "Name=tag:Project,Values=isucon14" \
  --query "Reservations[].Instances[].InstanceId" --output text)
```

停止・起動でパブリックIPが変わるため、起動後に `terraform apply` を実行して
`generated/ssh_config` を更新する（EIPは付けていない）。

## 初期状態に戻す

チューニングでDBや設定を壊した場合、`terraform destroy` → `apply` が最も確実で速い。
数分で完全な初期状態に戻る。これがこの構成の主な利点。

途中状態を保存したい場合は AMI を作成し、`ami_id` をその ID に差し替える。

## 注意

- `terraform.tfvars` は `.gitignore` に入れてある（`allowed_cidrs` を書いた場合に自分のIPを含むため）
- `use_spot = true` は費用を抑えられるが、中断で練習が止まる。
  通し練習では `false`、短時間の検証では `true` が目安
- 使い終わったら必ず destroy する（c5.large × 4 の放置は高くつく）
