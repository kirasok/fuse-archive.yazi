# fuse-archive.yazi

<!--toc:start-->

- [fuse-archive.yazi](#fuse-archiveyazi)
  - [What news with this fork](#what-news-with-this-fork)
    - [Keep the file mount](#keep-the-file-mount)
    - [Support multiple deep mount](#support-multiple-deep-mount)
  - [Requirements](#requirements)
  - [Installation](#installation)
    - [Options](#options)
  - [Usage](#usage)
  <!--toc:end-->

[fuse-archive.yazi](https://github.com/dawsers/fuse-archive.yazi)
uses [fuse-archive](https://github.com/google/fuse-archive) to
transparently mount and unmount archives in read-only mode, allowing you to
navigate inside, view, and extract individual or groups of files.

There is another plugin on which this one is based,
[archivemount.yazi](https://github.com/AnirudhG07/archivemount.yazi). It
mounts archives with read and and write permissions. The main problem is it uses
[archivemount](https://github.com/cybernoid/archivemount) which is much slower
than [fuse-archive](https://github.com/google/fuse-archive).
It also supports very few file types compared to this plugin, and you need to
mount and unmount the archives manually.

[fuse-archive.yazi](https://github.com/dawsers/fuse-archive.yazi) supports
mounting the following file extensions: `.zip`, `.gz`, `.bz2`, `.tar`, `.tgz`,
`.tbz2`, `.txz`, `.xz`, `.tzs`, `.zst`, `.iso`, `.rar`, `.7z`, `.cpio`, `.lz`,
`.lzma`, `.shar`, `.a`, `.ar`, `.apk`, `.jar`, `.xpi`, `.cab`.

## What news with this fork

### Keep the file mount

By using `plugin fuse-archive --args=leave`. So you can copy and paste
the content to other place without open a new tab

### Support multiple deep mount

That mean, if you have a file like below,
just use the `plugin fuse-archive --args=mount` to go deeper inside
and `plugin fuse-archive --args=leave` to go back. Even if the file inside have
password, it'll still asking for the first time you open.

- Origin file.zip
  - Child_1.zip
    - Grandchild_1.zip

## Requirements

1. A relatively modern (>= 0.3) version of
   [yazi](https://github.com/sxyazi/yazi).

2. This plugin only supports Linux, and requires having
   [fuse-archive](https://github.com/google/fuse-archive) and [xxHash](https://github.com/Cyan4973/xxHash)
   installed. This fork requires you to build and install fuse-archive with latest
   source from github (because the latest release is too old, 2020).

```sh
git clone https://github.com/google/fuse-archive
cd "fuse-archive"
make install
```

## Installation

```sh
ya pack -a dawsers/fuse-archive
```

Modify your `~/.config/yazi/init.lua` to include:

```lua
require("fuse-archive"):setup()
```

Install this if you want yazi un-mount all archive files after `exit` the `last`
yazi instance:

- If you use `fish` shell, then copy `yazi_fuse.fish` file to `~/.config/fish/functions`.
  e.g. `~/.config/fish/functions/yazi_fuse.fish`

- If you use `bash` shell, then copy the content of `bash.sh` file to this file `~/.bashrc`

### Options

The plugin supports the following options, which can be assigned during setup:

1. `smart_enter`: If `true`, when _entering_ a file it will be _opened_, while
   directories will always be _entered_. The default value is `false`.

```lua
require("fuse-archive"):setup({
  smart_enter = true,
})
```

## Usage

The plugin works transparently, so for the best effect, remap your navigation
keys assigned to `enter` and `leave` to the plugin. This way you will be able
to "navigate" compressed archives as if they were part of the file system.

When you _enter_ an archive, the plugin mounts it and takes you to the mounted
directory, and when you _leave_, it unmounts the archive and takes you back to
the original location of the archive.

Add this to your `~/.config/yazi/keymap.toml`:

```toml
[manager]
prepend_keymap = [
    { on   = [ "<Right>" ], run = "plugin fuse-archive --args=mount", desc = "Enter or Mount selected archive" },
    { on   = [ "<Left>" ], run = "plugin fuse-archive --args=unmount", desc = "Leave or Unmount selected archive" },
]
```

> BREAKING CHANGE from this fork: `plugin fuse-archive --args=unmount` in
> keymap.toml should changed to `plugin fuse-archive --args=leave`
> to make multiple deep mount work. the
> `unmount` still there if you want to unmount after leave the folder
> (this won't let you copy/move files/folders to other place without create another
> tab). But the downside of `leave` command is that the zip file won't unmount
> itself after exit yazi. Maybe use another shellscript with `trap EXIT` `uuidgen`
> and `umount` could solve this problem. I'll take a look at it later

When the current file is not a supported archive type, the plugin simply calls
_enter_, and when there is nothing to unmount, it calls _leave_, so it works
transparently.

In case you run into any problems and need to unmount something manually, or
delete any temporary directories, the location of the mounts is one of the
following three in order of preference:

1. ~~`$XDG_STATE_HOME/yazi/fuse-archive/...`~~
2. ~~`$HOME/.local/state/yazi/fuse-archive/...`~~
3. `/tmp/yazi/fuse-archive/...`
