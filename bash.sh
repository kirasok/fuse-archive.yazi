#!/usr/bin/env bash

umount_yazi_fuse() {
  # check if any yazi instance is still running
  if [ -z "$(pgrep yazi)" ]; then
    # get mount points
    fuse_archive_mnt_points=$(findmnt --output TARGET --noheadings --list /tmp/yazi/fuse-archive/*)
    echo "$fuse_archive_mnt_points" | while read -r mnt_point; do
      # force unmount
      fusermount -f "$mnt_point"
    done
  fi
}

# trigger function on exit
trap umount_yazi_fuse EXIT
