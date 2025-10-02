#!/system/bin/sh

SOURCE_DIR="/storage/emulated/0/Download/1DMP/Videos"
DEST_BASE="/storage/emulated/0/Aniyomi/downloads"
LOG_FILE="/storage/emulated/0/video_organizer.log"
VIDEO_INDEX="/storage/emulated/0/video_index.tmp"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_message() {
    printf '%s - %b\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
    printf '%b\n' "$1"
}

normalize_string() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Function to extract anime name and episode from video filename
parse_video_filename() {
    filename="$1"
    basefile=$(basename "$filename")
    basename_noext=${basefile%.*}

    case "$basename_noext" in
        *" - "*)
            anime_name=${basename_noext%% - *}
            episode_info=${basename_noext#* - }
            printf 'ANIME:%s|EPISODE:%s\n' "$anime_name" "$episode_info"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Build optimized video index
build_video_index() {
    log_message "${CYAN}Building video index...${NC}"
    
    > "$VIDEO_INDEX"
    temp_count_file="/storage/emulated/0/temp_count.tmp"
    echo "0" > "$temp_count_file"
    
    find "$SOURCE_DIR" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.wmv" -o -iname "*.flv" -o -iname "*.webm" \) | while IFS= read -r video_file; do
        
        parse_result=$(parse_video_filename "$video_file")
        
        if [ $? -eq 0 ]; then
            video_anime=$(printf '%s' "$parse_result" | cut -d'|' -f1 | cut -d':' -f2-)
            video_episode=$(printf '%s' "$parse_result" | cut -d'|' -f2 | cut -d':' -f2-)
            
            # Create search key
            norm_anime=$(normalize_string "$video_anime")
            norm_episode=$(normalize_string "$video_episode")
            search_key="${norm_anime}::${norm_episode}"
            
            # Store in index
            printf '%s|%s\n' "$search_key" "$video_file" >> "$VIDEO_INDEX"
            
            current_count=$(cat "$temp_count_file")
            new_count=$((current_count + 1))
            echo "$new_count" > "$temp_count_file"
        fi
    done
    
    final_count=$(cat "$temp_count_file")
    rm -f "$temp_count_file"
    
    log_message "${CYAN}Index complete: $final_count videos found${NC}"
    
    if [ "$final_count" -eq 0 ]; then
        log_message "${YELLOW}Warning: No parseable video files found in source directory${NC}"
        log_message "${YELLOW}Make sure filenames follow 'Anime Name - Episode Info' format${NC}"
    fi
}

# Fast lookup function
find_matching_video_fast() {
    target_anime="$1"
    target_episode="$2"
    
    norm_target_anime=$(normalize_string "$target_anime")
    norm_target_episode=$(normalize_string "$target_episode")
    search_key="${norm_target_anime}::${norm_target_episode}"
    
    result=$(grep "^${search_key}|" "$VIDEO_INDEX" 2>/dev/null | head -1 | cut -d'|' -f2)
    
    if [ -n "$result" ]; then
        printf '%s\n' "$result"
        return 0
    else
        return 1
    fi
}

# Move video file preserving original name
move_video_only() {
    source_file="$1"
    dest_dir="$2"
    
    filename=$(basename "$source_file")
    dest_file="$dest_dir/$filename"
    
    # Validation checks
    if [ ! -f "$source_file" ] || [ ! -r "$source_file" ] || [ ! -d "$dest_dir" ] || [ ! -w "$dest_dir" ]; then
        log_message "${RED}Error: File access issue - $filename${NC}"
        return 1
    fi
    
    # Handle existing files
    if [ -f "$dest_file" ]; then
        timestamp=$(date '+%Y%m%d_%H%M%S')
        name_without_ext="${filename%.*}"
        extension="${filename##*.}"
        backup_name="${name_without_ext}_backup_${timestamp}.${extension}"
        backup_path="$dest_dir/$backup_name"
        
        if ! mv "$dest_file" "$backup_path" 2>/dev/null; then
            log_message "${RED}Error: Cannot backup existing file - $filename${NC}"
            return 1
        fi
        log_message "${YELLOW}Backed up existing: $(basename "$backup_name")${NC}"
    fi
    
    # Move file
    if mv "$source_file" "$dest_file" 2>/dev/null; then
        return 0
    else
        log_message "${RED}Error: Move failed - $filename${NC}"
        return 1
    fi
}

main() {
    log_message "${BLUE}=== Video File Organizer Started ===${NC}"

    # Validate directories
    if [ ! -d "$SOURCE_DIR" ]; then
        log_message "${RED}Error: Source directory not found: $SOURCE_DIR${NC}"
        exit 1
    fi

    if [ ! -d "$DEST_BASE" ]; then
        log_message "${RED}Error: Destination directory not found: $DEST_BASE${NC}"
        exit 1
    fi

    # Build index
    build_video_index

    # Initialize counters
    total_dirs=0
    matched_dirs=0
    moved_videos=0
    error_moves=0
    skipped_dirs=0

    # Process directories
    for ext_dir in "$DEST_BASE"/*; do
        [ ! -d "$ext_dir" ] && continue

        ext_name=$(basename "$ext_dir")
        
        # Skip non-anime extensions
        case "$ext_name" in
            *Manga*|*manga*) continue ;;
        esac
        
        log_message "${YELLOW}Processing: $ext_name${NC}"

        for anime_dir in "$ext_dir"/*; do
            [ ! -d "$anime_dir" ] && continue

            anime_name=$(basename "$anime_dir")

            for episode_dir in "$anime_dir"/*; do
                [ ! -d "$episode_dir" ] && continue

                episode_name=$(basename "$episode_dir")
                total_dirs=$((total_dirs + 1))

                # Check for existing videos
                video_found=0
                for video_pattern in "$episode_dir"/*.mp4 "$episode_dir"/*.mkv "$episode_dir"/*.avi "$episode_dir"/*.mov "$episode_dir"/*.wmv "$episode_dir"/*.flv "$episode_dir"/*.webm; do
                    if [ -f "$video_pattern" ]; then
                        video_found=1
                        skipped_dirs=$((skipped_dirs + 1))
                        break
                    fi
                done

                [ $video_found -eq 1 ] && continue

                # Find matching video
                matching_video=$(find_matching_video_fast "$anime_name" "$episode_name")
                
                if [ -n "$matching_video" ]; then
                    matched_dirs=$((matched_dirs + 1))
                    
                    if move_video_only "$matching_video" "$episode_dir"; then
                        moved_videos=$((moved_videos + 1))
                        log_message "${GREEN}  ✓ $(basename "$matching_video") → $anime_name/$episode_name${NC}"
                    else
                        error_moves=$((error_moves + 1))
                    fi
                else
                    # Only log if we expected a match (for troubleshooting)
                    if [ "$matched_dirs" -gt 0 ] || [ "$moved_videos" -gt 0 ]; then
                        log_message "${YELLOW}  ? No video found for: $anime_name - $episode_name${NC}"
                    fi
                fi
            done
        done
    done

    # Summary
    log_message "${BLUE}=== Processing Complete ===${NC}"
    log_message "${CYAN}Episode directories scanned: $total_dirs${NC}"
    log_message "${CYAN}Already had videos: $skipped_dirs${NC}"
    log_message "${GREEN}Videos successfully moved: $moved_videos${NC}"
    
    if [ $error_moves -gt 0 ]; then
        log_message "${RED}Move errors: $error_moves${NC}"
    fi
    
    empty_dirs=$((total_dirs - skipped_dirs - moved_videos - error_moves))
    if [ $empty_dirs -gt 0 ]; then
        log_message "${YELLOW}No matching videos found: $empty_dirs directories${NC}"
    fi
    
    # Clean up
    rm -f "$VIDEO_INDEX"
    
    if [ $moved_videos -gt 0 ]; then
        log_message "${GREEN}Success: $moved_videos videos organized!${NC}"
    elif [ $skipped_dirs -eq $total_dirs ]; then
        log_message "${CYAN}All directories already contain videos${NC}"
    else
        log_message "${YELLOW}No videos were moved - check source directory and filename formats${NC}"
    fi
}

main

printf 'Script completed. Full log: %s\n' "$LOG_FILE"