#!/bin/bash

# Session name
SESSION="nextcloud-mount"

# Check if the tmux session already exists
if tmux HAS-SESSION -t "$SESSION" 2>/dev/null; then
  echo "Mount session '$SESSION' is already running."
  exit 0
fi

echo 'Starting Nextcloud mount in tmux session...'

# Create a detached session (-d) named nextcloud-mount (-s) and run rclone
# Note: No trailing '&' needed since tmux manages the backgrounding
tmux new-session -d -s "$SESSION" \
  "rclone mount portal: ~/portal --vfs-cache-mode full --vfs-cache-max-size 10G --dir-cache-time 1m"

echo "Mounted in tmux session '$SESSION'."
echo "You can close this terminal. To view logs later, run: tmux attach -t $SESSION"
