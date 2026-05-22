.PHONY: build-apk build-ios build-macos build-linux build-windows clean build-all install-apk help

help:
	@echo "可用命令:"
	@echo "  make build-apk    - 构建 Android APK"
	@echo "  make build-ios    - 构建 iOS (需要 macOS)"
	@echo "  make build-macos  - 构建 macOS"
	@echo "  make build-linux  - 构建 Linux"
	@echo "  make build-windows - 构建 Windows"
	@echo "  make clean        - 清理构建"
	@echo "  make build-all    - 清理并构建 APK"
	@echo "  make install-apk  - 安装 APK 到设备"

clean:
	cd rust && cargo clean && cd ../

build-rust:
	cd rust && cargo build && cd ../

build-apk: build-rust
	flutter build apk --release

build-ios: build-rust
	flutter build ios --release

build-macos: build-rust
	flutter build macos --release

build-linux: build-rust
	flutter build linux --release

build-windows: build-rust
	flutter build windows --release

build-all: build-apk

install-apk:
	adb install build/app/outputs/flutter-apk/app-release.apk