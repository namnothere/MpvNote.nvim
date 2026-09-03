# 📼 MpvNote.nvim

English/[中文](./src/README.md)

A lightweight plugin designed for Neovim users to interact with the mpv media player, allowing you to record and replay video timestamps. Ideal for clip notes, course annotations, segment tagging, and more.

# ✨ Features

📋 Copy Timestamp: Get the current playback path and timestamp from mpv, then copy it to the clipboard in a standard format.

📝 Paste Timestamp: Insert the timestamp as a new line into the current file.

🎬 Open Timestamp: Click on a timestamp to directly launch mpv and jump to that segment.

▶️ Managed mpv: Open media directly from Neovim without manually configuring an mpv IPC socket.

📜 Extract Subtitles: One-click parsing of subtitle files matching the current video filename.

# 🧩 Timestamp Format

The plugin uses a unified timestamp format:

```
["/path/to/video.mp4" ; 192.360]
or
["/path/to/video.mp4" ; (180.123:192.360)]
```

The first field is the video path

The second field is the time (in seconds), precise to three decimal places

# 🚀 Usage

## Start mpv from Neovim

MpvNote can launch and manage its own mpv instance. No `--input-ipc-server` option or `mpv.conf` entry is required:

```vim
:MpvNoteOpen ~/Videos/video.mp4
```

The plugin creates a unique temporary Unix socket for the managed instance and connects to it automatically.

You can also use the Lua API:

```lua
require("MpvNote").open("~/Videos/video.mp4")
```

Each call creates a separate managed mpv instance with its own IPC socket. The most recently opened instance is used by timestamp commands.

## Use an existing mpv instance

For users who already manage mpv themselves, an explicit socket can still be configured:

```lua
opts = {
  socket = "/tmp/mpvsocket",
}
```

In this mode, MpvNote does not launch mpv and communicates with the configured socket instead.

## Configure the plugin

Using Lazy.nvim:

```lua
return {
  "namnothere/MpvNote.nvim",
  lazy = true,
  cmd = { "MpvNoteOpen", "MpvCopyStamp", "MpvPasteStamp", "MpvOpenStamp", "MpvHover" },
  dependencies = "folke/snacks.nvim", -- optional
  opts = {
    -- Optional: omit this to let MpvNote manage mpv automatically.
    -- socket = "/tmp/mpvsocket",
    clipboard_cmd = "wl-copy",
    width = nil,
    height = nil,
  },

  -- set your keybindings below
  vim.keymap.set("n", "<leader>mn", "<cmd>MpvCopyStamp<CR>", { desc = "Copy Mpv Note" }),
  vim.keymap.set("n", "<leader>mp", "<cmd>MpvPasteStamp<CR>", { desc = "Paste Mpv Note" }),
  vim.keymap.set("n", "<leader>mo", "<cmd>MpvOpenStamp<CR>", { desc = "Open Mpv Note" })
}
```

## 1. Available Commands

1. `:MpvNoteOpen <file>`

Launch a new mpv instance with automatic IPC management.

2. `:MpvCopyStamp`

Get the current timestamp from mpv and copy it to the clipboard.

3. `:MpvPasteStamp`

Get the timestamp and insert it as a new line below the current line.

4. `:MpvOpenStamp`

If the cursor is on a properly formatted timestamp, this command will trigger mpv to play the corresponding segment.

If no managed mpv instance is running, it will automatically launch one for the stamped file.

5. `:MpvHover`

Extract current frame with ffmpeg and display with Snacks.nvim.

6. `:MpvTogglePause`

Just toggle pause/play.

7. `:MpvPasteImage`

Paste detected image at the current line with markdown image format.

8. `:MpvGetSrt`

Search for an SRT subtitle file that has the same name as the currently playing video and is located in the same directory, then display it using nvim’s notification system.

9. `:MpvExtractSrt`

Extract the SRT subtitle file that shares the same name as the currently playing video and resides in the same directory, then insert it into the current buffer in the format specified by mpvNote.

10. `MpvNote.mpv_command()`

Allow customize commands using `MpvNote.mpv_command()`. For Example:

```lua
local MpvNote = require("MpvNote")

key.set("n", "<C-l>", function ()
  MpvNote.mpv_command({ command = { "show-text", "HelloWorld" } })
end)
```

# 🛠 Requirements

Make sure the following tools are available:

mpv

socat (for socket communication)

A clipboard tool (like wl-copy, pbcopy, etc.)

ffmpeg (optional, for MpvHover)

folke/snacks.nvim -> image (optional)

The plugin uses the JSON IPC protocol. Managed instances have IPC enabled automatically. If you configure an external socket, ensure your mpv instance supports JSON IPC.

# 📌 Example Workflow

https://github.com/user-attachments/assets/db0b1ec6-065c-4c43-bd24-76317cf7e744

Run `:MpvNoteOpen ~/Videos/video.mp4` to start a managed mpv instance.

Run `:MpvCopyStamp` at the segment you want to mark.

Paste it into your markdown/notes using `:MpvPasteStamp`.

Move the cursor to any timestamp line and replay the clip using `:MpvOpenStamp`.

# 📚 Roadmap

Support for multi-socket / multi-instance management

# 📄 License

MIT License
