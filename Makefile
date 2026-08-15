.PHONY: preview suggest random
preview:
	docker compose up --build

suggest:
	ruby scripts/article.rb suggest --notes "$(NOTES)"

random:
	ruby scripts/article.rb random
