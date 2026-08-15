---
name: write-article
description: iPhoneのCursorから乱雑なメモを受け取り、文豪モデルで800字の記事を書く。修正と投稿日時、commit/push/mergeの確認まで行う。
---

`AGENTS.md` に従う。GitHub を開かせない。

1. メモを読む。モデルが無ければ 3 候補とランダムだけ返す。
2. 選ばれたら `_data/models.yml` の声で 700〜900 字書く。
3. 投稿日時は JST。未指定は今。過去は即反映、未来はその時刻まで非公開。
4. 写真があれば `prepare-image` で縮小し、既存記事と同じく先頭に入れる。
5. X の URL があれば `fetch-x` で中身を読む。本文に URL は書かない。`check-urls` で確認する。
6. `_posts/YYYY-MM-DD-slug.md` に書く。月が新しければ `archive/YYYY/MM/index.md` も作る。
7. 本文を見せて、修正するか、commit / push / merge を一気にやるか聞く。許可まで git 操作をしない。
