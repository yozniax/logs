# Jekyll + GitHub Pages ブログ

## セットアップ（ローカル）

```bash
bundle install
bundle exec jekyll serve
```

## GitHub Pages で公開

1. GitHub にリポジトリを作成（ユーザー公開サイトなら `YOUR_USERNAME.github.io`）。
2. このリポジトリの内容を push。
3. **Settings → Pages → Build and deployment**
   - Source: **Deploy from a branch**
   - Branch: **main** / **/(root)**

`_config.yml` の `url` を自分のサイト URL に書き換えてください。プロジェクトサイト（`username.github.io/repo-name/`）の場合は `baseurl: "/repo-name"` を設定します。

## 投稿の追加

`_posts/YYYY-MM-DD-slug.md` を作成し、フロントマターに `layout: post` と `title`, `date` を書いて commit / push します。
