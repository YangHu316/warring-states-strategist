# 战国谋士 — D1 玩法与技术规格

## Part A — Gameplay (D1 范围)

### 1. 概述
- **类型**：单人/卡牌策略/外交博弈/像素风
- **平台**：PC（Godot 4 桌面）
- **核心体验**：扮演苏秦或张仪，通过 7 张外交卡牌在 6 回合内说服 3 位君主（秦/赵/齐），决定合纵或连横之成败
- **电梯演讲**：「一局战国版《王权 Reigns》——3 君主 × 6 回合 × 7 张卡牌的策略博弈」
- **参考游戏**：Reigns（卡牌决策）、Slay the Spire（数值张力）
- **D1 范围**：项目打底（数据结构 + 场景骨架），不实现完整玩法循环

### 2. 核心机制（D1 数据层 only）
**核心循环（最终目标，D1 仅打地基）**：抽 1 张牌 → 选择目标君主 → 看君主 mock 反应 → 数值变化 → 下回合 → 6 回合后结算

**7 张卡牌**（D1 仅作数据，不实现效果）：
| 卡牌 ID | 名称 | 设计意图 |
|---------|------|---------|
| persuade | 游说 | 大幅提升好感，但暴露意图 |
| message | 传信 | 小幅好感，低风险 |
| promise | 许诺 | 立刻+好感，未来扣信任 |
| sow_discord | 离间 | 降低敌方关系 |
| spy | 刺探 | 获取君主下回合倾向 |
| prepare_war | 备战 | 提升威慑，影响所有君主 |
| discard | 弃牌 | 无效果，换 1 张新牌 |

**3 君主 mock 决策表**（D1 仅数据）：秦（强硬/连横倾向）、赵（中立/摇摆）、齐（保守/合纵倾向），每位君主有 7 张卡的反应模板。

**6 回合关键事件**（D1 仅数据）：第 2/4/6 回合触发，从 `key_events.json` 抽取，事件模板在 `event_templates.json` 占位。

### 3. 场景描述（D1 仅 main.tscn 骨架）
- **MainScene**：根节点 Node2D，作为后续场景的容器。包含：
  - `Background`（Sprite2D，占位底图）
  - `UILayer`（CanvasLayer，占位 UI 容器）
  - `DebugLabel`（Label，显示 "D1: Data Foundation Ready"）

### 4. 游戏流程（D1 实现）
- **启动**：`main.tscn` 加载 → `State` autoload 初始化 → 读取所有 JSON → `DebugLabel` 显示状态
- **D2+ 实现**：抽牌 / 出牌 / 君主反应 / 回合推进 / 结算

### 5. 控制器（D1 占位）
| 动作 | 输入 | 用途 |
|------|------|------|
| ui_accept | Space/Enter | （D2+）打出卡牌 |
| ui_cancel | Esc | （D2+）取消选择 |
| debug_dump | F1 | 打印 State 当前数据（D1 调试用） |

### 6. 关卡设计（D1 不涉及）
D1 不实现关卡，仅数据骨架。

## Part B — Technical Specifications

### 7. 脚本清单（分层目录）

```
scripts/
├─ core/
│  ├─ state.gd          # Autoload, 全局状态（君主好感、回合、手牌）
│  ├─ turn_manager.gd   # 回合管理器（D1 仅接口骨架）
│  └─ data_loader.gd    # JSON 数据加载器（D1 核心）
└─ entities/
   └─ card.gd           # 卡牌数据类（class_name Card）
```

### 8. 节点结构

```
Main (Node2D, scripts: 无)
├─ Background (Sprite2D)              # 占位底图
├─ UILayer (CanvasLayer)              # UI 容器（D1 空）
│  └─ DebugLabel (Label)              # 显示 "D1 Ready" + 数据加载状态
└─ TurnManagerNode (Node)             # 挂 turn_manager.gd 实例（D1 仅初始化）
```

### 9. 输入动作（D1 注册到 project.godot）

| 动作 | 物理键 | 用途 |
|------|--------|------|
| ui_accept | Space, Enter | 系统内置 |
| ui_cancel | Escape | 系统内置 |
| debug_dump | F1 | 调试打印 State |

### 10. Autoload 配置

| 名称 | 路径 | 作用 |
|------|------|------|
| State | res://scripts/core/state.gd | 全局状态单例（君主好感/回合/手牌/数据缓存） |
| DataLoader | res://scripts/core/data_loader.gd | JSON 加载器，启动时读取所有数据文件 |

### 11. 信号（D1 定义骨架，不连接）

| 信号 | 发出者 | 参数 | 说明 |
|------|--------|------|------|
| data_loaded | DataLoader | success: bool | 所有 JSON 加载完成 |
| turn_changed | TurnManager | round: int | 回合切换（D2+ 使用） |
| state_initialized | State | — | State 完成初始化 |

### 12. 状态转换表（D1 仅 BOOT/READY 两态）

| 当前状态 | 允许转向 | 禁止转向 | 异常处理 |
|---------|---------|---------|---------|
| BOOT | READY | PLAYING | 数据加载失败时停留 + 错误日志 |
| READY | PLAYING(D2+) | BOOT | — |

### 13. 数据结构（GDScript 类约定）

**Card 类（class_name Card）字段**：
| 字段 | 类型 | 说明 |
|------|------|------|
| id | String | 卡牌唯一 ID（如 "persuade"） |
| name | String | 显示名 |
| description | String | 描述文本 |
| cost | int | 行动力消耗（D1 默认 1） |
| target_type | String | "single" / "all" / "self" |

**State Autoload 字段**：
| 字段 | 类型 | 初始值 | 说明 |
|------|------|--------|------|
| current_round | int | 1 | 当前回合（1-6） |
| max_round | int | 6 | 最大回合 |
| favor | Dictionary | {qin:50, zhao:50, qi:50} | 君主好感（0-100） |
| hand | Array[Card] | [] | 当前手牌 |
| all_cards | Array[Card] | [] | 全部卡牌（从 cards.json 加载） |
| monarch_data | Dictionary | {} | 3 君主 mock 决策表 |
| events | Array | [] | key_events.json 解析结果 |

### 14. 数值边界（D1）

| 实体/数值 | 最小值 | 最大值 | 越界行为 |
|----------|--------|--------|----------|
| current_round | 1 | 6 | clamp |
| favor[君主] | 0 | 100 | clamp |
| hand.size() | 0 | 5 | 超出拒绝抽牌 |

### 15. 健壮性检查清单

- [ ] JSON 加载失败时 DataLoader 发出 `data_loaded(false)` + 控制台错误
- [ ] State autoload 初始化前其他脚本访问需先检查 `State.is_ready`
- [ ] Card.from_dict() 校验必需字段 id/name 非空
- [ ] DebugLabel 在数据加载失败时显示 "ERROR: data load failed"
- [ ] 所有 JSON 文件 UTF-8 编码，中文不转义

### 16. Viewport Config

| 项 | 值 |
|----|-----|
| viewport_width | 1152 |
| viewport_height | 648 |
| stretch/mode | canvas_items |
| stretch/aspect | expand |

### 17. 碰撞系统
D1 不涉及碰撞，跳过。
