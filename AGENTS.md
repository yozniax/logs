# AGENTS.md

このリポジトリは Jekyll の個人ブログ **Brilliant Scape**（https://briscape.com）です。
文豪の文体をモデルに、著者の経験と想いを短い随筆にする。

一般的なサイト構成は `README.md`。記事を増やす作業では、このファイルを先に読む。

## 記事生成（最優先）

著者が乱雑なメモを投げたら、整文せず、創造的な随筆にする。
LINE の下書き、箇条書き、単語の羅列で足りる。足りない情景は補ってよいが、メモにない事実・固有名詞・他人の悪口は足さない。

### 受け取り方

次のどれでも同じ扱いをする。

- チャットに貼られたメモ（LINE からコピーしたものも含む）
- GitHub Issue（ラベル `article`、テンプレート「記事メモ」）
- `scripts/article.rb suggest` の出力に続く指示

Issue から始めるときは、本文の「メモ」「モデル」「タイトル」「補足」を読む。

### モデルの決め方

モデルは `_data/models.yml` と `_data/tag_slugs.yml` にある作家だけを使う。新しく作らない。

1. 著者がモデル名を指定していれば、それを使う。
2. 「ランダム」なら `ruby scripts/article.rb random` で一つ選び、選んだ名前を先に伝える。
3. 指定がなければ、候補を **3つ** 出し、加えて **ランダム** を提示して待つ。
   - `ruby scripts/article.rb suggest --notes '…'` を使ってよい。
   - 各候補に、なぜ今のメモに合うかを一文で添える。
4. 著者が番号・名前・「ランダム」のどれかで答えたら、本文を書く。
5. 著者が「書いて」「おまかせ」と急かすときだけ、候補を出さずランダムで進めてよい。その場合も、使うモデル名を本文の前に明示する。

同じモデルが直近の記事で続いているときは、候補から外すか後ろに下げる。

### 本文の約束

- 文字数は **800字程度**。フロントマターと画像を除いた本文で **700〜900字**。
- 確認: `ruby scripts/article.rb count --file _posts/….md`
- タイトルは短く、本文の核だけを言う。説明的な長い題は避ける。
- 一人称・仮名遣い・文の呼吸は、選んだモデルに従う。`_data/models.yml` の `voice` と、そのモデルの既存 `_posts` を読む。
- 太宰治は歴史的仮名遣い。夏目漱石は文語交じり。柿本人麻呂は文語で「余」。町田町蔵は口語のまま。ほかは現代仮名を基本とする。
- 見出しは付けない。段落は 2〜5。
- 画像は、著者がファイルを渡したときだけ `image:` を付ける。無いなら付けない。
- 公開用の本文に、メモの引用や「AIが書いた」といった種明かしを残さない。

### ファイル

1. `_posts/YYYY-MM-DD-ascii-slug.md` を作る。日付は著者の指定がなければ今日。
2. フロントマター:

```yaml
---
layout: post
title: "タイトル"
date: YYYY-MM-DD
tags:
  - 作家名

permalink: /slug/
---
```

3. `tags` の先頭がモデル。`_data/tag_slugs.yml` のキーと一致させる。
4. その月の `archive/YYYY/MM/index.md` が無ければ作る（既存の月別アーカイブをコピーして年月だけ変える）。
5. 新しいモデルを増やすときだけ `model/<slug>.md` と `tag_slugs.yml` と `models.yml` を同時に更新する。普段は増やさない。

骨格だけ先に置くなら:

```bash
ruby scripts/article.rb scaffold --model 太宰治 --title "題" --slug example --notes 'メモ'
```

### 出し方

記事は pull request にする。直接 `main` へ推さない。
PR 本文に、使ったモデル、本文の字数、メモの要約を一行で書く。

## Cursor Cloud でのサイト確認

Ruby 3.2 と Bundler がある前提。Docker は使わない。

```bash
bundle config set --local path vendor/bundle
bundle install
bundle exec jekyll build
# 必要なら: bundle exec jekyll serve --host 0.0.0.0 --port 4000 --livereload
```

テストスイートはない。記事を足したら `jekyll build` が通ることと、字数が 700〜900 であることを確認する。
