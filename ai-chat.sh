#!/bin/bash

# 这第一行叫做 "Shebang"。它告诉操作系统（比如 Linux 或 macOS）
# 当你直接执行这个文件时（例如，通过 `./ai-chat.sh`），应该使用哪个程序来解释它。
# 在这里，`#!/bin/bash` 意味着“请使用 Bash shell 来运行我”。这是编写 Bash 脚本的标准开头。

# ==============================================================================
# AI Chat Shell Script (v2.4)
# ------------------------------------------------------------------------------
# 这是一个注释块，用来提供脚本的基本信息，比如名称和版本。
# "#" 符号在 Shell 脚本中表示单行注释，从 "#" 开始到行尾的所有内容都会被忽略。
# 良好的注释习惯对于代码的可读性和维护性至关重要。
#
# 更新日志 (Changelog):
# v2.4:
#   使用 jq 处理系统提示词，避免特殊符号读取异常
# v2.3:
#   增加 `-s` 或 `--save` 命令行选项。
#   允许用户在命令行设置参数的同时将配置保存到文件。
#   例如: `ai-chat -t 0.8 -m deepseek-ai/DeepSeek-R1 -s "Hello"`
#   这会将温度和模型永久保存，同时发送消息。
# ... (省略旧日志) ...
# ==============================================================================

# --- 1. 全局配置 (Global Configuration) ---
# 这一部分定义了整个脚本都会用到的全局变量。
# 将这些配置放在脚本的开头，使得修改它们变得非常容易。

# 定义脚本和配置文件的基本名称和路径
APP_NAME="ai-chat"
# `$HOME` 是一个特殊的系统环境变量，代表当前用户的家目录（例如 `/home/username`）。
# 这样配置可以确保每个用户都有自己独立的配置文件夹。
CONFIG_DIR="$HOME/.config/$APP_NAME"
# 将变量组合起来，形成完整的文件路径。
CONFIG_FILE="$CONFIG_DIR/config.env"
HISTORY_FILE="$CONFIG_DIR/history.json"

# 定义用于在终端输出彩色文本的“ANSI转义码”。
# 这会让用户界面更友好、信息更醒目。
# 例如，`\033[0;31m` 是开始红色文本的指令。
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # NC 代表 "No Color"，用于结束彩色文本，恢复终端的默认颜色。

# 定义各项功能的默认值。
# 这样做的好处是，即使用户不进行任何配置，脚本也能以一套合理的设置运行。
DEFAULT_API_URL="https://api.siliconflow.cn/v1/chat/completions"
DEFAULT_MODEL="deepseek-ai/DeepSeek-V3.2"
DEFAULT_TEMP=0.75
DEFAULT_SYSTEM_PROMPT="You are a helpful assistant. For compatible with command line interface, your response must be pure txt format, DO NOT use markdown or latex."
DEFAULT_HISTORY_LIMIT=10  # 历史记录保留最近 10 轮对话
DEFAULT_TIMEOUT=180       # API 请求的超时时间为 180 秒
DEFAULT_STREAM=true       # 默认开启流式输出

# --- 初始化运行时变量 ---
# 这里的语法 `${VARIABLE:-DEFAULT_VALUE}` 是 Shell 的一个强大功能，叫做“参数扩展”。
# 它的意思是：如果 `API_URL` 这个变量已经有值了（可能来自环境变量或配置文件），就使用它的值。
# 如果 `API_URL` 是空的或者没有被设置，就使用冒号后面的默认值 `$DEFAULT_API_URL`。
# 这种方式优雅地完成了“优先使用用户配置，否则使用默认配置”的逻辑。
API_URL=${API_URL:-$DEFAULT_API_URL}
API_KEY=${API_KEY:-""}
MODEL=${MODEL_NAME:-$DEFAULT_MODEL}
TEMPERATURE=${TEMPERATURE:-$DEFAULT_TEMP}
SYSTEM_PROMPT=${SYSTEM_PROMPT:-$DEFAULT_SYSTEM_PROMPT}
HISTORY_LIMIT=${HISTORY_LIMIT:-$DEFAULT_HISTORY_LIMIT}
TIMEOUT_SEC=${TIMEOUT_SEC:-$DEFAULT_TIMEOUT}
ENABLE_STREAM=${ENABLE_STREAM:-$DEFAULT_STREAM}

# --- 2. 初始化与配置 ---
# 这部分代码负责检查脚本运行所需的环境，并处理配置文件的加载和保存。

# 检查脚本的依赖项是否存在。
# `for cmd in ...; do ...; done` 是一个 for 循环，它会依次处理列表中的每一项。
for cmd in jq curl date; do
    # `command -v $cmd` 是一个命令，用于检查名为 `$cmd` 的程序是否存在于系统的 PATH 中。
    # `&> /dev/null` 是一个重定向。`&>` 表示重定向标准输出(stdout)和标准错误(stderr)。
    # `/dev/null` 是一个特殊的“黑洞”文件，任何写入它的数据都会被丢弃。
    # 所以，`command -v $cmd &> /dev/null` 的作用是：安静地检查命令是否存在，不产生任何屏幕输出。
    # `if ! ...` 表示 "如果上一条命令执行失败" (即命令不存在)。
    if ! command -v $cmd &> /dev/null; then
        # 如果依赖不存在，就用 `echo -e` 打印一条红色的错误信息并退出脚本。
        # `-e` 参数让 `echo` 可以解释像 `\033...` 这样的转义序列来显示颜色。
        # `exit 1` 表示脚本以错误状态码 1 退出。非零的退出码通常表示发生了错误。
        echo -e "${RED}Error: 缺少依赖 '$cmd'。${NC}"; exit 1
    fi
done

# 检查 `glow` 命令是否存在，这是一个可选的依赖，用于美化 Markdown 输出。
HAS_GLOW=false # 先假设 `glow` 不存在
if command -v glow &> /dev/null; then
    # 如果 `glow` 存在，就把标志位设为 true。
    HAS_GLOW=true
fi

# 检查并创建配置文件目录和历史文件。
# `[ ! -d "$CONFIG_DIR" ]` 是一个测试条件。
# `[` 是 `test` 命令的简写。`!` 表示 "非"，`-d` 表示 "是一个目录"。
# 所以，这句的意思是 "如果 `$CONFIG_DIR` 这个目录不存在"。
if [ ! -d "$CONFIG_DIR" ]; then 
    # `mkdir -p` 会创建目录。`-p` 参数非常有用，它能确保如果父目录（如 `.config`）不存在时也一并创建。
    mkdir -p "$CONFIG_DIR"; 
fi
# `! -f` 表示 "不是一个文件"。如果历史记录文件不存在...
if [ ! -f "$HISTORY_FILE" ]; then 
    # 就创建一个空的 JSON 数组文件。`>` 是输出重定向，会覆盖文件内容。
    # 这样做可以防止后续的 `jq` 命令因为文件不存在或为空而报错。
    echo "[]" > "$HISTORY_FILE"; 
fi

# 定义函数来加载配置。函数是一段可以重复使用的代码块。
load_config() {
    # `-f "$CONFIG_FILE"` 检查配置文件是否存在且是一个普通文件。
    # `&&` 表示 "并且"，只有当 `[ -f ... ]` 为真时，才会执行后面的 `source` 命令。
    if [ -f "$CONFIG_FILE" ]; then 
        # `source` (或它的简写 `.`) 命令会读取并执行指定文件中的命令。
        # 在这里，它会执行 `config.env` 文件中的 `API_KEY="xxx"` 等赋值语句，
        # 从而将保存的配置加载到当前脚本的运行环境中。
        source "$CONFIG_FILE"; 
    fi;
}

# 定义函数来保存当前配置。
save_config() {
    # `cat <<EOF > "$CONFIG_FILE"` 是一种叫做 "Here Document" 的技术。
    # 它会将从 `<<EOF` 到下一行 `EOF` 之间的所有内容，作为 `cat` 命令的输入，
    # 然后 `>` 将这些输入重定向到 `$CONFIG_FILE` 文件中，从而覆盖旧的配置文件。
    # 文件中的 `$API_URL`, `$API_KEY` 等变量会被替换成它们当前在脚本中的值。
    cat <<EOF > "$CONFIG_FILE"
API_URL="$API_URL"
API_KEY="$API_KEY"
MODEL="$MODEL"
TEMPERATURE="$TEMPERATURE"
SYSTEM_PROMPT="$SYSTEM_PROMPT"
HISTORY_LIMIT="$HISTORY_LIMIT"
TIMEOUT_SEC="$TIMEOUT_SEC"
ENABLE_STREAM="$ENABLE_STREAM"
EOF
    chmod 600 "$CONFIG_FILE" # 为了保护 API KEY 信息，设置配置文件权限为仅当前用户可读写
    echo -e "${GREEN}配置已保存至: $CONFIG_FILE${NC}"
}

# 定义函数来重置配置。
reset_config() {
    # `[ -f "$CONFIG_FILE" ] && ...` 检查文件是否存在，如果存在，则执行 `mv` 命令。
    # `mv "$CONFIG_FILE" "${CONFIG_FILE}.bak"` 将当前配置文件重命名为备份文件，防止数据丢失。
    [ -f "$CONFIG_FILE" ] && mv "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    # 将所有运行时变量重置为脚本定义的默认值。
    API_URL="$DEFAULT_API_URL"; API_KEY=""; MODEL="$DEFAULT_MODEL";
    TEMPERATURE="$DEFAULT_TEMP"; SYSTEM_PROMPT="$DEFAULT_SYSTEM_PROMPT";
    HISTORY_LIMIT="$DEFAULT_HISTORY_LIMIT"; TIMEOUT_SEC="$DEFAULT_TIMEOUT"; ENABLE_STREAM="$DEFAULT_STREAM"
    # 调用 `save_config` 函数，将这些重置后的值写入新的配置文件。
    save_config
    echo -e "${YELLOW}配置已重置。请重新设置 API Key。${NC}"
}

# 脚本启动时，立即调用 `load_config` 函数，加载已有的用户配置。
load_config

# --- 3. 界面显示 (UI Display Functions) ---
# 这部分定义了所有用于向用户显示信息的函数。

# 显示脚本用法说明。
show_usage() {
    # `$0` 是一个特殊变量，代表当前执行的脚本文件名。
    echo -e "AI Chat Shell Script v2.4"
    echo -e "${BLUE}Usage:${NC} $0 [options] [message]"
    echo -e "  -u, --url URL       设置 API URL"
    echo -e "  -k, --key KEY       设置 API Key"
    echo -e "  -m, --model NAME    设置模型"
    echo -e "  -t, --temp NUM      设置温度"
    echo -e "  -s, --save          保存当前命令行参数到配置文件" # [新增说明]
    echo -e "  -H, --history       查看详细历史"
    echo -e "  -e, --env           查看配置"
    echo -e "  --stream            流式输出"
    echo -e "  --no-stream         非流式输出"
    echo -e "  --reset-config      重置配置"
}

# 显示当前配置。
show_config_cli() {
    # 为了安全，不直接显示完整的 API Key。
    # `${API_KEY:0:6}` 是字符串切片，表示从第 0 个字符开始，取 6 个字符（即前 6 位）。
    # `${API_KEY: -4}` 表示取最后 4 个字符。
    local masked_key="${API_KEY:0:6}******${API_KEY: -4}"
    if [ -z "$API_KEY" ]; then
        masked_key="(Not Set)"
    else
        # 即使 key 很短，也尝试掩码，虽然可能效果不佳，但比显示"未设置"更准确
        masked_key="${API_KEY:0:6}******${API_KEY: -4}"
    fi

    local glow_status="Not Installed"
    # 根据之前检查的结果，显示 glow 的安装状态。
    [ "$HAS_GLOW" = true ] && glow_status="Installed (Auto-enable on history/non-stream)"

    echo -e "${CYAN}--- 当前配置状态 ---${NC}"
    echo -e "API URL      : $API_URL"
    echo -e "API Key      : $masked_key"
    echo -e "Model        : ${GREEN}$MODEL${NC}"
    echo -e "Stream Mode  : ${YELLOW}$ENABLE_STREAM${NC}"
    echo -e "Temperature  : $TEMPERATURE"
    echo -e "History Limit: $HISTORY_LIMIT 轮"
    echo -e "Markdown     : $glow_status"
    # `${SYSTEM_PROMPT:0:60}` 只显示系统提示的前 60 个字符，避免刷屏。
    echo -e "${GRAY}System Prompt: ${SYSTEM_PROMPT:0:60}...${NC}"
}

# 显示完整的对话历史。
show_history_full() {
    # `-s "$HISTORY_FILE"` 检查文件是否存在且不为空。
    # `||` 表示 "或者"，如果前面的条件不满足，则执行后面的命令。
    if [ ! -s "$HISTORY_FILE" ] || [ "$(cat "$HISTORY_FILE")" == "[]" ]; then
        echo -e "${GRAY}暂无历史记录。${NC}"; return # `return` 会提前结束当前函数的执行。
    fi

    # 如果 `glow` 已安装，则使用 `jq` 生成 Markdown 格式的输出，并用 `glow` 渲染。
    if [ "$HAS_GLOW" = true ]; then
        # `jq -r '...' "$HISTORY_FILE"`: `jq` 是一个命令行 JSON 处理工具。
        # `-r` 表示 raw-output，输出纯文本而不是带引号的 JSON 字符串。
        # `.[]` 遍历历史文件这个 JSON 数组中的每一个对象。
        # `|` 是管道，将前一个命令的输出作为后一个命令的输入。
        # 整个 `jq` 脚本的作用是为每条历史记录生成一段 Markdown 文本。
        # `//` 是 `jq` 中的 "默认值" 操作符，如果左边的值是 null 或不存在，就使用右边的值。
        # `| glow -` 将 `jq` 生成的 Markdown 文本通过管道传给 `glow` 命令进行实时渲染。 `-` 表示从标准输入读取。
        jq -r '.[] | 
            "\n---\n" + 
            "> 🕒 " + (.timestamp // "未知时间") + " | 🧠 " + (.model // "unknown") + " | 🌡️ " + (.temperature // "N/A") + "\n\n" +
            (if .role == "user" then "### 👤 User" else "### 🤖 AI" end) + "\n\n" + 
            .content + "\n"' "$HISTORY_FILE" | glow -
    else
        # 如果 `glow` 未安装，则使用 `jq` 生成带 ANSI 颜色的普通文本输出。
        echo -e "${CYAN}=== 对话历史记录 ===${NC}"
        jq -r '.[] | 
            "\n" + 
            "--------------------------------------------------\n" +
            "\u001b[90m[" + (.timestamp // "未知时间") + "] " + 
            "Model: " + (.model // "unknown") + " | Temp: " + (.temperature // "N/A") + "\u001b[0m\n" +
            (if .role == "user" then "\u001b[32m[User]: \u001b[0m" else "\u001b[34m[AI]: \u001b[0m" end) + 
            .content' "$HISTORY_FILE"
        echo -e "${CYAN}====================${NC}"
    fi
}

# --- 4. 参数解析 (Argument Parsing) ---
# 这部分代码负责解析用户在命令行输入的选项和参数。

USER_INPUT=""
MODE="interactive" # 默认是交互模式
ACTION_ONLY=false  # 标记是否执行了一个“只做事不聊天”的动作（如查看历史）
SAVE_CONFIG_FLAG=false # [新增变量] 初始化保存标志，默认为 false

# `while [[ $# -gt 0 ]]` 是一个循环，只要还有命令行参数（`$#` 是参数数量），就一直执行。
while [[ $# -gt 0 ]]; do
    key="$1" # 将第一个参数（比如 `-u`）赋值给 `key` 变量。
    # `case ... in ... esac` 是一个选择结构，根据 `key` 的值执行不同的代码块。
    case $key in
        # `-u|--url)`: 如果 `key` 是 `-u` 或者 `--url`。
        -u|--url) API_URL="$2"; shift 2 ;; # 把第二个参数 `$2` 赋值给 `API_URL`。`shift 2` 会移除已处理的 `-u` 和它的值，让循环下一次处理新的 `$1`。
        -k|--key) API_KEY="$2"; shift 2 ;;
        -m|--model) MODEL="$2"; shift 2 ;;
        -t|--temp) TEMPERATURE="$2"; shift 2 ;;
        --timeout) TIMEOUT_SEC="$2"; shift 2 ;;
        # `-s|--save)`: 如果 `key` 是 `-s` 或者 `--save`。
        -s|--save) SAVE_CONFIG_FLAG=true; shift ;; # 这是一个“标志”选项，不带值。将标志设为 true，然后 `shift` 移除 `-s` 本身。
        --stream) ENABLE_STREAM=true; shift ;;
        --no-stream) ENABLE_STREAM=false; shift ;;
        -c|--clear) echo "[]" > "$HISTORY_FILE"; echo "History cleared."; ACTION_ONLY=true; shift ;;
        -e|--env) show_config_cli; ACTION_ONLY=true; shift ;;
        --reset-config) reset_config; ACTION_ONLY=true; shift ;;
        -H|--history) show_history_full; ACTION_ONLY=true; shift ;;
        -h|--help) show_usage; exit 0 ;; # 显示帮助后直接退出。
        # `*)` 是默认分支，如果前面的模式都匹配不上，就会执行这里。
        *) 
           # 这个逻辑用来收集所有不带 `-` 前缀的参数作为用户的聊天输入。
           if [ -z "$USER_INPUT" ]; then # `-z` 检查字符串是否为空
               USER_INPUT="$1" # 如果是第一个单词，直接赋值。
           else
               USER_INPUT="$USER_INPUT $1" # 如果不是，就在后面追加一个空格和这个单词。
           fi
           shift ;; # 每次处理完一个单词，都要 `shift`。
    esac
done

# 处理管道输入 (Piped Input)。例如 `cat question.txt | ./ai-chat.sh`
# `[ -p /dev/stdin ]` 检查标准输入是否是一个管道。
if [ -p /dev/stdin ]; then
    # `PIPE_INPUT=$(cat)` 会读取管道中的所有内容并存入变量。
    PIPE_INPUT=$(cat)
    # 如果管道中有内容...
    if [ -n "$PIPE_INPUT" ]; then # `-n` 检查字符串是否非空。
        # 将管道内容追加到命令行输入之后。
        if [ -n "$USER_INPUT" ]; then
            USER_INPUT="$USER_INPUT"$'\n'"$PIPE_INPUT" # `\n` 是换行符。
        else
            USER_INPUT="$PIPE_INPUT"
        fi
    fi
fi

# [核心逻辑修改] 检查是否需要保存配置。
# 这个检查放在所有参数解析之后，可以确保保存的是命令行中最新的值。
if [ "$SAVE_CONFIG_FLAG" = true ]; then
    save_config
fi

# 如果执行了“仅动作”类命令（如-H, -e）并且没有附加聊天内容，则脚本到此结束。
if [ "$ACTION_ONLY" = true ] && [ -z "$USER_INPUT" ]; then exit 0; fi

# 根据是否有用户输入来决定模式：
# 如果 `USER_INPUT` 非空，说明是单次聊天模式。
# 否则，就是交互式聊天模式。
if [ -n "$USER_INPUT" ]; then MODE="single"; else MODE="interactive"; fi

# --- 5. 核心功能 (Core Functionality) ---

# 检查 API Key 是否已设置。
check_api_key() {
    if [ -z "$API_KEY" ]; then
        echo -e "${RED}错误: API_KEY 未设置。${NC}"
        # 如果是交互模式，提示用户输入 Key 并保存。
        # `read -p "提示信息" VARIABLE` 会显示提示并等待用户输入，然后存入变量。
        [ "$MODE" == "interactive" ] && read -p "Input API Key: " API_KEY && save_config || exit 1
    fi
}

# 发起聊天请求的函数。
chat_request() {
    local user_msg="$1" # 使用 `local` 声明的变量只在函数内部有效，避免污染全局。
    local current_time=$(date '+%Y-%m-%d %H:%M:%S') # 获取当前时间。

    # 使用 jq 准备 API 需要的 JSON 格式数据。
    # 这种方式比手动拼接字符串更安全、更健壮，可以正确处理特殊字符。
    local sys_json=$(jq -n --arg sp "$SYSTEM_PROMPT" '{role: "system", content: $sp}')
    # `jq -n --arg s "$user_msg" '$s'` 是一个安全的将字符串转换为 JSON 字符串值的方法。
    local user_api_json="{\"role\": \"user\", \"content\": $(jq -n --arg s "$user_msg" '$s')}"
    # 历史记录限制的是“轮”，一轮包含用户和AI两条消息，所以实际条数要乘以2。
    local keep_count=$((HISTORY_LIMIT * 2))
    # `mktemp` 创建一个唯一的临时文件，用来存放请求体，比硬编码文件名更安全。
    local payload_file=$(mktemp)

    # 这是整个脚本中最复杂的 `jq` 命令，它负责构建最终发送给 API 的 JSON payload。
    jq -n \
       --argjson sys "$sys_json" \
       --argjson user "$user_api_json" \
       --slurpfile history "$HISTORY_FILE" \
       --arg model "$MODEL" \
       --argjson temp "$TEMPERATURE" \
       --argjson limit "$keep_count" \
       --argjson stream "$ENABLE_STREAM" \
       '{
         model: $model,
         temperature: $temp,
         stream: $stream,
         messages: ([$sys] + ($history[0] | .[-$limit:] | map({role, content})) + [$user])
       }' > "$payload_file"
    # 分解 `messages` 的构建过程:
    # 1. `[$sys]`: 创建一个只包含系统消息的数组。
    # 2. `$history[0]`: `$history` 是通过 `--slurpfile` 读入的，它本身是个数组，所以 `$history[0]` 才是历史记录数组。
    # 3. `.[-$limit:]`: 对历史记录数组进行切片，只取最后 `$limit` 条记录。
    # 4. `map({role, content})`: 遍历切片后的历史记录，每条只保留 `role` 和 `content` 两个字段。
    # 5. `+ [$user]`: 将用户的最新消息追加到数组末尾。
    # 最终 `messages` 是 `[系统消息, ...历史消息, 用户新消息]` 的结构。

    # 准备 curl 命令的选项。使用数组来构建命令可以避免很多因空格和特殊字符导致的错误。
    local curl_opts=(-s -X POST) # -s: 静默模式, -X POST: 使用POST方法
    if [ "$TIMEOUT_SEC" -gt 0 ]; then curl_opts+=(--max-time "$TIMEOUT_SEC"); fi # 动态添加超时选项

    if [ "$MODE" == "interactive" ]; then echo -e "${GREEN}AI (${MODEL}):${NC}"; fi

    local response_content=""

    if [ "$ENABLE_STREAM" = true ]; then
        # --- 流式输出处理 ---
        curl_opts+=(-N) # -N: 禁用缓冲，让数据立即输出，这是流式接收的关键。
        local temp_response_file=$(mktemp) # 临时文件，用于拼接完整的 AI 回复。

        # `while read ... done < <(command)` 是一个推荐的读取命令输出的模式。
        # `< <(...)` 叫做“进程替换”，它允许我们将一个命令的输出像文件一样重定向给另一个命令。
        # 这样 `while` 循环就不会在子 shell 中运行，循环内设置的变量在循环外也可见。
        while IFS= read -r line; do
            # OpenAI/兼容API的流式输出是 Server-Sent Events (SSE) 格式。
            if [[ "$line" == "data: [DONE]" ]]; then break; # 收到结束标志，跳出循环。
            elif [[ "$line" == data:* ]]; then # 如果是数据行...
                # `${line#data: }` 移除行首的 "data: " 字符串。
                # `jq -j '.choices[0].delta.content // empty'` 从数据块中提取内容。`-j`表示无换行输出。
                # `// empty` 确保如果 .content 是 null，则输出空字符串。
                # `echo -n "@"; chunk="${chunk%@}"` 是一个处理换行符的技巧，确保即使 chunk 为空也不会出错。
                local chunk=$(echo "${line#data: }" | jq -j '.choices[0].delta.content // empty'; echo -n "@")
                chunk="${chunk%@}" 

                if [ -n "$chunk" ]; then
                    printf "%s" "$chunk" # `printf`比`echo`更可靠，直接打印收到的文本块，实现打字机效果。
                    printf "%s" "$chunk" >> "$temp_response_file" # 同时将文本块追加到临时文件中。
                fi
            elif [[ "$line" == \{* ]]; then # 如果收到的是一个完整的 JSON 对象，可能是错误信息。
                 local err=$(echo "$line" | jq -r '.error.message // empty')
                 # 如果解析出错误信息，打印并返回。
                 [ -n "$err" ] && echo -e "\n${RED}API Error: $err${NC}" && rm "$payload_file" "$temp_response_file" && return 1
            fi
        done < <(curl "${curl_opts[@]}" "$API_URL" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $API_KEY" \
            -d @"$payload_file") # `-d @file` 表示从文件读取 POST 数据。

        echo "" # 流式输出结束后换一行，使界面整洁。
        response_content=$(cat "$temp_response_file") # 从临时文件中读取完整的 AI 回复。
        rm "$temp_response_file" # 删除临时文件。

    else
        # --- 非流式输出处理 ---
        local raw_response
        raw_response=$(curl "${curl_opts[@]}" "$API_URL" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $API_KEY" \
            -d @"$payload_file")

        # `$?` 是一个特殊变量，保存着上一条命令的退出码。curl 成功时为 0。
        if [ $? -ne 0 ]; then echo -e "${RED}Connection Error.${NC}"; rm "$payload_file"; return 1; fi

        # 检查 API 是否返回了错误。
        local err_msg=$(echo "$raw_response" | jq -r '.error.message // empty')
        if [ -n "$err_msg" ]; then echo -e "${RED}API Error: $err_msg${NC}"; rm "$payload_file"; return 1; fi

        # 从返回的 JSON 中提取 AI 的回复内容。
        response_content=$(echo "$raw_response" | jq -r '.choices[0].message.content // empty')

        if [ -n "$response_content" ]; then
            # 如果安装了 `glow` 并且输出是到终端（`-t 1`），则用 `glow` 渲染。
            if [ "$HAS_GLOW" = true ] && [ -t 1 ]; then
                echo "$response_content" | glow -
            else
                echo "$response_content"
            fi
        else
            echo -e "${RED}Error: Empty response received.${NC}"
            rm "$payload_file"; return 1
        fi
    fi

    rm "$payload_file" # 请求完成后，删除请求体临时文件。

    # --- 保存历史记录 ---
    if [ -n "$response_content" ]; then
        # 为用户消息和 AI 回复分别创建包含元数据（时间、模型等）的 JSON 对象。
        local user_full_json=$(jq -n --arg r "user" --arg c "$user_msg" --arg m "$MODEL" --arg t "$current_time" --arg T "$TEMPERATURE" \
            '{role: $r, content: $c, model: $m, timestamp: $t, temperature: $T}')
        local asst_full_json=$(jq -n --arg r "assistant" --arg c "$response_content" --arg m "$MODEL" --arg t "$(date '+%Y-%m-%d %H:%M:%S')" --arg T "$TEMPERATURE" \
            '{role: $r, content: $c, model: $m, timestamp: $t, temperature: $T}')

        local temp_hist=$(mktemp)

        # 使用 jq 更新历史文件：将新对话追加到数组，然后裁剪数组以保持在限制长度内。
        jq --argjson u "$user_full_json" \
           --argjson a "$asst_full_json" \
           --argjson limit "$keep_count" \
           '(. + [$u, $a]) | if length > $limit then .[-$limit:] else . end' \
           "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"
        # `> "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"` 是一个安全的文件写入操作。
        # 先写入临时文件，成功后再用 `mv`（原子操作）替换原文件，可防止因意外中断导致文件损坏。
    fi
}

# --- 6. 主循环 (Main Loop) ---
# 这是脚本的入口点和主要控制流程。

check_api_key # 首先检查 API Key

if [ "$MODE" == "single" ]; then
    # 如果是单次模式，直接调用 chat_request 并传入用户输入，然后脚本结束。
    chat_request "$USER_INPUT"
else
    # 如果是交互模式，打印欢迎语。
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   AI Chat CLI (Stream: $ENABLE_STREAM)   ${NC}"
    # 如果 glow 可用且当前为非流式模式，给出提示。
    [ "$HAS_GLOW" = true ] && [ "$ENABLE_STREAM" = false ] && echo -e "${GRAY}   Markdown Renderer: Glow Active         ${NC}"
    echo -e "${BLUE}========================================${NC}"

    # `while true` 创建一个无限循环，直到用户输入 `/exit` 或 `/quit`。
    while true; do
        # `echo -ne` 打印提示符，`-n` 表示不换行。
        echo -ne "${YELLOW}You:${NC} "
        # `IFS= read -r input_line` 是读取用户输入的标准、安全的方式。
        # `IFS=` 防止行首和行尾的空白被ตัด掉，`-r` 防止反斜杠被解释。
        IFS= read -r input_line

        # 解析用户输入的 "斜杠命令"，如 `/model deepseek-v2`。
        # `${input_line%% *}` 提取第一个空格前的部分作为命令。
        # `${input_line#* }` 提取第一个空格后的所有部分作为参数。
        cmd="${input_line%% *}"; arg="${input_line#* }"; [ "$cmd" == "$arg" ] && arg=""

        case "$cmd" in
            /exit|/quit) echo "Bye!"; break ;; # `break` 跳出 `while` 循环。
            /clear) echo "[]" > "$HISTORY_FILE"; echo -e "${GREEN}历史记录已清除。${NC}" ;;
            /config) show_config_cli ;;
            /history) show_history_full ;;
            /save) save_config ;;
            /reset) reset_config; check_api_key ;; # 重置后需要重新检查 key。
            /stream) 
                # 切换流式模式的开关。
                [ "$ENABLE_STREAM" = true ] && ENABLE_STREAM=false || ENABLE_STREAM=true
                echo -e "${GREEN}Stream: $ENABLE_STREAM${NC}" 
                [ "$ENABLE_STREAM" = false ] && [ "$HAS_GLOW" = true ] && echo -e "${GRAY}(Glow rendering enabled)${NC}"
                ;;
            /model) [ -n "$arg" ] && MODEL="$arg" && echo -e "${GREEN}Model set.${NC}" || echo "Current: $MODEL" ;; # 如果有参数则设置，否则显示当前值。
            /temp) [ -n "$arg" ] && TEMPERATURE="$arg" && echo -e "${GREEN}Temp set.${NC}" || echo "Current: $TEMPERATURE" ;;
            /help) echo -e "----Commands----\n/stream          流式输出开关\n/model modelname 设置模型名\n/temp number     设置模型温度\n/history         显示对话记录\n/config          显示当前配置\n/save            保存当前配置\n/reset           重置所有配置\n/clear           清除对话记录\n/exit            退出\n" ;;
            "") continue ;; # 如果用户只敲了回车，`continue` 会跳过本次循环的剩余部分，直接开始下一次循环。
            *) 
                # 如果输入以 `/` 开头但不是已知命令...
                if [[ "$input_line" == /* ]]; then
                    echo -e "${RED}Unknown command.${NC}";
                else
                    # 否则，这就是一条普通的聊天消息，调用 chat_request 处理。
                    chat_request "$input_line";
                fi ;;
        esac
    done
fi

