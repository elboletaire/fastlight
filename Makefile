# Single entry point. Needs Swift (the Command Line Tools are enough) and
# Rust 1.85+ for the vendored fsearch. UNIVERSAL=1 builds arm64 + x86_64;
# CODESIGN_IDENTITY signs with a real identity instead of ad-hoc.

APP := build/Fastlight.app

.PHONY: app dmg test run install clean fsearch submodules

app: submodules
	scripts/bundle.sh

fsearch: submodules
	scripts/build-fsearch.sh

dmg: app
	scripts/dmg.sh

test:
	scripts/test.sh

run: app
	open $(APP)

# Quit a running copy first: replacing the bundle under a live process
# leaves it running the old binary.
install: app
	-osascript -e 'if application id "com.elboletaire.fastlight" is running then tell application id "com.elboletaire.fastlight" to quit' 2>/dev/null
	@for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq Fastlight || break; sleep 0.5; done
	rm -rf /Applications/Fastlight.app
	ditto $(APP) /Applications/Fastlight.app
	@echo "Installed /Applications/Fastlight.app"

clean:
	rm -rf build .build

# A fresh clone without --recursive has an empty third_party/fsearch.
submodules:
	@if [ ! -f third_party/fsearch/Cargo.toml ] && [ -e .git ]; then \
		git submodule update --init third_party/fsearch; \
	fi
