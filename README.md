# ai-chat
AI chat script for linux shell

用于 Linux 的 AI 对话脚本

### 支持的功能列表如下
  - 自定义兼容 OpenAI 规范的 API 和 KEY，默认为硅基流动 API
  - 自定义模型，默认为 DeepSeek-V3.2
  - 自定义温度，默认为 0.75
  - 自定义系统提示词
  - 中文输入和输出
  - 管道符输入
  - 流式输出和非流式输出
  - 交互式聊天界面和命令行调用两种方式
  - 历史聊天记录保存和清理
  - 可自定义对话轮数实现多轮对话，默认 10 轮对话，自动清除超出轮数的对话记录
  - 非流式输出和查看历史对话时支持 Markdown 渲染，需要安装依赖 `glow`
  - 配置完成之后无需 root 权限亦可使用

### 使用方法
1. 下载 `ai-chat.sh` 脚本到 Linux 设备上
2. 将 `ai-chat.sh` 命名为 `ai-chat`
3. 将 `ai-chat` 放到 `/usr/bin` 目录下
4. 执行命令 `chmod +x /usr/bin/ai-chat`
5. 安装必要的依赖 `curl` 和 `jq`，用包管理器安装即可，推荐安装 [glow](https://github.com/charmbracelet/glow/releases) 
6. 使用 `vim /usr/bin/ai-chat` 修改默认配置（这一步可以略过）
7. 运行命令 `ai-chat`，，首次运行会要求输入 KEY，输入硅基流动的 API Key 即可，随后会进入交互界面
8. 在交互界面下，输入 `/help` 可以查看帮助，输入 `/exit` 退出
9. 在命令行界面下，输入命令 `ai-chat -h` 可以查看命令选项
10. 首次运行后，配置文件会保存在 `~/.config/ai-chat/config.env`，可按需修改其中的内容
11. 聊天记录保存在 `~/.config/ai-chat/history.json`，不建议乱动这个文件
