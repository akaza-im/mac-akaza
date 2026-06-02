OUTDIR = out/
APP = $(OUTDIR)/Akaza.app
INSTALL_DIR = $(HOME)/Library/Input Methods
MODEL_VERSION = v2026.602.0
MODEL_DIR = $(OUTDIR)/model/$(MODEL_VERSION)
MODEL_TARBALL = $(MODEL_DIR)/akaza-default-model.tar.gz

.PHONY: all build build-universal bundle install clean download-model

all: build

build:
	swift build -c release
	cargo build --release

build-universal:
	swift build -c release --arch arm64
	swift build -c release --arch x86_64
	lipo -create \
		.build/arm64-apple-macosx/release/AkazaIME \
		.build/x86_64-apple-macosx/release/AkazaIME \
		-output .build/release/AkazaIME
	rustup target add aarch64-apple-darwin x86_64-apple-darwin
	cargo build --release --target aarch64-apple-darwin
	cargo build --release --target x86_64-apple-darwin
	lipo -create \
		target/aarch64-apple-darwin/release/akaza-server \
		target/x86_64-apple-darwin/release/akaza-server \
		-output target/release/akaza-server

download-model:
	@if [ ! -f "$(MODEL_DIR)/akaza-default-model/unigram.model" ]; then \
		echo "Downloading akaza-default-model $(MODEL_VERSION)..."; \
		mkdir -p $(MODEL_DIR); \
		gh release download $(MODEL_VERSION) \
			--repo akaza-im/akaza \
			--pattern "akaza-default-model.tar.gz" \
			--dir $(MODEL_DIR) --clobber; \
		tar xzf $(MODEL_TARBALL) -C $(MODEL_DIR); \
	else \
		echo "Model already downloaded."; \
	fi

# .app バンドルを out/ に組み立てる（ビルド済みバイナリを使用）
bundle: download-model
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Resources/model
	cp Info.plist $(APP)/Contents/
	cp .build/release/AkazaIME $(APP)/Contents/MacOS/
	cp target/release/akaza-server $(APP)/Contents/MacOS/
	cp -r resources/* $(APP)/Contents/Resources/
	cp $(MODEL_DIR)/akaza-default-model/*.model $(APP)/Contents/Resources/model/
	cp $(MODEL_DIR)/akaza-default-model/*.model.scores $(APP)/Contents/Resources/model/
	cp $(MODEL_DIR)/akaza-default-model/SKK-JISYO.* $(APP)/Contents/Resources/model/

install: build bundle
	rm -rf "$(INSTALL_DIR)/Akaza.app"
	cp -a $(APP) "$(INSTALL_DIR)/"

clean:
	rm -rf .build/ $(OUTDIR)/ target/
