# ai-chat
AI chat script for linux shell

用于 Linux 的 AI 对话脚本，支持的功能列表如下：
  - 自定义兼容 OpenAI 规范的 API 和 KEY，默认为硅基流动 API，首次运行会要求输入 KEY
  - 自定义模型，默认为 DeepSeek-V3.2
  - 自定义温度，默认为 0.75
  - 自定义系统提示词
  - 中文输入和输出
  - 管道符输入
  - 流式输出和非流式输出
  - 历史聊天记录保存和清理
  - 可自定义对话轮数实现多轮对话，默认 10 轮对话，自动清除超出轮数的对话记录
  - 非流式输出和查看历史对话时支持 Markdown 渲染，需要安装依赖 [glow](https://github.com/charmbracelet/glow/releases)

需要安装依赖 `curl` 和 `jq`，用包管理器安装即可。
