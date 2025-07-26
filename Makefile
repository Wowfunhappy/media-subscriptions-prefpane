# MediaSubscriptions Preference Pane Makefile for OS X 10.9

# Compiler and flags
CC = clang
OBJC = clang
FRAMEWORKS = -framework Cocoa -framework PreferencePanes
CFLAGS = -mmacosx-version-min=10.9 -fobjc-arc
LDFLAGS = $(FRAMEWORKS)

# Target and source files
TARGET = MediaSubscriptions
SOURCES = MediaSubscriptionsPane.m
OBJECTS = $(SOURCES:.m=.o)

# Bundle structure
BUNDLE = $(TARGET).prefPane
BUNDLE_CONTENTS = $(BUNDLE)/Contents
BUNDLE_MACOS = $(BUNDLE_CONTENTS)/MacOS
BUNDLE_RESOURCES = $(BUNDLE_CONTENTS)/Resources

# Version (automatically set to current date)
VERSION = $(shell date +%Y.%m.%d)

# Build rules
all: bundle

bundle: $(BUNDLE_MACOS)/$(TARGET) $(BUNDLE_CONTENTS)/Info.plist resources

$(BUNDLE_MACOS)/$(TARGET): $(OBJECTS)
	@mkdir -p $(BUNDLE_MACOS)
	$(OBJC) $(CFLAGS) $(LDFLAGS) -bundle -o $@ $^

%.o: %.m
	$(OBJC) $(CFLAGS) -c $< -o $@

$(BUNDLE_CONTENTS)/Info.plist: Info.plist
	@mkdir -p $(BUNDLE_CONTENTS)
	sed -e 's/<string>1.0<\/string>/<string>$(VERSION)<\/string>/g' Info.plist > $(BUNDLE_CONTENTS)/Info.plist

resources:
	@mkdir -p $(BUNDLE_RESOURCES)
	cp Deps/yt-dlp $(BUNDLE_RESOURCES)/
	cp Deps/ffmpeg $(BUNDLE_RESOURCES)/
	chmod +x $(BUNDLE_RESOURCES)/yt-dlp
	chmod +x $(BUNDLE_RESOURCES)/ffmpeg
	cp downloader.sh $(BUNDLE_RESOURCES)/
	chmod +x $(BUNDLE_RESOURCES)/downloader.sh
	cp icon.png $(BUNDLE_RESOURCES)/

install-user: bundle
	cp -R $(BUNDLE) ~/Library/PreferencePanes/

install-system: bundle
	sudo cp -R $(BUNDLE) /Library/PreferencePanes/

clean:
	rm -rf $(BUNDLE) *.o

.PHONY: all bundle resources install-user install-system clean