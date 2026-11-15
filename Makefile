APP := build/Flick.app
TESTING_PLUGINS := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
SWIFT_TEST_FLAGS := $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.PHONY: app test test-web bench check run install clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/Flick $(APP)/Contents/MacOS/Flick
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(APP)

test:
	swift test $(SWIFT_TEST_FLAGS)

test-web:
	FLICK_NETWORK_TESTS=1 swift test $(SWIFT_TEST_FLAGS)

bench: app
	scripts/bench-launch.sh $(APP)

check: test bench

run: app
	open $(APP)

install: app
	rm -rf ~/Applications/Flick.app
	mkdir -p ~/Applications
	cp -R $(APP) ~/Applications/Flick.app

clean:
	rm -rf .build build .bench
