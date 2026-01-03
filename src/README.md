# 📼 MpvNote.nvim

[English](../README.md)/中文

一个为 Neovim 用户设计的小型插件，用于与 mpv 播放器交互，记录并回放视频时间戳。适用于剪辑笔记、课程记录、片段标注等场景。

# ✨ 插件功能

📋 复制时间戳：从 mpv 获取当前播放路径与时间戳，并复制为标准格式到剪贴板

📝 粘贴时间戳：将时间戳插入当前文件为新的一行

🎬 打开时间戳：点击时间戳可直接唤起 mpv 跳转播放该片段

📜 提取字幕：一键解析当前视频同名字幕文件

# 🧩 时间戳格式

插件使用统一的时间戳格式：

```
["/path/to/video.mp4" ; 192.360]
或
["/path/to/video.mp4" ; (180.123:192.360)]
```

第一个字段为视频路径

第二个字段为时间（秒），保留三位小数

# 🚀 使用方式

## 1. 启动 mpv 并启用 socket 控制

`mpv --input-ipc-server=/path/to/your/socket_file "/path/to/your/video"`

或者在 `mpv.conf` 中设置 `input-ipc-server=/path/to/your/socket_file`

`socket_file` 默认为 `/tmp/mpvsocket`

## 2. 配置插件

使用 Lazy.nvim

```lua
return {
  "SilverofLight/MpvNote.nvim",
  lazy = true,
  cmd = { "MpvCopyStamp", "MpvPasteStamp", "MpvOpenStamp", "MpvHover" },
  dependencies = "folke/snacks.nvim", -- optional
  opts = {
    socket = "/tmp/mpvsocket", -- your socket file
    clipboard_cmd = "wl-copy", -- your clipboard tool command
    width = nil,
    height = nil, -- MpvHover's size
  },

  -- set your keybindings below
  vim.keymap.set("n", "<leader>mn", "<cmd>MpvCopyStamp<CR>", { desc = "Copy Mpv Note" }),
  vim.keymap.set("n", "<leader>mp", "<cmd>MpvPasteStamp<CR>", { desc = "Paste Mpv Note" }),
  vim.keymap.set("n", "<leader>mo", "<cmd>MpvOpenStamp<CR>", { desc = "Open Mpv Note" })
}
```

## 3. 提供的命令

1. `:MpvCopyStamp`

从 mpv 获取当前时间戳并复制到剪贴板

2. `:MpvPasteStamp`

从 mpv 获取时间戳并插入为当前行下的一行

3. `:MpvOpenStamp`

如果光标所在行为标准格式的时间戳，会调用 mpv 播放对应位置

若 mpv 没有运行，将自动以后台方式启动并跳转播放

4. `:MpvHover`

使用 Snacks.nvim 和 ffmpeg 提取并显示当前帧

5. `:MpvTogglePause`

暂停和开始播放

6. `:MpvPasteImage`

在这一行使用 markdown image 格式粘贴生成的图片。

7. `:MpvGteSrt`

搜索与当前播放视频同目录下的同名 srt 字幕文件，并使用 nvim 的通知显示。

8. `:MpvExtractSrt`

提取与当前播放视频同目录下的同名 srt 字幕文件，并按照 mpvNote 规定的格式添加到当前 buffer 中。

9. `MpvNote.mpv_command()`

使用 `MpvNote.mpv_command()` 自定义命令。例如：

```lua
local MpvNote = require("MpvNote")

key.set("n", "<C-l>", function ()
  MpvNote.mpv_command({ command = { "show-text", "HelloWorld" } })
end)
```

# 🛠 注意事项

插件依赖以下命令可用：

mpv（需开启 --input-ipc-server）

socat（用于 socket 通信）

剪贴板工具（如 wl-copy、pbcopy 等）

ffmpeg (可选, 用于 MpvHover)

folke/snacks.nvim -> image (可选，用于 MpvHover)

插件使用 JSON 通信协议，确保 mpv 版本支持 IPC。

# 📌 示例使用流程

https://github.com/user-attachments/assets/db0b1ec6-065c-4c43-bd24-76317cf7e744

在想记录的片段，运行 `:MpvCopyStamp`

粘贴到 markdown/笔记中 `:MpvPasteStamp`

随时光标移动到某行，使用 `:MpvOpenStamp` 回放该片段

# 📚 未来计划

支持多 socket / 多实例管理

# 📄 License

MIT License
