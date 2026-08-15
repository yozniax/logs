---
name: write-article
description: iPhoneのCursorから乱雑なメモを受け取り、文豪モデルで800字の記事を書いてPRにする。
---

`AGENTS.md` に従う。GitHub を開かせない。

1. メモを読む。モデルが無ければ 3 候補とランダムだけ返す。
2. 選ばれたら `_data/models.yml` の声で 700〜900 字書く。
3. `_posts/YYYY-MM-DD-slug.md` を PR にする。月が新しければ `archive/YYYY/MM/index.md` も作る。
4. 返信はモデル名、字数、PR の URL だけ。
