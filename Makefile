OUTDIR = out/
APP = $(OUTDIR)/Akaza.app
INSTALL_DIR = $(HOME)/Library/Input Methods
MODEL_VERSION = v2026.220.3
MODEL_DIR = $(OUTDIR)/model/$(MODEL_VERSION)
MODEL_TARBALL = $(MODEL_DIR)/akaza-default-model.tar.gz

.PHONY: all build install clean download-model

all: build

build:
	swift build -c release
	cargo build --release

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

install: build download-model
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Resources/model
	rm -rf "$(INSTALL_DIR)/Akaza.app"
	cp Info.plist $(APP)/Contents/
	cp .build/release/AkazaIME $(APP)/Contents/MacOS/
	cp target/release/akaza-server $(APP)/Contents/MacOS/
	cp -r resources/* $(APP)/Contents/Resources/
	cp $(MODEL_DIR)/akaza-default-model/*.model $(APP)/Contents/Resources/model/
	cp $(MODEL_DIR)/akaza-default-model/SKK-JISYO.* $(APP)/Contents/Resources/model/
	cp -a $(APP) "$(INSTALL_DIR)/"

clean:
	rm -rf .build/ $(OUTDIR)/ target/
