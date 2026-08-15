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

乱雑なメモからでよい。LINE の下書きをコピーして投げてよい。本文の目安は **800字**。

### いちばん楽な流れ

1. GitHub で **[Issue](https://github.com/yozniax/logs/issues/new?template=article.yml)** 「記事メモ」を開く。  
2. メモを貼る。モデルは「おまかせ」（候補が3つ付く）か「ランダム」、または作家名。  
3. 候補の番号を Issue に返信するか、Cursor Cloud Agent にその Issue を渡す。  
4. エージェントが `_posts/` の原稿を pull request にする。

チャットにメモをそのまま貼っても同じ。モデルを言わなければ、候補を3つ出してから書く。

LINE から投げるときは、トークの下書きをコピーして Issue の「メモ」へ貼る。スマホの GitHub でも同じテンプレートが開く。LINE Bot は置いていない。

```bash
# メモから候補を見る / ランダムに一人選ぶ
ruby scripts/article.rb suggest --notes '昼から酒。街は外国人ばかり。'
ruby scripts/article.rb random

# 骨格だけ先に置く（本文はモデルの声で書き直す）
ruby scripts/article.rb scaffold --model random --title "題" --slug example
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
