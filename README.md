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

[fuse-archive.yazi](https://github.com/boydaihungst/fuse-archive.yazi)
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

[fuse-archive.yazi](https://github.com/boydaihungst/fuse-archive.yazi) supports
mounting the following file extensions: `.zip`, `.gz`, `.bz2`, `.tar`, `.tgz`,
`.tbz2`, `.txz`, `.xz`, `.tzs`, `.zst`, `.iso`, `.rar`, `.7z`, `.cpio`, `.lz`,
`.lzma`, `.shar`, `.a`, `.ar`, `.apk`, `.jar`, `.xpi`, `.cab`.

## What news with this fork

> [!IMPORTANT]
> Minimum version: yazi v25.2.7

### Keep the file mount

By using `plugin fuse-archive -- leave`. So you can copy and paste
the content to other place without open a new tab

### Support multiple deep mount

That mean, if you have a file like below,
just use the `plugin fuse-archive -- mount` to go deeper inside
and `plugin fuse-archive -- leave` to go back. Even if the file inside have
password, it'll still asking for the first time you open.

- Origin file.zip
  - Child_1.zip
    - Grandchild_1.zip

## Requirements

1. A relatively modern (>= 25.2.7) version of
   [yazi](https://github.com/sxyazi/yazi).

2. This plugin only supports Linux, and requires having
   [fuse-archive](https://github.com/google/fuse-archive), [xxHash](https://github.com/Cyan4973/xxHash) and `fuse3`
   installed. This fork requires you to build and install fuse-archive with latest
   source from github (because the latest release is too old, 2020).

## Installation

### Dependencies:

- For Ubuntu:

  ```sh
  sudo apt install git cmake g++ pkg-config libfuse3-dev libarchive-dev libboost-all-dev xxhash fuse3
  git clone https://github.com/google/fuse-archive
  cd "fuse-archive"
  sudo make install
  ```

- For Arch based:

  ```sh
  yay -S xxhash fuse3 fuse-archive
  # or: paru -S xxhash fuse3 fuse-archive

  # Or: install fuse-archive from source:
  # git clone https://github.com/google/fuse-archive
  # cd "fuse-archive"
  # sudo make install
  ```

- For other distros, it's better to use ChatGPT for dependencies. Prompt: `install fuse-archive YOUR_DISTRO_NAME`.

### fuse-archive.yazi:

```sh
ya pack -a boydaihungst/fuse-archive
```

Modify your `~/.config/yazi/init.lua` to include:

```lua
require("fuse-archive"):setup()
```

Install this shell script if you want yazi auto un-mount all mounted archives after `exit` the `last`
yazi instance:

Both yazi_fuse.fish and bash.sh are in the `yazi/plugins/fuse-archive.yazi/assets/` directory.

- For `fish` shell: copy [assets/yazi_fuse.fish](./assets/yazi_fuse.fish) file to `~/.config/fish/conf.d/`.
  e.g. `~/.config/fish/conf.d/yazi_fuse.fish`

- For `bash` shell: copy the content of [assets/bash.sh](./assets/bash.sh) file to `~/.bashrc` file.

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
    { on   = [ "<Right>" ], run = "plugin fuse-archive -- mount", desc = "Enter or Mount selected archive" },
    { on   = [ "<Left>" ], run = "plugin fuse-archive -- leave", desc = "Leave selected archive without unmount it" },
    { on   = [ "l" ], run = "plugin fuse-archive -- mount", desc = "Enter or Mount selected archive" },
    { on   = [ "h" ], run = "plugin fuse-archive -- leave", desc = "Leave selected archive without unmount it" },
]
```

> [!IMPORTANT]
> BREAKING CHANGE from this fork: `plugin fuse-archive -- unmount` in
> keymap.toml should changed to `plugin fuse-archive -- leave`
> to make multiple deep mount work. the
> `unmount` still there if you want to unmount after leave the folder
> (this won't let you copy/move files/folders to other place without create another
> tab). But the downside of `leave` command is that the zip file won't unmount
> itself after exit yazi, unless you use the fish or bash script which is mentioned in the #installation section.

When the current file is not a supported archive type, the plugin simply calls
_enter_, and when there is nothing to unmount, it calls _leave_, so it works
transparently.

In case you run into any problems and need to unmount something manually, or
delete any temporary directories, the location of the mounts is one of the
following three in order of preference:

1. ~~`$XDG_STATE_HOME/yazi/fuse-archive/...`~~
2. ~~`$HOME/.local/state/yazi/fuse-archive/...`~~
3. `/tmp/yazi/fuse-archive/...`
