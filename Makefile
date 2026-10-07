.PHONY: build test app run install clean

build:
	swift build

test:
	swift test

app:
	scripts/build-app.sh

run: app
	open build/MacTile.app

install: app
	rm -rf /Applications/MacTile.app
	cp -R build/MacTile.app /Applications/
	open /Applications/MacTile.app

clean:
	rm -rf .build build
