# スマホから操作する検証環境

GitHubの **Actions → Lab control → Run workflow** で操作します。ブランチは `main`、実行者はリポジトリ所有者に限定します。

| action | 動作 |
|---|---|
| status | 検証用DockerとComposeの状態 |
| up | Composeを起動・更新 |
| stop | 停止（データ保持） |
| down | Composeのコンテナ・ネットワークを削除（ボリューム保持） |
| logs | 直近100行のログ |
| exec | command欄の任意のBashコマンドを実行 |

`exec` は `/srv/pc-lab/workspace` を作業場所として実行します。例:

```bash
docker ps -a
```

```bash
docker run --rm alpine sh -c 'id; echo hello'
```

```bash
printf '<h1>スマホから更新しました</h1>\n' > www/index.html
```

任意コマンドは専用の `pc-lab` ユーザーとして実行し、専用rootless Dockerを操作します。検証用ファイル・イメージ・コンテナ・ボリュームの作成、編集、削除、コンテナ内root操作が可能です。Gitもこのユーザー権限で使用できます。ホストのsudo権限や既存Dockerソケットへのアクセス権限は付与しません。

これは専用Linuxユーザーとrootless Dockerによる権限分離です。VMのような別カーネル・完全なネットワーク分離ではなく、ホストの一般公開ファイルや到達可能なネットワークサービスにはアクセスできます。ホストのapt操作はできません。検証用パッケージはコンテナ内にインストールしてください。

リポジトリは公開されているため、command入力・ログにパスワードやトークンを含めないでください。既存のGitHub認証情報は検証用ユーザーに渡しません。検証環境からGitHubへpushする場合の資格情報は、対象リポジトリに限定して別途設定します。`permissions: write-all` は検証環境へのOS権限を付与する設定ではないため使用しません。

## PCでの初回導入

以下のスクリプトを確認して管理者として実行します。

```bash
sudo bash scripts/install-lab-actions.sh
```

インストーラーは `uidmap`・`dbus-user-session`・`slirp4netns` の導入、`pc-lab` ユーザーの作成、rootless Dockerの自動起動、限定sudo入口の設置と動作検証を行います。既に同名ユーザーやディレクトリが存在する場合は停止します。途中失敗した場合は、状態を確認してから復旧してください。

- 作業場所: `/srv/pc-lab/workspace`
- このPC: http://127.0.0.1:18081
- Tailscale端末: `http://このPCのTailscale-IP:18081`（既存アクセスルールに従う）
- ローカル操作: `sudo -n /usr/local/sbin/github-lab-control status`
- ローカル任意コマンド: `printf 'docker ps\n' | sudo -n /usr/local/sbin/github-lab-control exec`

既存の `~/lab` のWeb（18080）、本番Docker、ホストTailscaleとHomeserver controlの権限は変更しません。検証用の2つ目のTailscaleは未導入です。必要に応じて検証用Docker内に独立したstateで追加できます。

参考: [Docker rootless](https://docs.docker.com/engine/security/rootless/)、[GitHub self-hosted runners](https://docs.github.com/en/actions/concepts/runners/self-hosted-runners)
