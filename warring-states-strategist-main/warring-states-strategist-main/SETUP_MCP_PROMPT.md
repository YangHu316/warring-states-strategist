# 🔌 给 AI:配置 Godot MCP 服务器(目标项目 game_20260630_d3d6de)

把这份文件的内容整个贴给 Claude Code(或类似 AI)让它照做。做完再让它验证一下。

---

## 你的任务

在当前工作目录(`c:\Users\vicyanghu\Downloads\game_20260630_d3d6de`)配置 Godot MCP,让 Claude Code 能通过 `mcp__godot__*` 工具集操作 Godot 编辑器(读场景树、创建节点、执行 GDScript 等)。

## 架构(先理解再动手)

```
Claude Code ──stdio──> Node.js 桥接 ──WebSocket──> Godot 编辑器 addon
   (你)               (Godot-MCP-main)              (godot_mcp plugin)
```

三个环节缺一不可:
1. **Godot 编辑器插件** `addons/godot_mcp/` — 项目本地,启动 WS server(默认 9080 端口)
2. **Node.js 桥接** — 已存在于 `C:/Users/vicyanghu/Downloads/Godot-MCP-main/Godot-MCP-main/server/dist/index.js`,复用即可
3. **`.mcp.json`** 项目根 — 告诉 Claude Code 怎么启桥接进程

⚠️ 重要:Godot 编辑器**必须打开着这个项目**才能连上。headless / 关闭状态下 MCP 工具全会 timeout。

## 步骤(顺序执行)

### 1. 检查参考项目是否有插件源

```bash
ls "c:/Users/vicyanghu/Downloads/game_20260609_200021/addons/godot_mcp/"
```

预期看到 `plugin.cfg / mcp_server.gd / websocket_server.gd / commands/` 等。

如果参考项目不存在,从 GitHub 克隆:`git clone https://github.com/Coding-Solo/godot-mcp` 或直接用 `C:/Users/vicyanghu/Downloads/Godot-MCP-main/Godot-MCP-main/addons/godot_mcp/`。

### 2. 复制插件到目标项目

```bash
mkdir -p "c:/Users/vicyanghu/Downloads/game_20260630_d3d6de/addons"
cp -r "c:/Users/vicyanghu/Downloads/game_20260609_200021/addons/godot_mcp" \
      "c:/Users/vicyanghu/Downloads/game_20260630_d3d6de/addons/"
```

### 3. 在 `project.godot` 启用插件

用 Read 工具打开 `c:/Users/vicyanghu/Downloads/game_20260630_d3d6de/project.godot`,找 `[editor_plugins]` 段。

**如果段已存在**:确认 `enabled=` 那行含有 `res://addons/godot_mcp/plugin.cfg`。没有就加进去。

**如果段不存在**:在文件末尾追加:
```ini
[editor_plugins]

enabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")
```

⚠️ 不要动其他段(尤其 `[application]`、`[autoload]`)。用 Edit 工具做局部修改。

### 4. 创建 `.mcp.json`(项目根)

在 `c:/Users/vicyanghu/Downloads/game_20260630_d3d6de/.mcp.json` 写:

```json
{
  "mcpServers": {
    "godot": {
      "command": "cmd",
      "args": [
        "/c",
        "set GODOT_PORT=9082&& set MCP_TRANSPORT=stdio&& node C:/Users/vicyanghu/Downloads/Godot-MCP-main/Godot-MCP-main/server/dist/index.js"
      ]
    }
  }
}
```

⚠️ 端口选择:参考项目 `game_20260609_200021` 已用 9081。给这个新项目用 **9082**,避免同时开两个 Godot 编辑器时端口冲突。

### 5. 让 Godot 编辑器认识新端口

Godot 插件默认监听 9080。要让它用 9082,有两条路:

**A. 改插件默认端口(推荐,一劳永逸)**
Read `addons/godot_mcp/websocket_server.gd`,找 `port` 或 `9080` 常量,改成 9082。

**B. 环境变量启动 Godot**
用 `set GODOT_MCP_PORT=9082` 在启动 Godot 前设。但插件不一定读环境变量,需要看代码支持。

先用 A 方案。改完保存。

### 6. 校验插件源码支持当前 Godot 版本

用 Bash 跑:
```bash
"/c/Users/vicyanghu/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe" --headless --path "c:/Users/vicyanghu/Downloads/game_20260630_d3d6de" --check-only 2>&1 | head -20
```

如果 addons 有 GDScript 语法错误(比如版本不匹配),这里会报。有错就先修再往下走。

### 7. 用户手动步骤(你告诉用户去做)

**你不能替用户做的事,列清楚让他做**:
- **A. 关掉当前打开的 Godot 编辑器实例(如果开着参考项目的)**,或者确认新项目用不同端口(已做,9082)
- **B. 用 Godot 4.6.x 编辑器打开目标项目**:双击 `c:/Users/vicyanghu/Downloads/game_20260630_d3d6de/project.godot`
- **C. 首次打开会提示"启用插件",在 `Project → Project Settings → Plugins` 里确认 Godot MCP 是 Enabled
- **D. 编辑器启动完毕后,底部输出面板应看到类似 `[MCP] WebSocket server started on port 9082` 的日志。看到才算成功
- **E. 重启 Claude Code**(必须重启,`.mcp.json` 只在启动时读)

### 8. 验证(用户完成 A-E 后)

调一个最轻的 MCP 工具:
```
mcp__godot__get_project_info
```

预期返回项目名、版本、path。返回 `Connection refused` / `timeout` → 回步骤 7 检查 Godot 编辑器状态。

再试:
```
mcp__godot__list_nodes 参数 parent_path="/root"
```

预期返回场景树根节点列表。

## 常见坑(遇到就地拆)

| 症状 | 根因 | 解 |
|---|---|---|
| MCP 工具全 timeout | Godot 编辑器没开 / 开了别的项目 | 打开目标项目的编辑器 |
| `Connection refused: 9082` | 端口没匹配 | 检查 `.mcp.json` 的 `GODOT_PORT` 和插件 `websocket_server.gd` 里的 port 一致 |
| `Cannot find module .../index.js` | Node 桥接路径错 | 用 `ls` 验证 `C:/Users/vicyanghu/Downloads/Godot-MCP-main/Godot-MCP-main/server/dist/index.js` 存在;不存在需 `cd server && npm install && npm run build` |
| `Plugin not enabled` | project.godot 没配 | 步骤 3 改错 / 用户没在 UI 里 Enable |
| Claude Code 看不到 mcp__godot__* 工具 | 没重启 Claude / .mcp.json 语法错 | JSON 校验 + 重启 Claude |
| 参考项目的 `.claude/settings.json` 里有旧 CodeBuddy 路径的 mcpServers 块 | 用户之前清理过双 server,只剩 Godot-MCP-main。**不要参考那个块**,以 `.mcp.json` 为准 | — |

## 别做的事

- ❌ **不要**改参考项目 `game_20260609_200021` 里的任何东西
- ❌ **不要**把 addons/godot_mcp 里的插件文件当成"我们的代码"提交(它是三方 addon,原样拿来用)
- ❌ **不要**编造 `mcp__godot-mcp__*` 之类不存在的命名空间。这个 MCP server 暴露的工具全是 `mcp__godot__*`(单下划线不带连字符 `godot-mcp`)。命名空间由 `.mcp.json` 里的 `"godot"` 键决定
- ❌ **不要**试图 headless 启动 Godot 来"顺便开 MCP"— 插件只在 editor mode 加载

## 完成汇报

按以下格式报告给用户(极简):

```
✅ 插件已复制:addons/godot_mcp/
✅ project.godot 已 enable
✅ .mcp.json 已创建(端口 9082)
⚠️ 需要用户操作:
  1. 关掉参考项目 Godot 编辑器(如开着)
  2. 用 Godot 4.6.x 打开 c:/Users/vicyanghu/Downloads/game_20260630_d3d6de
  3. Plugins 面板 Enable Godot MCP
  4. 底部输出确认 "WebSocket server started on port 9082"
  5. 重启 Claude Code
完成后调用 mcp__godot__get_project_info 验证。
```

不要多写段落,不要写 emoji 装饰,不要"总结这次做了什么"。用户看到 diff + 上面 5 行就够。
