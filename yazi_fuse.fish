function umount_yazi_fuse
    # check if any yazi instance is still running
    if test -z "$(pgrep yazi)"
        # get mount points
        set fuse_archive_mnt_points (findmnt --output TARGET --noheadings --list /tmp/yazi/fuse-archive/*)
        echo "$fuse_archive_mnt_points" | while read -l mnt_point
            # force unmount.
            fusermount -f "$mnt_point"
        end
    end
end

# trigger function on exit
trap umount_yazi_fuse EXIT
