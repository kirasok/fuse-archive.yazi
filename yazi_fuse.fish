function umount_yazi_fuse
    # check if any yazi instance is still running
    if test -z "$(pgrep yazi)"
        # get mount points
        set fuse_archive_mnt_points (findmnt --output TARGET --noheadings --list | grep "^/tmp/yazi/fuse-archive" | sort -r)
        for mnt_point in $fuse_archive_mnt_points
            # force unmount.
            fusermount -u "$mnt_point"
        end
    end
end

# trigger function on exit
trap umount_yazi_fuse EXIT
