BUILDDIR=$(CURDIR)/embuild
OUTPUTDIR=$(CURDIR)/output
MAKEFILESDIR=$(CURDIR)/makefiles
FSDIR=$(OUTPUTDIR)/fs
WASMDIR=$(OUTPUTDIR)/wasm

FILE_PACKAGER=python3 $(EMSDK)/upstream/emscripten/tools/file_packager.py
ALLTARGETS=sdcc zmac

.PHONY: clean clobber prepare $(ALLTARGETS)

all: $(ALLTARGETS)

prepare:
	mkdir -p $(OUTDIR) $(BUILDDIR) $(OUTPUTDIR) $(FSDIR) $(WASMDIR)
	@emcc --version || { echo 'Emscripten not found. Install https://github.com/emscripten-core/emsdk first.'; exit 1; }

clean:
	rm -fr $(BUILDDIR)
	rm -fr $(OUTPUTDIR)

clobber: clean
	git submodule foreach --recursive git clean -xfd

copy.%: prepare
	echo "Copying $* to $(BUILDDIR)"
	mkdir -p $(BUILDDIR)/$*
	cd $* && git archive HEAD | tar x -C $(BUILDDIR)/$*

$(FSDIR)/fs%.js: $(BUILDDIR)/%/fsroot
	cd $< && $(FILE_PACKAGER) \
		$(FSDIR)/fs$*.data \
		--preload * \
		--separate-metadata \
		--js-output=$@

%.js: %
	sed -r 's/(return \w+)[.]ready/\1;\/\/.ready/' < $< > $@

%.wasm: %.js
	cp $*.wasm $*.js $(WASMDIR)/
	#node -e "require('$*.js')().then((m)=>{m.callMain(['--help'])})" 2> $*.stderr 1> $*.stdout
	-node -e "require('$*.js')({arguments:['--help']})" 2> $*.stderr 1> $*.stdout

EMCC_FLAGS= -Os \
	--memory-init-file 0 \
	-s MODULARIZE=1 \
	-s 'EXPORTED_RUNTIME_METHODS=[\"FS\",\"callMain\"]' \
	-s FORCE_FILESYSTEM=1 \
	-s ALLOW_MEMORY_GROWTH=1 \
	-lworkerfs.js

### sdcc

SDCC_CONFIG=\
  --disable-mcs51-port   \
  --enable-z80-port      \
  --enable-z180-port     \
  --disable-r2k-port     \
  --disable-r3ka-port    \
  --enable-gbz80-port    \
  --disable-tlcs90-port  \
  --enable-ez80_z80-port \
  --disable-ds390-port   \
  --disable-ds400-port   \
  --disable-pic14-port   \
  --disable-pic16-port   \
  --disable-hc08-port    \
  --disable-s08-port     \
  --disable-stm8-port    \
  --disable-pdk13-port   \
  --disable-pdk14-port   \
  --disable-pdk15-port   \
  --disable-pdk16-port   \
  --enable-mos6502-port    \
  --enable-non-free      \
  --disable-doc          \
  --disable-libgc        

SDCC_EMCC_CONFIG=--disable-ucsim --disable-device-lib --disable-packihx --disable-sdcpp --disable-sdcdb --disable-sdbinutils

SDCC_FLAGS= \
	-s USE_BOOST_HEADERS=1 \
	-s ERROR_ON_UNDEFINED_SYMBOLS=0

sdcc.build:
	cd sdcc/sdcc && ./configure $(SDCC_CONFIG) && make
	cd $(BUILDDIR)/sdcc/sdcc/support/sdbinutils && ./configure && make
	cp -rp sdcc/sdcc/bin/makebin $(BUILDDIR)/sdcc/sdcc/bin/
	cd $(BUILDDIR)/sdcc/sdcc && emconfigure ./configure $(SDCC_CONFIG) $(SDCC_EMCC_CONFIG) EMCC_FLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS)"
	sed -i 's/#define HAVE_BACKTRACE_SYMBOLS_FD 1//g' $(BUILDDIR)/sdcc/sdcc/sdccconf.h
	# can't generate multiple modules w/ different export names
	cd $(BUILDDIR)/sdcc/sdcc/src && emmake make EMCC_FLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS) -s EXPORT_NAME=sdcc" LDFLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS) -s EXPORT_NAME=sdcc"
	#cp $(BUILDDIR)/sdcc/sdcc/bin/sdcc* $(WASMDIR)

sdcc.asm:
	cd $(BUILDDIR)/sdcc/sdcc/sdas/as6500 && emmake make EMCC_FLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS) -s EXPORT_NAME=sdas6500" LDFLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS) -s EXPORT_NAME=sdas6500"

sdcc.fsroot:
	rm -fr $(BUILDDIR)/sdcc/fsroot
	mkdir -p $(BUILDDIR)/sdcc/fsroot
	ln -s $(CURDIR)/sdcc/sdcc/device/include $(BUILDDIR)/sdcc/fsroot/include
	ln -s $(CURDIR)/sdcc/sdcc/device/lib/build $(BUILDDIR)/sdcc/fsroot/lib

sdcc: prepare copy.sdcc sdcc.build sdcc.asm sdcc.fsroot \
	$(FSDIR)/fssdcc.js \
	$(BUILDDIR)/sdcc/sdcc/bin/sdcc.wasm \
	$(BUILDDIR)/sdcc/sdcc/bin/sdas6500.wasm
	$(EMSDK)/upstream/bin/wasm-opt --strip -Oz $(BUILDDIR)/sdcc/sdcc/bin/sdcc.wasm -o $(WASMDIR)/sdcc.wasm

### zmac

zmac.wasm: copy.zmac
	cd $(BUILDDIR)/zmac && emmake make EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=zmac"

zmac: zmac.wasm $(BUILDDIR)/zmac/zmac.wasm
