.PHONY: macos-app image receiver-release clean

macos-app:
	./scripts/build-macos-app.sh

image:
	./image/build/build.sh

receiver-release:
	./scripts/build-receiver-release.sh $(VERSION)

clean:
	rm -rf dist image/out image/build/live-build
