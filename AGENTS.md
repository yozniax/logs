# AGENTS.md

## Cursor Cloud specific instructions

This repository is a single **Jekyll static blog** (Ruby + the `github-pages` gem bundle). There is no backend, database, or API — the only service is the Jekyll dev server. General setup and content-authoring docs live in `README.md`.

### Environment notes
- Ruby 3.2 (matching the `Dockerfile` base image `ruby:3.2`) and Bundler are provided by the VM environment. The startup update script runs `bundle install` for you.
- Gems are installed into a project-local `./vendor/bundle` (configured via `bundle config set --local path vendor/bundle`, stored in the git-ignored `.bundle/config`). Do **not** run a bare `gem install` / system-wide `bundle install` — it fails with a permission error on `/var/lib/gems`. Always prefix Jekyll commands with `bundle exec`.
- Do not use Docker here. `docker-compose.yml` / `Dockerfile` exist for convenience, but Docker is not installed in this environment; run Jekyll natively instead.

### Run / build / test
- Run the dev server: `bundle exec jekyll serve --host 0.0.0.0 --port 4000 --livereload`. Homepage: `http://127.0.0.1:4000/`. LiveReload auto-regenerates on file changes (verified: adding a `_posts/*.md` file rebuilds and serves it within a couple seconds).
- Build only: `bundle exec jekyll build` (outputs to the git-ignored `_site/`).
- There is no test suite or linter in this repo. "Testing" a change means building/serving the site and confirming the affected page(s) render.

### Content gotchas
- Posts live in `_posts/YYYY-MM-DD-slug.md` with front matter; permalinks follow `_config.yml` (`permalink:`) unless overridden per-post.
- A post's first `tags` entry is treated as the "model" (author) and linked via `_data/tag_slugs.yml`; add new authors there plus a `model/<slug>.md` page.
