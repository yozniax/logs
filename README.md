# Jekyll + GitHub Pages ブログ

## プレビュー（推奨: Docker）

Ruby をローカルに入れずに表示できます。Docker を入れたうえで:

```bash
docker compose up --build
# または: make preview
```

サーバーは **`0.0.0.0:4000`** で待ち受けます。本番と同じく **`baseurl` は空**なので、トップは次です。

**http://localhost:4000/**

（旧構成で `baseurl: "/logs"` にしている場合だけ **`http://localhost:4000/logs/`** になります。）

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

成功したら、もう一度 `docker compose up --build` を実行し、**http://localhost:4000/** を開いてください。

Cursor / VS Code では **「Dev Containers: Reopen in Container」** でこのフォルダをコンテナで開くと、ポート 4000 の転送通知からも開けます。

## セットアップ（ローカルに Ruby がある場合）

```bash
bundle install
bundle exec jekyll serve --host 0.0.0.0 --livereload
```

表示 URL は **`http://127.0.0.1:4000/`** です（`baseurl` 空のため）。

## GitHub Pages で公開

1. GitHub にリポジトリを作成（ユーザー公開サイトなら `YOUR_USERNAME.github.io`）。
2. このリポジトリの内容を push。
3. **Settings → Pages → Build and deployment**
   - Source: **Deploy from a branch**
   - Branch: **main** / **/(root)**

本番は **`https://briscape.com`**（ルートに index。サブドメインは不要）。`_config.yml` の `url` / `baseurl` とリポジトリルートの **`CNAME`** がそれに合わせてあります。

## Cloudflare で apex（briscape.com）を向ける（GitHub Pages）

前提: **briscape.com** の DNS が [Cloudflare](https://www.cloudflare.com/) 管理であること。

1. **GitHub（例: リポジトリ `yozniax/logs`）**  
   - **Settings → Pages → Custom domain** に **`briscape.com`** を追加。  
   - **Enforce HTTPS** を有効にする。  
   - ルートの **`CNAME`** ファイルは **`briscape.com`** の一行（このリポジトリに含める）。

2. **Cloudflare → DNS（apex）**  
   - **名前 `@`** に GitHub Pages 用の **A レコード**を追加する（[公式の IP 一覧](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site#configuring-an-apex-domain)）。  
   - または Cloudflare の **CNAME flattening** で `briscape.com` を **`yozniax.github.io`** に向ける設定が使える場合は、その方法でも可。  
   - **SSL/TLS** は通常 **Full**。証明書が有効になるまで数分〜最大48時間かかることがあります。

3. **`_config.yml`**  
   - `url: "https://briscape.com"`、`baseurl: ""` で問題ありません。

4. **ローカルプレビュー**  
   - **`http://localhost:4000/`** がトップです。

## 投稿の追加

`_posts/YYYY-MM-DD-slug.md` を作成し、フロントマターに `layout: post` と `title`, `date` を書いて commit / push します。
