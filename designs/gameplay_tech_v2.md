# 战国谋士 v7.3 — V2 玩法与技术规格

## Part A — Gameplay (v7.3)

### 1. 概述
- **类型**：单人 / 卡牌 + 文字博弈 / 像素风
- **平台**：PC（Godot 4 桌面）
- **核心循环**：6 回合内访问 3 国君主，通过抽 / 打 / 谈 / 漂移 / 终判循环，最终推出 16 型 MBTI 谋士档案 + 终局走向
- **本阶段 (Phase A)**：仅实现数据层 + 仲裁层（State / DataLoader / Arbiter / TurnManager），UI 留在 Phase C

### 2. 玩家三维（初值）
| 维度 | 初值 | 即死边界 |
|------|------|----------|
| 合纵 hezong | 40 | ≤0 或 ≥100 |
| 名望 mingwang | 50 | ≤0 或 ≥100 |
| 心计 xinji | 40 | ≤0 或 ≥100 |

### 3. 国家三维（国威 / 盟信 / 战心）
| 国家 | 国威 guowei | 盟信 mengxin | 战心 zhanxin |
|------|-------------|--------------|--------------|
| 秦 qin | 70 | 30 | 60 |
| 赵 zhao | 50 | 60 | 40 |
| 齐 qi | 55 | 45 | 25 |

### 4. 自动漂移（每偶数回合开始：第 2/4/6 回合）
- 玩家：合纵 −4 / 心计 −3；若该回合未行动 → 名望 −2
- 秦：国威 +5
- 赵、齐：国威 +2，盟信 −2

### 5. 成功率公式
`clamp(基础 + 加成数值 × 系数, 5%, 95%)`

| 动作 | 基础 | 加成属性 | 系数 |
|------|------|----------|------|
| 游说 persuade | 40% | 名望 | 0.30 |
| 离间 alienate | 35% | 心计 | 0.30 |
| 刺探 spy | 50% | 心计 | 0.25 |
| 许诺 promise | 45% | 名望 | 0.30 |
| 传信 message | 40% | 合纵 | 0.30 |

### 6. 打牌方向（游说 / 传信 / 许诺必选；离间 / 刺探不选）

#### 6.1 游说 persuade
| 方向 | 成功效果（玩家三维）|
|------|-------------------|
| 推合纵 push_hezong | 合纵+8 名望+3 心计+3 |
| 推亲秦 push_qin    | 合纵−8 名望+3 心计+3 |
| 中立 neutral       | 名望+5 心计+3 |

#### 6.2 传信 message
| 方向 | 成功效果 |
|------|---------|
| 利合纵 favor_hezong | 合纵+5 心计+3 |
| 利连横 favor_lianheng | 合纵−5 心计+3 |
| 中立 neutral | 心计+5 |

#### 6.3 许诺 promise
| 方向 | 成功效果 |
|------|---------|
| 援助 aid    | 心计+6 名望+3 |
| 结盟 ally   | 心计+4 名望+5 合纵+3 |
| 中立 neutral | 心计+5 名望+2 |

#### 6.4 离间 alienate（无方向）
- 目标国盟信 > 30 → 合纵−6 心计+5 名望+2（视作"成功离间"）
- 目标国盟信 ≤ 30 → 心计+3 名望+1（"不在联盟，效果有限"）

#### 6.5 刺探 spy（无方向）
- 成功：心计+3，揭示该国意图（生成 1 张情报牌）

#### 6.6 失败统一
- 名望 −3
- 例外：面谈裁决失败 名望 −5

### 7. 面谈裁决
综合分 = `comp × 0.3 + stance × 0.4 + pers × 0.3`

| 综合分 | 结果 | 效果 |
|--------|------|------|
| ≥ 6.0 | 采纳 | 打牌方向效果 × 1.5，+1 情报牌 |
| < 6.0 | 拒绝 | 名望 −5，+1 情报牌（含拒绝原因） |

#### 7.1 8 秒超时 mock 关键词
- 包含 `应允/好/定/可/善/依/遵` → 采纳（综合分 6.5，三维各分 6.5）
- 包含 `否/退/罢/不/休/莫` → 拒绝（综合分 4.0）
- 其他 → 拒绝（综合分 5.0）

### 8. 终局判定（第 6 回合末，先检查即死）

#### 8.1 即死叙事（6 种）
| 条件 | 叙事 key |
|------|----------|
| 合纵 = 0   | suspected_qin_spy（疑为秦间）|
| 合纵 = 100 | hezong_martyr（合纵成·身先死）|
| 名望 = 0   | silent_end（无声而终）|
| 名望 = 100 | tall_tree（木秀于林）|
| 心计 = 0   | no_move（无子可落）|
| 心计 = 100 | backfire（棋局反噬）|

#### 8.2 终局情境（第 6 回合末）
| 条件 | 终局 |
|------|------|
| 赵盟信 ≥ 55 AND 齐盟信 ≥ 55 AND 秦国威 ≤ 75 | 【合纵却秦】alliance_victory |
| (赵盟信 ≤ 30 OR 齐盟信 ≤ 30) AND 秦国威 ≥ 80 | 【连横破盟】lianheng_victory |
| 其余 | 【纵横未决】undecided |

### 9. MBTI 4 维 12 题
4 维度：T/F（务实-理想）、S/N（强合纵-强连横）、P/J（主动-被动）、A/E（权变-守正）
每维度 3 题，第 1/2/3/4/5/6 回合分别 2 题，共 12 题。

#### 9.1 单维度累计 → 字母
| 累计 (A 选项数) | 输出 |
|----------------|------|
| 0-1 | B（弱 B）|
| 2   | neutral（中立）|
| 3   | A 弱 |
| 4-5 | A 中 |
| 6   | A 强 |

简化为 16 型：4 维各取 A/B 主导即可（neutral 时按设计文档§五先暂定取 A）。

### 10. 卡牌（7 张，含 directions）
| ID | 名 | 方向 | 基础 | 加成 |
|----|----|------|------|------|
| persuade | 游说 | push_hezong / push_qin / neutral | 40% | 名望×0.30 |
| message  | 传信 | favor_hezong / favor_lianheng / neutral | 40% | 合纵×0.30 |
| promise  | 许诺 | aid / ally / neutral | 45% | 名望×0.30 |
| alienate | 离间 | （无）| 35% | 心计×0.30 |
| spy      | 刺探 | （无）| 50% | 心计×0.25 |
| audience | 面谈 | （走裁决）| — | — |
| intel    | 情报 | （展示用）| — | — |

## Part B — Technical Specifications

### 11. 脚本清单（Phase A 实施）
```
scripts/
├─ core/
│  ├─ state.gd          # Autoload, 全局状态 + 即死检测
│  ├─ data_loader.gd    # Autoload, JSON 加载器
│  ├─ arbiter.gd        # Autoload, 仲裁器（class_name Arbiter）
│  └─ turn_manager.gd   # 场景节点, 回合机
├─ entities/
│  └─ card.gd           # 卡牌数据类（class_name Card，含 directions）
└─ main.gd              # 入口（Phase A 清空业务逻辑，仅显示 "V2 Phase A Ready"）
```

### 12. 节点结构（main.tscn）
```
Main (Node2D, scripts/main.gd)
├─ Background (Sprite2D)
├─ UILayer (CanvasLayer)
│  ├─ DebugLabel (Label)      # 显示 "V2 Phase A Ready - Cards:N MBTI:N Events:N"
│  └─ ActionPanel (Panel)
│     └─ NextTurnButton       # 调用 TurnManager.advance_turn()
│     └─ RoundLabel           # 当前回合数
└─ TurnManagerNode (Node, scripts/core/turn_manager.gd)
```

### 13. Autoload 配置
| 名称 | 路径 | 作用 |
|------|------|------|
| State | res://scripts/core/state.gd | 玩家+国家+MBTI+手牌全局状态 |
| DataLoader | res://scripts/core/data_loader.gd | 启动加载 5 个 JSON |
| Arbiter | res://scripts/core/arbiter.gd | 仲裁器：roll_card / parse_dialogue / apply_drift / check_ending / judge_mbti |

TurnManager 不做 Autoload（场景节点）。

### 14. State 字段
| 字段 | 类型 | 初值 |
|------|------|------|
| player_attrs | Dictionary | {hezong:40, mingwang:50, xinji:40} |
| country_attrs | Dictionary | qin/zhao/qi 三国三维 |
| mbti_scores | Dictionary | {T:0,F:0,S:0,N:0,P:0,J:0,A:0,E:0,neutral:0} |
| mbti_answers | Array | [] |
| current_round | int | 1 |
| max_round | int | 6 |
| action_hand | Array[Card] | [] |
| intel_hand | Array | [] |
| player_location | String | "qin" |
| country_states | Dictionary | {qin:"idle",zhao:"idle",qi:"idle"} |
| acted_this_turn | bool | false |

#### 14.1 State 方法
- `apply_player_delta(d:Dictionary)` — d 形如 {hezong:8, mingwang:3}
- `apply_country_delta(country:String, d:Dictionary)`
- `check_death() -> String` — 返回即死叙事 key（无则 ""）
- `dump_state() -> String`
- `reset()` — Phase A 中暂保留旧 API 桥接

### 15. Arbiter 方法（class_name Arbiter，挂 Autoload）
- `roll_card(card_id:String, direction:String, target_country:String) -> Dictionary`
  返回 `{success:bool, deltas_player:{}, deltas_country:{}, intel:String}`
- `parse_dialogue(text:String, monarch:String, direction:String) -> Dictionary`
  返回 `{verdict:"accept"/"reject", comp:float, stance:float, pers:float, score:float}`
- `apply_drift()` — 每偶数回合开始时由 TurnManager 调用
- `check_ending() -> Dictionary` — `{type:"death"/"situation", detail:String, mbti_type:String}`
- `judge_mbti() -> String` — 返回 4 字母如 "TSPA"

### 16. TurnManager 接口
- 信号：`turn_started(round:int)`、`phase_changed(phase:String)`
- Phase 状态机：`mbti → event → draw → free → end`
- 方法：
  - `advance_turn()` — 切到下一回合首阶段
  - `start_mbti_phase()` / `start_free_phase()`
  - `_phase` 字段维护当前阶段

### 17. State 状态转换表（Phase A）
| 当前 | 允许转向 |
|------|----------|
| BOOT | READY |
| READY | PLAYING |
| PLAYING | GAME_OVER, READY |
| GAME_OVER | READY |

### 18. 数据文件
```
data/
├─ cards.json            # 7 张牌 + directions 字段
├─ mbti_questions.json   # 12 题（4 维 × 3 题）
├─ key_events.json       # ≥12 条关键事件模板（按回合段位×状态索引）
├─ monarch_mock.json     # 3 君主 × 4~6 动作的台词模板
└─ endings.json          # 6 即死 + 3 终局 + ≥16 MBTI 评语
```

### 19. Viewport Config
沿用 1152×648，canvas_items + expand。

### 20. Phase A 验收
- 编译全部通过；main.tscn 通过 godot_run_scenes
- 运行 5 秒，DebugLabel 显示 `V2 Phase A Ready - Cards:7 MBTI:12 Events:12`
- F1 调试键打印 `State.dump_state()`
- 点击"下一回合"按钮，回合数 +1，控制台日志显示 phase_changed 信号
