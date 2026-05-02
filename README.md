# Jekyll + GitHub Pages ブログ

## プレビュー（推奨: Docker）

Ruby をローカルに入れずに表示できます。Docker を入れたうえで:

```bash
docker compose up --build
# または: make preview
```

サーバーは **`0.0.0.0:4000`** で待ち受けます。ブラウザでは次を開いてください（**ルート `/` ではなく `baseurl` 付き**です）。

**http://localhost:4000/logs/**

（`http://localhost:4000/` だけだと、プロジェクト用 `baseurl` の関係で正しく表示されないことがあります。必ず **`/logs/`** まで含めてください。）

### 表示されない・`docker compose` が失敗する場合（Linux）

次のエラーは **Docker デーモンに接続する権限がない** 状態です。

`permission denied while trying to connect to the docker API at unix:///var/run/docker.sock`

1. **Docker Desktop を起動したまま**にする（タスクトレイ／メニューから実行）。
2. 自分のユーザーを **`docker` グループ**に入れる（一度だけ、パスワード入力が必要です）。

```bash
sudo usermod -aG docker "$USER"
```

3. **ログアウトして再ログイン**するか、PC を再起動する（グループ変更の反映に必要です）。すぐ試すだけなら次でも可です。

```bash
newgrp docker
```

4. 確認:

```bash
docker run --rm hello-world
```

成功したら、もう一度 `docker compose up --build` を実行し、**http://localhost:4000/logs/** を開いてください。

Cursor / VS Code では **「Dev Containers: Reopen in Container」** でこのフォルダをコンテナで開くと、ポート 4000 の転送通知からも開けます。

## セットアップ（ローカルに Ruby がある場合）

```bash
bundle install
bundle exec jekyll serve --host 0.0.0.0 --livereload
```

表示 URL は **`http://127.0.0.1:4000/logs/`** です。

## GitHub Pages で公開

1. GitHub にリポジトリを作成（ユーザー公開サイトなら `YOUR_USERNAME.github.io`）。
2. このリポジトリの内容を push。
3. **Settings → Pages → Build and deployment**
   - Source: **Deploy from a branch**
   - Branch: **main** / **/(root)**

`_config.yml` の `url` を自分のサイト URL に書き換えてください。プロジェクトサイト（`username.github.io/repo-name/`）の場合は `baseurl: "/repo-name"` を設定します。

## 投稿の追加

`_posts/YYYY-MM-DD-slug.md` を作成し、フロントマターに `layout: post` と `title`, `date` を書いて commit / push します。
