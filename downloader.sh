#!/bin/sh

RESOURCES_DIR="$1"
BUNDLED_PYTHON="$RESOURCES_DIR/python3/bin/python3.10"
BUNDLED_YT_DLP="$RESOURCES_DIR/yt-dlp"
FFMPEG="$RESOURCES_DIR/ffmpeg"
DENO="$RESOURCES_DIR/deno"

# Set up environment for Deno on OS X 10.9
export DYLD_FORCE_FLAT_NAMESPACE=1
export DYLD_INSERT_LIBRARIES="$RESOURCES_DIR/libWowfunhappyLegacySupport.dylib:$RESOURCES_DIR/libMacportsLegacySupport.dylib"

APP_SUPPORT="$HOME/Library/Application Support/MediaSubscriptions"
ARCHIVES_DIR="$APP_SUPPORT/archives"
CACHE_DIR="$HOME/Library/Caches/MediaSubscriptions"
MOVIES_DIR="$HOME/Movies"
MUSIC_DIR="$HOME/Music"

# Ensure Application Support directory exists
mkdir -p "$APP_SUPPORT"

# Copy yt-dlp to Application Support and use that version
YT_DLP="$APP_SUPPORT/yt-dlp"
cp "$BUNDLED_YT_DLP" "$YT_DLP"

# Update yt-dlp
"$BUNDLED_PYTHON" "$YT_DLP" -U --no-check-certificates

URLS=$(defaults read Wowfunhappy.mediasubscriptions URLs 2>/dev/null | grep "url =" | sed 's/.*url = "\(.*\)";/\1/')

if [ -z "$URLS" ]; then
	echo "No URLs configured"
	exit 0
fi

echo "$URLS" | while IFS= read -r url; do
	if [ -z "$url" ]; then
		continue
	fi
	
	echo "Processing: $url"
	
	ARCHIVE_FILE="$ARCHIVES_DIR/$(echo "$url" | sed 's/[^a-zA-Z0-9]/_/g').txt"
	
	# Download everything to cache directory first
	"$BUNDLED_PYTHON" "$YT_DLP" \
		-f "bestvideo+bestaudio/best" \
		--format-sort "+hdr,res,fps,vcodec:h264,vcodec:vp9.2,vcodec:vp9,vcodec:h265,vcodec:h263,vcodec:vp8,vcodec:theora,vcodec:av1,acodec:aac,acodec:mp4a,acodec:ac3,acodec:opus" \
		--dateafter today-1month \
		--playlist-end 15 \
		--download-archive "$ARCHIVE_FILE" \
		--ignore-errors \
		--retry-sleep 30 \
		--sleep-subtitles 8 \
		--sleep-requests 1.5 \
		--sleep-interval 15 \
		--max-sleep-interval 40 \
		--no-check-certificates \
		--ffmpeg-location "$FFMPEG" \
		--js-runtimes "deno:$DENO" \
		--replace-in-metadata title \' ’ \
		--embed-metadata \
		--embed-thumbnail \
		--all-subs \
		--embed-subs \
		--match-filter "duration>90" \
		--xattrs \
		--mtime \
		--merge-output-format mp4 \
		--compat-options no-live-chat \
		--paths "$CACHE_DIR" \
		-o "%(title)s.%(ext)s" \
		"$url"
done

# After all downloads complete, move files to appropriate folders based on type
if [ -d "$CACHE_DIR" ]; then
	# Move audio files to Music
	find "$CACHE_DIR" -type f \( -name "*.mp3" -o -name "*.m4a" -o -name "*.aac" -o -name "*.opus" -o -name "*.ogg" -o -name "*.wav" -o -name "*.flac" \) -exec mv {} "$MUSIC_DIR/" \;
	
	# Move video files to Movies (excluding temporary and fragment files)
	find "$CACHE_DIR" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" -o -name "*.avi" -o -name "*.mov" \) \
		! -name "*.temp.*" \
		! -name "*.f[0-9]*.*" \
		! -name "*.part" \
		! -name "*.ytdl" \
		-exec mv {} "$MOVIES_DIR/" \;
fi