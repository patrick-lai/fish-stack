export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: test runtime-test app-test app run-dev

test: runtime-test app-test

runtime-test:
	cd runtime && uv run --python 3.12 python -W error::ResourceWarning -m unittest discover -s tests

app-test:
	cd app && swift test

app:
	scripts/build-app.sh

# Serves on the dev port with state and the run/daemon.json home inside the worktree,
# so nothing touches ~/Library or the real ~/.fishStack that CommissionAI reads.
run-dev:
	cd runtime && exec .venv/bin/python -m fishd serve --port $${COMMISSION_DEV_PORT:-20880} --state-dir "$(CURDIR)/state-dev" --home "$(CURDIR)/state-dev/fishStack"
