# Brilliant Scape — プロジェクトサマリー

Yo Yoshizaki（`yozniax` / `champlasonic`）の個人ブログ。文豪の文体を借りて、自分の経験と想いを短い随筆にする。

| 項目 | 内容 |
|------|------|
| 公開 | https://briscape.com |
| リポジトリ | [`yozniax/logs`](https://github.com/yozniax/logs) |
| 技術 | Jekyll（`github-pages`）+ GitHub Pages |
| ドメイン | `briscape.com`（ルートの `CNAME`） |
| 著者 | Yo Yoshizaki |
| コピー | 文豪の文体をお借りして経験と想いと考えを書いています |

サイトは静的 HTML。記事の中身は、iPhone の Cursor に乱雑なメモを投げてエージェントが書く。著者は GitHub を開かない。

---

## 何をする場所か

ブログの見た目は最小限。ヘッダに太字の **Brilliant Scape** と、小さいディスクリプション。右に About アイコン（`https://www.doyo.be`）。トップは記事一覧。各記事は「by ○○ model」と日付が付く。

中身の核は **モデル**。太宰治、夏目漱石、村上春樹など、カタログにある作家の声で 800 字前後の随筆を書く。AI が書いたことは本文に残さない。URL も本文に書かない。

---

## 記事の流れ

1. Cursor（iPhone 可）にメモを投げる。整文しなくてよい。
2. モデル未指定なら候補 3 つと「0. ランダム」を出して待つ。指定があればその声で書く。
3. 本文を見せる。修正を受け付ける。
4. 「一気に」と言われてから commit / push / merge する。言うまでは git しない。

日時は **JST**。過去なら merge した瞬間に載る。未来ならその時刻まで出ない。15 分おきの GitHub Actions が、時刻の来た記事があれば Pages を再ビルドする。

写真はチャット添付だと Cloud Agent のディスクに落ちないことが多い。X の投稿 URL を混ぜると、そちらの画像を記事用に縮小して入れる。生成画像では代用しない。

詳細な約束は `AGENTS.md`。エージェント用スキルは `.cursor/skills/write-article/`。

---

## リポジトリの地図

| パス | 役割 |
|------|------|
| `_posts/` | 記事。ファイル名は `YYYY-MM-DD-ascii-slug.md` |
| `_data/models.yml` | モデルの声・一人称・キーワード |
| `_data/tag_slugs.yml` | モデル名 → `/model/<slug>/` |
| `model/` | 各モデルの紹介ページ |
| `archive/YYYY/MM/` | 月別アーカイブ |
| `assets/css/main.css` | スタイル（明朝、記事画像はグレースケール） |
| `assets/post-images/` | 記事画像・favicon・ヘッダアイコン |
| `scripts/article.rb` | 候補、日時、字数、X 取得、画像処理 |
| `scripts/resize_image.py` | 長辺 1600px、JPEG、位置情報なし |
| `_layouts/` `_includes/` | 共通ヘッダ、記事、一覧、モデル byline |
| `.github/workflows/publish-due-posts.yml` | 未来記事の公開 |

新しいモデルを増やすときは `model/<slug>.md` と `tag_slugs.yml` と `models.yml` を同時に直す。普段は増やさない。

---

## モデル（18）

lyric / essay / vernacular / idea の四群。候補出しのとき群を混ぜる。

| モデル | 一人称 | 向き |
|--------|--------|------|
| 太宰治 | 私 | 弱さ、酒、都会。歴史的仮名 |
| 夏目漱石 | 私 | 区切り、皮肉な内省。文語交じり |
| 菊池寛 | 私 | 明快な一件 |
| 村上春樹 | 僕 | 身体、店、淡々とした日常 |
| 坂口安吾 | 私 | 生活の泥と本音 |
| 三島由紀夫 | 私 | 美と毒、組織 |
| 寺山修司 | 私 | 熱狂、挑発 |
| 安部公房 | 僕 | 都市、異化 |
| 中原中也 | 僕 | 恐怖、記憶、反復 |
| 林芙美子 | 私 | 忙しさ、季節 |
| 泉鏡花 | 私 | 病、光、美文 |
| 織田作之助 | 私 | 俗、逆説 |
| 町田町蔵 | 私 | 口語のまま |
| 北大路魯山人 | 私 | 食、土地 |
| 中谷宇吉郎 | 私 | 観察、道具 |
| 司馬遼太郎 | 私 | 年齢を時代の眼で |
| 柿本人麻呂 | 余 | 短い詠嘆。文語 |
| 松本清張 | 私 | 制度、職業、空白 |

---

## 公開と確認

本番は `main` を GitHub Pages がビルドする。`future: false` のため、未来の `date` はビルドに出ない。

ローカル確認:

- Docker: `docker compose up --build` → http://127.0.0.1:4000/
- Ruby: `bundle exec jekyll serve --host 0.0.0.0 --port 4000 --livereload`

サイト構成の説明は `README.md`。記事を増やす作業は `AGENTS.md` が正。
