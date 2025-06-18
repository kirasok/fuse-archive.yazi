# fuse-archive.yazi (Fork)

<!--toc:start-->

- [fuse-archive.yazi](#fuse-archiveyazi)
  - [What news with this fork](#what-news-with-this-fork)
    - [Keep the file mount](#keep-the-file-mount)
    - [Support multiple deep mount](#support-multiple-deep-mount)
  - [Requirements](#requirements)
  - [Installation](#installation)
    - [Dependencies:](#dependencies)
    - [fuse-archive.yazi:](#fuse-archiveyazi)
    - [Options](#options)
  - [Usage](#usage)
  <!--toc:end-->

<!--toc:start-->

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

[fuse-archive.yazi](https://github.com/boydaihungst/fuse-archive.yazi) supports mounting the following file extensions: [SUPPORTED ARCHIVE FORMATS](https://github.com/google/fuse-archive?tab=readme-ov-file#archive-formats)

## What news with this fork

> [!IMPORTANT]
> Minimum version: yazi v25.5.31.
>
> Password-protected RAR file is not supported yet!

### Keep the file mount

By using `plugin fuse-archive -- leave`. So you can copy and paste
the content to other place without open a new tab

### Support multiple deep mount

That mean, if you have a file like below,
just use the `plugin fuse-archive -- mount` to go deeper inside
and `plugin fuse-archive -- leave` to go back. Even if the files inside are password-protected,
it will still prompt you to enter a password. You only need to enter the password once for each file.

- Origin file.zip
  - Child_1.zip
    - Grandchild_1.zip
  - Child_2.zip (with password)
    - Grandchild_2.zip (with another password)
      - GranGrandchild_3.zip (with another password)

## Requirements

1. [yazi](https://github.com/sxyazi/yazi).

2. This plugin only supports Linux, and requires having
   [fuse-archive](https://github.com/google/fuse-archive), [xxHash](https://github.com/Cyan4973/xxHash) and `fuse3`
   installed. This fork requires you to build and install fuse-archive with latest
   source from github (because the latest release is too old, 2020).

## Installation

### Dependencies:

- For Ubuntu:

  Use `libfuse3-dev` instead of `libfuse-dev` if you are using Ubuntu 22.04 or later.

  - libfuse-dev: This is for FUSE 2.x, the older version.
  - libfuse3-dev: This is for FUSE 3.x, the newer and actively developed version.
    which is recommended by fuse-archive's author.

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
ya pkg add boydaihungst/fuse-archive
```

Modify your `~/.config/yazi/init.lua` to include:

```lua
require("fuse-archive"):setup()
```

Install this shell script if you want yazi auto un-mount all mounted archives after closed the `last`
yazi instance:

- For `fish` shell: add this command to `~/.config/fish/config.fish` file:

  ```fish
  test -f ~/.config/yazi/plugins/fuse-archive.yazi/assets/yazi_fuse.fish; and source ~/.config/yazi/plugins/fuse-archive.yazi/assets/yazi_fuse.fish
  ```

- For `bash` shell: add this command to `~/.bashrc` file:

  ```sh
  [[ -f ~/.config/yazi/plugins/fuse-archive.yazi/assets/yazi_fuse.sh ]] && . ~/.config/yazi/plugins/fuse-archive.yazi/assets/yazi_fuse.sh
  ```

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
[mgr]
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

1. `/tmp/yazi/fuse-archive/...`
