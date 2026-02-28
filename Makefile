.PHONY: install install-api dev dev-fe dev-be dev-web dev-api build lint format format-check test test-unit test-api test-e2e test-ios test-ios-unit test-ios-ui build-ios check

install:
	pnpm install

install-api:
	python3 -m venv apps/api/.venv
	. apps/api/.venv/bin/activate && pip install --upgrade pip && pip install -r apps/api/requirements-dev.txt

dev:
	@if [ ! -d node_modules ]; then echo "Installing JS dependencies..."; pnpm install; fi
	pnpm dev

dev-fe:
	@if [ ! -d node_modules ]; then echo "Installing JS dependencies..."; pnpm install; fi
	pnpm dev:fe

dev-be:
	pnpm dev:be

dev-web:
	pnpm dev:fe

dev-api:
	pnpm dev:be

build:
	pnpm build

lint:
	pnpm lint

format:
	pnpm format

format-check:
	pnpm format:check

test:
	pnpm test

test-unit:
	pnpm test:unit

test-api:
	pnpm test:api

test-e2e:
	pnpm test:e2e

test-ios:
	pnpm test:ios

test-ios-unit:
	pnpm test:ios:unit

test-ios-ui:
	pnpm test:ios:ui

build-ios:
	pnpm build:ios

check:
	pnpm check
