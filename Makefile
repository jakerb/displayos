.PHONY: macos-app image clean

macos-app:
	./scripts/build-macos-app.sh

image:
	./image/build/build.sh

clean:
	rm -rf dist image/out image/build/live-build
