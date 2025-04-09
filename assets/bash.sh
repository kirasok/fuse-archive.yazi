#!/usr/bin/env bash

umount_yazi_fuse() {
  # check if any yazi instance is still running
  if [ -z "$(pgrep yazi)" ]; then
    # get mount points
    fuse_archive_mnt_points=$(findmnt --output TARGET --noheadings --list | grep "^/tmp/yazi/fuse-archive" | sort -r)
    # Loop through each mount point and force unmount
    while IFS= read -r mnt_point; do
      fusermount -u "$mnt_point"
    done <<<"$fuse_archive_mnt_points"
  fi
}

# trigger function on exit
trap umount_yazi_fuse EXIT HUP INT QUIT ABRT TERM
