.PHONY: help dockerize

help:
	@echo "Available targets:"
	@echo "  make dockerize - Dockerize the service"

dockerize:
	@echo "Dockerizing service..."
	./.script/dockerize.sh

