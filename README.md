# homeserver-config

ホームサーバーの設定ファイル管理リポジトリ。

## 管理対象

| ディレクトリ | 取得元 | 内容 |
|---|---|---|
| `docker/` | `/srv/docker/` | docker-compose.yml 群 |
| `caddy/` | `/etc/caddy/` | Caddyfile |
| `systemd/user/` | `~/.config/systemd/user/` | systemd ユーザーユニット |
| `systemd/system/` | `/etc/systemd/system/` | systemd システムユニット（自作のみ） |
| `scripts/` | `/srv/scripts/` | 管理用スクリプト |

## /srv ディレクトリ設計

役割ごとにサブディレクトリで分離する。**設定ファイルだけをgit管理し、データは管理しない。**

```
/srv/
├── web/      ← Webサービス（Caddyfile・compose で定義）
├── media/    ← メディアファイル実体（git 管理外）
├── data/     ← アプリ状態・DB（git 管理外）
└── backup/   ← バックアップアーカイブ（git 管理外）
```

## git 管理外（.gitignore）

- `.env` / `*.env` — 環境変数・シークレット
- `secrets/` / `*.key` / `*.pem` — 秘密鍵・証明書
- メディアファイル（動画・音楽・画像）
- DBダンプ・SQLiteファイル
- Docker ボリュームの実データ（`data/` `db/` `media/` 等）

## 日常ワークフロー

### 設定変更を記録する

```bash
# 1. ライブ設定をリポジトリに取り込む
./sync.sh

# 2. 差分を確認してコミット
git diff
git add -p
git commit -m "update: Caddyfile — add new subdomain"
```

### 新マシンにデプロイする

```bash
# 1. リポジトリをクローン
git clone <remote-url> ~/homeserver-config
cd ~/homeserver-config

# 2. リモートを確認（必要なら --remote で設定）
./setup-git.sh

# 3. 設定をライブ環境に展開
./setup-git.sh --deploy

# 4. .env ファイルを手動配置（git 管理外）
sudo cp /path/to/backup/.env /srv/docker/myapp/.env
```

## スクリプト

| スクリプト | 役割 |
|---|---|
| `sync.sh` | ライブ設定 → リポジトリへ取り込み |
| `setup-git.sh` | リモート設定 / リポジトリ → ライブ環境へデプロイ |
| `scripts/homeserver-backup.sh` | DBとアプリ状態をresticへバックアップ |

## バックアップ

`backup.env.example` を `/etc/homeserver-backup.env` にコピーし、別途
`/etc/homeserver-backup.password` を600権限で作成する。バックアップ先は
OSディスクとは異なるファイルシステムまたはリモートを指定する。

初回のみ `restic init` を実行した後、次を有効化する。

```bash
sudo systemctl enable --now homeserver-backup.timer
sudo systemctl start homeserver-backup.service
```

月1回は一時ディレクトリへの復元テストを行うこと。


## Surface / Android / サーバーの使い分け

- Surface (Fedora): GitHubからcloneし、設定やWeb UIを編集してpushする。
- サーバー: `git pull` 後に `./scripts/config-check.sh` を通してからデプロイする。
- Android: Tailscale接続中に `https://start.tail90daba.ts.net` をホーム画面へ追加し、状態確認とChatGPT履歴検索を行う。

変更前後は次を実行する。

```bash
./scripts/config-check.sh
git diff --check
```
