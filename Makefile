OUTDIR = out/

all: target/release/mac-akaza

target/release/mac-akaza: src/main.rs src/imk.rs
	cargo build --release

install: target/release/mac-akaza
	mkdir -p $(OUTDIR)/Akaza.app/Contents/MacOS
	mkdir -p $(OUTDIR)/Akaza.app/Contents/Resources
	rm -rf ~/Library/'Input Methods'/Akaza.app
	cp Info.plist $(OUTDIR)/Akaza.app/Contents/
	cp target/release/mac-akaza $(OUTDIR)/Akaza.app/Contents/MacOS
	cp -r resources/* $(OUTDIR)/Akaza.app/Contents/Resources/
	cp -a $(OUTDIR)/Akaza.app ~/Library/'Input Methods'

clean:
	rm -rf target/ $(OUTDIR)/

.PHONY: all clean install

