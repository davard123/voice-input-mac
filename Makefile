.PHONY: build run install clean

APP_NAME = VoiceInput
BUILD_DIR = .build

build:
	@echo "🔨 Building $(APP_NAME)..."
	swift build --configuration release
	@echo "✅ Build complete"

run: build
	@echo "🚀 Running $(APP_NAME)..."
	$(BUILD_DIR)/release/$(APP_NAME)

install: build
	@echo "📦 Installing to /Applications..."
	cp -r $(BUILD_DIR)/release/$(APP_NAME).app /Applications/
	@echo "✅ Installed"

clean:
	@echo "🧹 Cleaning..."
	rm -rf $(BUILD_DIR)
	@echo "✅ Clean"

help:
	@echo "Usage:"
	@echo "  make build    - Build"
	@echo "  make run      - Build and run"
	@echo "  make install  - Install to Applications"
	@echo "  make clean    - Clean"
