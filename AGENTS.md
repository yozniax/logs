# AGENTS.md

このリポジトリは Jekyll の個人ブログ **Brilliant Scape**（https://briscape.com）です。
文豪の文体をモデルに、著者の経験と想いを短い随筆にする。

一般的なサイト構成は `README.md`。記事を増やす作業では、このファイルを先に読む。

## 記事生成（最優先）

正規の投入口は **Cursor**（iPhone アプリを含む）。
著者に GitHub を開かせない。Issue を作らせない。

乱雑なメモを整文せず、創造的な随筆にする。箇条書きや単語の羅列で足りる。
足りない情景は補ってよいが、メモにない事実・固有名詞・他人の悪口は足さない。

スマホ向けに短く返す。手順の説明はしない。

### いつ記事にするか

次のいずれかなら記事生成に入る。サイト改修の質問なら記事にしない。

- 「記事」「書いて」「メモ」などがある
- 体験や感想の走り書きで、コードや設定の話ではない

すでに原稿を出しているあとで、短く・結を変えて・日時を変えて、といった指示が来たら **修正** であり、新しい記事ではない。

### モデルの決め方

モデルは `_data/models.yml` と `_data/tag_slugs.yml` にある作家だけを使う。新しく作らない。

1. 著者がモデル名を指定していれば、それを使う。
2. 「ランダム」なら `ruby scripts/article.rb random` で一つ選び、選んだ名前を先に伝える。
3. 指定がなければ、候補を **3つ** 出し、加えて **0. ランダム** を提示して待つ。
   - `ruby scripts/article.rb suggest --notes '…'` を使ってよい。
   - 各候補は「名前 — 一言」だけ。
4. 番号・名前・「ランダム」のどれかで答えたら、本文を書く。
5. 「書いて」「おまかせ」と急かすときだけ、候補を出さずランダムで進めてよい。使うモデル名は先に言う。

同じモデルが直近の記事で続いているときは、候補から外すか後ろに下げる。

最初の返信の型（これ以上長くしない）:

```
1. 太宰治 — 弱さ、酒、都会
2. 坂口安吾 — 生活の泥と本音
3. 菊池寛 — 明快な一件
0. ランダム
```

### 投稿日時

日時は **JST**。未指定なら今。

- 過去 → そのタイムスタンプで出す。merge した瞬間にサイトへ載る。
- 未来 → フロントマターにその日時を書き、merge しても JST のその時刻まで出ない。時刻を過ぎると GitHub Actions が Pages を再ビルドする。

`ruby scripts/article.rb when --date '8月10日 21時'` で過去か未来かを確認する。
フロントマターは必ず次の形。

```yaml
date: 2026-08-10 21:00:00 +0900
```

ファイル名の日付は、その JST の暦日。日時を直したら、日が変わるときはファイル名と `archive/YYYY/MM/` も直す。

### 本文の約束

- 文字数は **800字程度**。フロントマターと画像を除いた本文で **700〜900字**。
- 確認: `ruby scripts/article.rb count --file _posts/….md`
- タイトルは短く、本文の核だけを言う。説明的な長い題は避ける。
- 一人称・仮名遣い・文の呼吸は、選んだモデルに従う。`_data/models.yml` の `voice` と、そのモデルの既存 `_posts` を読む。
- 太宰治は歴史的仮名遣い。夏目漱石は文語交じり。柿本人麻呂は文語で「余」。町田町蔵は口語のまま。ほかは現代仮名を基本とする。
- 見出しは付けない。段落は 2〜5。
- 公開用の本文に、メモの引用や「AIが書いた」といった種明かしを残さない。
- **本文に URL を絶対に書かない。** `https://`、`x.com`、`t.co` も不可。確認: `ruby scripts/article.rb check-urls --file _posts/….md`

### 写真

チャットの写真添付は、モデルには見えることがあるが、**VM にファイルとして届かないことが多い**。同じ添付の再送では直らない。生成画像で代用しない。

取る順:

1. `ruby scripts/article.rb find-attachment`（直近1時間の実ファイル。複数なら先頭）
2. メモに X の投稿 URL か画像 URL があれば、それで取る。

```bash
python3 -m pip install --user Pillow   # 未導入なら
ruby scripts/article.rb prepare-image --url 'https://x.com/user/status/…' --date '2026-08-15 10:00' --slug example
# 実ファイルがあるときだけ --file
ruby scripts/article.rb prepare-image --file 添付パス --date '2026-08-15 10:00' --slug example
```

3. 置き場所は `assets/post-images/YYYYMMDD-slug.jpg`。長辺 1600px、JPEG、おおむね 400KB 以下。
4. 既存記事と同じく、フロントマターと本文先頭に入れる。CSS（`.post-content img` のグレースケールと余白）がそのまま当たる。

ファイルも URL もないときは、写真なしで本文を出し、「Xの投稿を貼って」とだけ言う。手順は説明しない。

```yaml
image: /assets/post-images/20260815-example.jpg
```

```markdown
![タイトル]({{ '/assets/post-images/20260815-example.jpg' | relative_url }})
```

画像の Markdown は字数に数えない。会話に出す本文プレビューからも、URL やファイルパスは省いてよい。

### X の投稿

メモに `x.com` / `twitter.com` の投稿 URL があれば、中身を読んでから書く。

```bash
ruby scripts/article.rb fetch-x --notes 'メモと https://x.com/user/status/…'
```

取れた本文・名前・画像を材料にする。画像は `prepare-image --url` で記事に入れる。足りない情景は補ってよいが、投稿にない事実は足さない。
**生成した記事の文中に、その URL も他の URL も書かない。** 「リンクはこちら」とも書かない。

### ファイル

1. `_posts/YYYY-MM-DD-ascii-slug.md` を作る。
2. フロントマター:

```yaml
---
layout: post
title: "タイトル"
date: 2026-08-10 21:00:00 +0900
tags:
  - 作家名

permalink: /slug/
image: /assets/post-images/20260815-slug.jpg   # 写真があるときだけ
---
```

3. `tags` の先頭がモデル。`_data/tag_slugs.yml` のキーと一致させる。
4. その月の `archive/YYYY/MM/index.md` が無ければ作る。
5. 新しいモデルを増やすときだけ `model/<slug>.md` と `tag_slugs.yml` と `models.yml` を同時に更新する。普段は増やさない。

### 生成したあとの対話

原稿を出したら、**すぐには commit / push / merge しない**。本文を会話に出し、次だけ聞く。

```
太宰治 / 812字 / 2026-08-10 21:00 JST（過去・即反映）

（本文）

修正する？
commit / push / merge を一気にやる？
```

- 修正指示 → 直して、同じ型でもう一度出す。聞く。
- 「一気に」「出して」「マージして」→ commit、push、PR、**main へ merge**。
- 「プッシュだけ」→ commit、push、PR。merge しない。
- 黙っている・「まだ」→ ファイルは置いたまま、git 操作をしない。

未来日時を一気に出した場合は、反映が JST のその時刻であることを一言添える。

著者への操作手順（GitHub の開き方など）は書かない。一気に出したあとだけ、PR の URL を残す。

## Cursor Cloud でのサイト確認

Ruby 3.2 と Bundler がある前提。Docker は使わない。

```bash
bundle config set --local path vendor/bundle
bundle install
bundle exec jekyll build
# 必要なら: bundle exec jekyll serve --host 0.0.0.0 --port 4000 --livereload
```

テストスイートはない。記事を足したら `jekyll build` が通ることと、字数が 700〜900 であることを確認する。
未来の `date` は `future: false` のためビルドに出ない。それでよい。
