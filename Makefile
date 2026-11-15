APP := build/Flick.app
TESTING_PLUGINS := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
SWIFT_TEST_FLAGS := $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.PHONY: app icon test test-web bench check run install release clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources $(APP)/Contents/Frameworks
	cp .build/release/Flick $(APP)/Contents/MacOS/Flick
	ditto .build/release/Sparkle.framework $(APP)/Contents/Frameworks/Sparkle.framework
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	scripts/bundle-libs.py $(APP)
	codesign --force --sign - $(APP)
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(APP)

icon:
	mkdir -p .build/AppIcon.iconset
	swift scripts/make-icon.swift .build/AppIcon-1024.png
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size .build/AppIcon-1024.png --out .build/AppIcon.iconset/icon_$${size}x$${size}.png >/dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) .build/AppIcon-1024.png --out .build/AppIcon.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns

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

release: app
	scripts/release.sh $(APP)

clean:
	rm -rf .build build .bench
