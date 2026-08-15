# Brilliant Scape

[Jekyll](https://jekyllrb.com/) と [GitHub Pages](https://pages.github.com/) で公開する個人ブログです。

| 項目 | 値 |
|------|-----|
| 本番 | **https://briscape.com** |
| GitHub | [`yozniax/logs`](https://github.com/yozniax/logs) |
| Jekyll | `github-pages` バンドル（`Gemfile` 参照） |

`baseurl` は空で、サイトルートがそのままトップになります。カスタムドメイン用にルートに **`CNAME`**（`briscape.com`）があります。

## このリポジトリの構成

| パス | 役割 |
|------|------|
| `index.md` + `_layouts/home.html` | トップ（記事一覧、Models / Published のタグ風リンク） |
| `_posts/*.md` | 記事。パーマリンクは `_config.yml` の `permalink` に従う（任意で `permalink:` で上書き可） |
| `model/*.md` | 各「モデル」（文体の参照元としての作家）の紹介ページ |
| `_data/tag_slugs.yml` | 記事の `tags` の先頭をモデル名として扱い、`/model/<slug>/` に対応づける |
| `archive/<year>/<month>/index.md` | 月別アーカイブ（Published からリンク） |
| `about.md` | `/about/` |
| `assets/css/main.css` | スタイル |
| `assets/post-images/` | 記事画像・**favicon**（`.ico` / `favicon-*.png`）・ヘッダー用 `about_icon` 画像など |

プラグインは `_config.yml` のとおり `jekyll-feed` と `jekyll-seo-tag`（`github-pages` に含まれる想定）です。

## ローカルプレビュー（推奨: Docker）

Ruby を入れずに動かせます。

```bash
docker compose up --build
# または: make preview
```

**http://localhost:4000/** がトップです（`baseurl` 空のため）。

Livereload は `35729` も公開しています。Linux で Docker に接続できない場合は、従来どおりユーザーを `docker` グループに入れる／`newgrp docker` などで権限を確認してください。

## ローカルプレビュー（Ruby あり）

```bash
bundle install
bundle exec jekyll serve --host 0.0.0.0 --livereload
```

**http://127.0.0.1:4000/** で閲覧できます。

## 設定の上書き（任意）

`_config.yml` のコメントどおり、ローカルだけ別 URL にしたい場合は **`_config_local.yml`** を用意し、`jekyll serve --config _config.yml,_config_local.yml` のように複数指定してください（ファイルが無ければそのままで問題ありません）。

## GitHub Pages での公開

1. このリポジトリを `main`（など）に push する。  
2. リポジトリの **Settings → Pages** で、デプロイ元ブランチを **`/(root)`** に設定する。  
3. カスタムドメインは **Settings → Pages → Custom domain** に `briscape.com` を追加し、**Enforce HTTPS** を有効にする。ルートの **`CNAME`** がビルド成果物に含まれるよう `_config.yml` の `include` に入っています。

DNS が Cloudflare 管理の場合は、GitHub の [apex 用ドキュメント](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site#configuring-an-apex-domain)に沿って A レコードまたは CNAME フラット化を設定し、SSL/TLS は通常 **Full** でよいです。反映まで数分〜最大 48 時間かかることがあります。

## 記事の追加

乱雑なメモからでよい。本文の目安は **800字**。GitHub は開かなくてよい。

### いちばん楽な流れ（iPhone の Cursor）

1. Cursor アプリでこのリポジトリのエージェントを開く。  
2. メモを投げる。整える必要はない。

```
記事
今日歌舞伎町で昼から酒。友が遅れた。街は外国人ばかり。
```

3. 候補が3つ来る。`1` / `2` / `3` / `ランダム`、または作家名を返す。  
4. 本文が出る。修正を指示できる。  
5. `commit / push / merge を一気にやる？` と聞かれる。よいときだけ出す。

モデルや日時を先に書いてよい（例: `ランダムで` / `太宰で` / `8月10日21時で` / `明日9時で`）。
写真を添付すると、既存記事と同じ位置に記事画像として入る（iPhone の写真は縮小する）。
X の投稿 URL を混ぜてよい。中身を読んで書く。本文には URL を入れない。

- 過去の日時 → そのタイムスタンプで、merge した瞬間に載る。  
- 未来の日時 → JST のその時刻まで出ない。時刻を過ぎると自動で反映する。

```bash
# メモから候補を見る / ランダムに一人選ぶ
ruby scripts/article.rb suggest --notes '昼から酒。街は外国人ばかり。'
ruby scripts/article.rb random

# 骨格だけ先に置く（本文はモデルの声で書き直す）
ruby scripts/article.rb scaffold --model random --title "題" --slug example

# 写真を記事用に縮小する / Xの投稿を読む
ruby scripts/article.rb prepare-image --file photo.jpg --date '2026-08-15 10:00' --slug example
ruby scripts/article.rb fetch-x --notes 'https://x.com/user/status/123'
```

詳細な約束は **`AGENTS.md`**。モデルの声は **`_data/models.yml`**。

### 手でファイルを置く場合

1. `_posts/YYYY-MM-DD-slug.md` を作成する。  
2. フロントマター例:

```yaml
---
layout: post
title: "タイトル"
date: YYYY-MM-DD
tags:
  - 作家名   # 先頭が「モデル」として表示・リンクされる（_data/tag_slugs.yml に定義がある場合）
permalink: /custom-path/   # 任意
image:   # 任意。画像は assets/post-images/ を参照
---
```

3. 新しいモデル（作家）を増やすときは **`model/<slug>.md`** を追加し、**`_data/tag_slugs.yml`** と **`_data/models.yml`** に同じ作家名を追記する。

## README について

本ファイルは **GitHub Pages のビルドから除外**されています（`_config.yml` の `exclude`）。
