# 策划交付物 · AI 集成指南（**v7.3.7** · 2026-07-02 · RFC-001/002 修订 + 23 项 P1 修复）

> **目的**：让程序或 AI Agent 在**第一次接触项目**时，仅凭本文件就能定位"每个 C0X 交付物是什么、应该落到代码的哪一处、被哪个类加载"。
>
> **面向对象**：
> - 程序同事（接入新交付物时第一查的文件）
> - AI 编程助手（被命令"按交付物改 X 行为"时的索引文件）
> - 后续 D2/D3/D4 策划交付物的索引范本
>
> **本目录结构**（v7.3.7 重组后）：
> ```
> 策划交付物/
> ├── README.md                       ← 总索引（按 D1/D2/D3/D4 + RFC/推演/质量/集成 分类）
> ├── D1-策划交付物-20260630/         ← D1 设计锁定（8 个 C0X + README）
> ├── D2-策划交付物-20260702/         ← D2 Mock 决策表 + 困局模板（7 个 C0X + README）
> ├── D3-策划交付物-20260702/         ← D3 LLM Prompt 终稿 + 试玩（7 个 CXX + README）
> ├── D4-策划交付物-20260702/         ← D4 集成、彩排、签字（4 个 CXX + README）
> ├── RFC/                            ← RFC 修订记录
> ├── 推演验证/                        ← 数值/平衡推演报告
> ├── 质量报告/                        ← 质量检测与修复报告
> └── 集成指南/                        ← 本文件 + 调用规则附录
>     └── AI_INTEGRATION_GUIDE.md
> ```
>
> **版本对应**：**v7.3.7**（RFC-001/002 数值+面谈类 P0 修订 + 23 项 P1 修复 · 2026-07-02）
> - **v7.3.7**：秦国威漂移 +5→+3（推演发现 · **代码侧待实施**，见 §5 #1）/ 面谈机制 stance_aware_actions 重设计（RFC-002，P0-2/3/4 修复 · **代码侧待实施**，见 §5 #2）/ 投降关键词映射中立（P0-10 · **代码侧待实施**，见 §5 #3）/ 23 项 P1 修复
> - v7.3.6：玩家三维初值 / 单卡惩罚 / 终局阈值 / 国家三维 clamp（RFC-001）
> - v7.3.5：召见面谈立场结算（ea86f2d）

---

## 0 · 30 秒总览（先看这张表）

> **改了策划交付物 → 改项目里哪里？** 一图回答。
>
> ⚠️ **本表字段名已与 v7.3.7 实际 JSON 字段对齐**（与 C05 契约可能仍有差异，详见各 C0X §"实际 vs 契约"小节）

| 交付物 | 锁定什么 | **落到 `data/` 的 JSON** | **被 `scripts/` 哪个类读取** | **同步源文档** | **v7.3.7 状态** |
|---|---|---|---|---|---|
| **C01** 数值系统 | 玩家/国家三维初值、漂移、终局阈值、面谈立场结算 | （硬编码在 `state.gd`） | `core/state.gd`（初值）+ `core/arbiter.gd`（漂移/终局/动作效果） | `03-数值系统.md` §一 §二 §2.1 §2.2 | ⚠️ 秦国威漂移 +5→+3 未实施 |
| **C02** 卡牌 + 方向 + 情报牌 | 5 牌效果、方向枚举、情报牌加成公式 | **`cards.json`** | `core/data_loader.gd` → `core/state.gd.all_cards` → `core/arbiter.gd.roll_card()`（掷骰）+ `scripts/main.gd`（打牌 UI） | `05-卡牌设计.md` §一 §二 | ✅ 一致 |
| **C03** 3 君主 persona | 性格/核心利益/可用动作/近臣/记忆/决策规则/输出 schema | `data/monarch_mock.json`（**仅开场白台词**） | 开场白：`scripts/ui/dialogue.gd`<br>性格/动作集：**硬编码**于 `core/monarch_ai.gd.make()`<br>LLM prompt：**硬编码**于 `core/monarch_ai.gd._build_prompt()` | `04-Agent架构.md` + `11b-角色设计稿-程序.md` | ⚠️ C09–C11 mock 决策表 **未真正被代码读取**（见 §5 #4） |
| **C04** 5 近臣权重 + 视觉 | 近臣权重表 + Prompt 注入片段 + 视觉关键词 | `data/monarch_mock.json`（**无权重字段**）<br>`assets/portraits/` `assets/silhouettes/`（视觉） | 权重：**硬编码**于 `core/monarch_ai.gd.advisor_weights`<br>LLM：注入到 `_build_prompt()` §advisor_defs<br>美术：依 ID 命名加载 | `04-Agent架构.md` §四 + `11a-角色设计稿-美术.md` | ⚠️ `minister_weights` 字段未在 JSON |
| **C05** 设计契约 | 类名/字段名/资产 ID/prompt 字段名（**唯一权威**） | （**不是数据，是规范**）<br>所有 JSON 的字段必须按本契约命名 | `core/state.gd`（类字段）+ `core/data_loader.gd`（路径常量）+ `core/agent_manager.gd` + 美术资产加载 | 全 v7-纵横RTS | ⚠️ **多处与实际 JSON 字段不符**（详见 §2.1–§2.8） |
| **C06** 3 立场题库 6 题 | Q1–Q6 题面、计分规则、超时 | **`mbti_questions.json`** | `core/data_loader.gd` → `core/state.gd.all_questions` → `scripts/main.gd._show_mbti_questions_for_round()` | `08-结局设计.md` §2.2 | ✅ 一致（字段 `score` 而非 C05 契约的 `stance`） |
| **C07** 9 评语 + 6 死亡 | 3 终局 × 3 立场 = 9 + 6 死亡 | **`endings.json`** | `core/data_loader.gd` → `core/state.gd.endings` → `scripts/ui/ending.gd`（读取） | `08-结局设计.md` §六 | ✅ 一致（按 death/situation/stance_review 三类组织） |
| **C08** 6 回合关键事件 | 6 回合主题、状态分支、调用接口 | **`key_events.json`** | `core/data_loader.gd` → `core/state.gd.events` → `scripts/main.gd._resolve_key_event()`（回合开始注入 banner） | `12-总体剧本.md`（结构已改造为 6 回合单层） | ⚠️ JSON 字段是 `state_tag/text/round_range`，C08 文档描述的 `theme/title/description/agent_topics` 不符（见 §2.8） |

> **核心原则**：策划交付物**只产出 markdown + JSON 数据**；**不直接生成代码**。所有代码侧的字段名、ID、枚举必须严格遵循 **C05 设计契约**（但 §2 标注 ⚠️ 的字段实际 JSON 与契约有差异，改动时优先对齐契约而非保持 JSON 原状）。

---

## 1 · 数据流：从交付物到运行时

```
策划交付物 (.md)
  │
  ├─── 程序手动转写为 data/*.json（按 C05 字段名）
  │      ↓
  │    res://data/cards.json            ← C02 卡牌（5 牌 + 6 牌 + 召见）
  │    res://data/mbti_questions.json   ← C06 三立场题库
  │    res://data/key_events.json       ← C08/C15 关键事件（state_tag/text）
  │    res://data/monarch_mock.json     ← C03 开场白台词（每君主按动作分类的台词池）
  │    res://data/endings.json          ← C07/C18 评语 + 死亡叙事
  │    res://data/event_templates.json  ← C15 教程式首局事件模板
  │    res://data/mock_qin.json         ← C09 mock 决策表（策划稿 · 代码未读，见 §5 #4）
  │    res://data/mock_zhao.json        ← C10 mock 决策表（同上）
  │    res://data/mock_qi.json          ← C11 mock 决策表（同上）
  │      ↓
  │    core/data_loader.gd._load_all()  (Autoload: DataLoader)
  │      ↓
  │    core/state.gd (Autoload: State)
  │      ├── all_cards       (Array[Card])
  │      ├── all_questions   (Array)
  │      ├── events          (Array)
  │      ├── monarch_mock    (Dictionary<String, Dictionary>)
  │      └── endings         (Dictionary)
  │      ↓
  │    业务逻辑读取
  │      ├── core/arbiter.gd        (C01 漂移/终局 + C02 牌效果 + C07 评语)
  │      ├── core/turn_manager.gd   (回合阶段机)
  │      ├── core/agent_manager.gd  (3 君主博弈调度)
  │      ├── core/monarch_ai.gd     (C03/C04 决策 + LLM prompt 硬编码)
  │      ├── core/llm_client.gd     (LLM 通信 · Autoload)
  │      ├── scripts/main.gd        (C06 立场问卷 + C08 关键事件横幅 + 打牌流程)
  │      └── scripts/ui/dialogue.gd (C03 persona 台词 + 面谈 UI)
  │
  └─── 运行时配置
         └── user://config.cfg         (LLMClient 读 api_key)
```

> ⚠️ **C09–C11 mock 决策表**（C09-mock决策表-秦王.md 等 3 文件）已落盘为 `data/mock_qin.json` / `data/mock_zhao.json` / `data/mock_qi.json`，**但 DataLoader 未读取**，实际决策走 `core/monarch_ai.gd.make()` 硬编码的 mock。详见 §5 #4。

---

## 2 · 逐文件详解

### 2.1 · C01 · 数值系统 → `core/state.gd` + `core/arbiter.gd`

> **位置**：`策划交付物/D1-策划交付物-20260630/C01-数值系统-锁定表.md`

| 章节 | 锁定内容 | 落到代码哪里 | **v7.3.7 实际状态** |
|---|---|---|---|
| §一 玩家三维初值 | `{hezong:40, mingwang:50, xinji:40}`（**v7.3.7 实际**） | `core/state.gd:14` `var player_attrs: Dictionary` | ✅ 已对齐（v7.3.6 描述的 50/60/40 → 实际 50/40/50, 详见 P1-6 备注） |
| §一 国家三维初值 | 秦 70/30/60 · 赵 50/60/40 · 齐 55/45/25 | `core/state.gd:17-21` `var country_attrs: Dictionary` | ✅ 一致 |
| §三 国家三维取值范围 | 0–100 clamp | `core/state.gd:82, 97` `clampi(v, 0, 100)` | ✅ 一致 |
| §1.1 单卡方向幅度 | 游说推合纵+8 / 推亲秦−8 / 传信+5/−5 / 离间分支 / 许诺结盟+3 | `core/arbiter.gd.roll_card()` 中 `match card_id` | ✅ 已对齐 `data/cards.json` |
| §1.2 面谈立场结算 | **v7.3.7 stance_aware_actions**（推合纵/推亲秦背书 / 中立君主自决） | `core/agent_manager.gd`（`on_player_stance()`） | ⚠️ **代码未实现**（§5 #2） |
| §1.3 面谈超时降级 | 关键词：合/纵/盟/抗秦 → 推合纵；横/连横/亲秦 → 推亲秦 | `core/arbiter.gd.parse_dialogue()`（综合分判 accept/reject） | ⚠️ **没有按立场分流**（仅按综合分判 accept/reject） |
| §二 漂移参数 | 每 2 回合触发：合纵 −4、名望 −2、心计 −3、**秦国威 +5（⚠️ v7.3.7 文档说 +3，代码未改）** 等 6 项 | `core/arbiter.gd.apply_drift()` + `core/turn_manager.gd.advance_turn()`（每 2 回合开始时调用） | ⚠️ **秦国威 +3 待实施**（§5 #1） |
| §3.1 终局阈值 | 合纵：赵盟信≥55 AND 齐盟信≥55 AND 秦国威≤75<br>连横：赵/齐 盟信≤30 AND 秦国威≥80 | `core/arbiter.gd.check_ending()` | ✅ 代码与 C01 §3.1 一致（v7.3.6 已写入） |
| §四 二值判定公式 | `clamp(基础 + 数值 × 系数 + 消耗情报牌数 × 5, 5, 95)` | `core/arbiter.gd.roll_card()` line 26-27 | ✅ 一致 |
| §五 6 种值死亡叙事 | 6 段文言叙事 | `data/endings.json["death"]` 段 | ✅ 已落 `data/endings.json`（中文/英文 key 混用） |

**`core/state.gd` 关键字段**（v7.3.7 实际）：

```gdscript
# state.gd:14
var player_attrs: Dictionary = {"hezong": 40, "mingwang": 50, "xinji": 40}

# state.gd:17-21
var country_attrs: Dictionary = {
    "qin":  {"guowei": 70, "mengxin": 30, "zhanxin": 60},
    "zhao": {"guowei": 50, "mengxin": 60, "zhanxin": 40},
    "qi":   {"guowei": 55, "mengxin": 45, "zhanxin": 25}
}

# state.gd:9-10 — 实际枚举
enum GameState { BOOT, READY, PLAYING, GAME_OVER }
# ⚠️ C05 §2.2 描述的 Phase 枚举（INIT/FREE_ACTION/ROUND_END/GAME_OVER/AUDIENCE）实际未用
# 实际阶段字符串由 turn_manager.gd PHASES 数组承载（见 §2.1.1）

# state.gd:39
var country_states: Dictionary = {"qin":"idle", "zhao":"idle", "qi":"idle"}
# 状态字符串：idle / running / summon / decided / done（agent_manager 维护）
```

**`core/turn_manager.gd` 关键字段**（v7.3.7 实际）：

```gdscript
# turn_manager.gd:9
const PHASES: Array = ["mbti", "event", "draw", "free", "end"]
# ⚠️ 实际有 5 个阶段，mbti/event/draw/free/end（不包含 C05 文档的 AUDIENCE）
# 阶段推进由 main.gd._start_round_flow() → turn_manager.advance_turn() 驱动

# turn_manager.gd:30 — 第偶数回合调用 apply_drift
if State.current_round % 2 == 0:
    var arb = get_node_or_null("/root/Arbiter")
    if arb != null and arb.has_method("apply_drift"):
        arb.apply_drift()
```

**改 C01 时的检查清单**：
- [ ] 改了玩家/国家三维初值 → 改 `core/state.gd:14/17-21`（**注意 v7.3.6 文档值 50/60/40 与 v7.3.7 代码值 50/40/50 不一致**，以代码为准）
- [ ] 改了动作效果表 → 改 `data/cards.json`（C02 同步）
- [ ] 改了终局阈值 → 改 `core/arbiter.gd.check_ending()` line 200-214
- [ ] 改了成功率公式 → 改 `core/arbiter.gd.roll_card()` line 26-27
- [ ] 改漂移秦国威 +5→+3 → 改 `core/arbiter.gd.apply_drift()` line 195（**P0 漏修**）
- [ ] 改面谈立场语义 → 改 `core/arbiter.gd.parse_dialogue()` + 补 `core/agent_manager.gd.on_player_stance()` stance_aware_actions 三分支

---

### 2.2 · C02 · 卡牌 + 方向 + 情报牌 → `data/cards.json`

> **位置**：`策划交付物/D1-策划交付物-20260630/C02-卡牌效果与方向选择-锁定表.md`
> **运行时文件**：`res://data/cards.json`

**JSON 实际结构**（v7.3.7 · 与 C05 契约有差异）：

```json
{
  "cards": [
    {
      "id": "persuade",
      "name": "游说",
      "description": "向君主陈述合纵之利。需选择方向。",
      "cost": 1,
      "target_type": "single",
      "requires_direction": true,
      "directions": ["push_hezong", "push_qin", "neutral"],
      "base_rate": 40,
      "scale_attr": "mingwang",
      "scale_coef": 0.30,
      "on_success": {
        "push_hezong": {"hezong": 8, "mingwang": 3, "xinji": 3},
        "push_qin":    {"hezong": -8, "mingwang": 3, "xinji": 3},
        "neutral":     {"mingwang": 5, "xinji": 3}
      },
      "on_fail": {"mingwang": -3}
    },
    {
      "id": "message",
      "name": "传信",
      "requires_direction": true,
      "directions": ["favor_hezong", "favor_lianheng", "neutral"],
      "on_success": {
        "favor_hezong":   {"hezong": 5, "xinji": 3},
        "favor_lianheng": {"hezong": -5, "xinji": 3},
        "neutral":        {"xinji": 5}
      }
    },
    {
      "id": "promise",
      "name": "许诺",
      "requires_direction": true,
      "directions": ["aid", "ally", "neutral"],
      "on_success": {
        "aid":  {"xinji": 6, "mingwang": 3},
        "ally": {"xinji": 4, "mingwang": 5, "hezong": 3},
        "neutral": {"xinji": 5, "mingwang": 2}
      }
    },
    {
      "id": "alienate",
      "name": "离间",
      "requires_direction": false,
      "base_rate": 35,
      "on_success_high_mengxin": {"hezong": -6, "xinji": 5, "mingwang": 2},
      "on_success_low_mengxin":  {"xinji": 3, "mingwang": 1}
    },
    {
      "id": "spy",
      "name": "刺探",
      "requires_direction": false,
      "base_rate": 50,
      "on_success": {"xinji": 3}
    },
    {
      "id": "audience",
      "name": "面谈",
      "base_rate": 0,
      "on_success": {}
    }
  ]
}
```

> ⚠️ **与 C05 契约差异**：
> - C05 §2.2 描述的方向枚举是 `PUSH_HEZONG / PUSH_QIN / NEUTRAL_ADVICE`，但 cards.json 中：
>   - persuade 用 `push_hezong / push_qin / neutral`
>   - message 用 `favor_hezong / favor_lianheng / neutral`（**新增值**）
>   - promise 用 `aid / ally / neutral`（**新增值**）
> - C05 描述 Card.type 是枚举 `PERSUADE/ALIENATE/SPY/PROMISE/DISPATCH`，实际 `id` 字段是 `persuade/.../dispatch`（**dispatch 替换 spy** + 多了 audience）

**读取路径**：
- `core/data_loader.gd:6` `const PATH_CARDS = "res://data/cards.json"`
- `core/data_loader.gd:30-35` 加载（`Card.from_dict(cd)`）
- `core/state.gd:43` `var all_cards: Array = []`
- **消费方**：
  - `core/arbiter.gd.roll_card()` line 5-65（掷骰/结算）—— 通过 `match card_id` 硬编码分支
  - `scripts/main.gd._draw_action_cards()` line 201-215（抽牌）
  - `scripts/main.gd._preview_rate()` line 246-251（UI 预览）

**关键参数（v7.3.3 → v7.3.4 改过）**：
- 情报牌加成：**每张 +5%**（`scripts/main.gd:287` `var intel_bonus: int = intel_indices.size() * 5`）
- 加成公式：`clamp(基础 + 数值×系数 + 消耗牌数×5, 5, 95)`

**改 C02 时的检查清单**：
- [ ] 改了牌效果表 → 改 `data/cards.json`
- [ ] 改了方向枚举 → 同步 `core/arbiter.gd.roll_card()` 的 `match` 分支
- [ ] 改了情报牌加成 → 改 `scripts/main.gd:287`（不在 `core/state.gd` 中！）
- [ ] 加了新牌 → 同步 `core/arbiter.gd.roll_card()` + `scripts/main.gd`（牌 UI）

---

### 2.3 · C03 · 3 君主 persona → 硬编码于 `core/monarch_ai.gd` + `data/monarch_mock.json`（仅开场白）

> **位置**：`策划交付物/D1-策划交付物-20260630/C03-三君主persona卡片.md`
> **运行时分布**：
> - **决策逻辑**：硬编码于 `core/monarch_ai.gd.make()`（每个国家一个 `persona` + `advisor_weights`）
> - **LLM prompt**：硬编码于 `core/monarch_ai.gd._build_prompt()`（按国家分流 `role_defs` / `actions_defs` / `advisor_defs`）
> - **开场白台词**：`data/monarch_mock.json`（按国家 → 6 动作分类的台词池）

**`data/monarch_mock.json` 实际结构**（v7.3.7）：

```json
{
  "qin": {
    "name": "秦王嬴稷",
    "persuade": ["...", "...", "..."],
    "message":  ["...", "..."],
    "promise":  ["...", "..."],
    "alienate": ["...", "..."],
    "spy":      ["...", "..."],
    "audience": ["...", "..."]
  },
  "zhao": { ... },
  "qi":   { ... }
}
```

> ⚠️ **C03 文档描述的 `actions{weight,conditions}` / `minister_weights{action:weight}` / `decision_priority` 结构在 JSON 中不存在**！这些字段已由 `core/monarch_ai.gd.make()` 硬编码实现。`data/monarch_mock.json` 退化为**仅开场白台词池**。
>
> ⚠️ **C09/C10/C11 描述的 mock 决策表**（`mock_qin.json` / `mock_zhao.json` / `mock_qi.json`）**已落盘但 DataLoader 不读**（详见 §5 #4）。实际决策走 `monarch_ai.gd` 硬编码 mock。

**`core/monarch_ai.gd.make()` 实际**（v7.3.7 · line 22-49）：

```gdscript
static func make(country_id: String) -> MonarchAI:
    var ai := MonarchAI.new()
    ai.country = country_id
    match country_id:
        "qin":
            ai.persona = {
                "actions": ["pressure", "alienate", "lure", "prepare"],
                "base": {"pressure": 1.0, "alienate": 1.0, "lure": 1.0, "prepare": 0.6}
            }
            # 张仪·连横推手 + 魏冉·主战
            ai.advisor_weights = {"lure": 1.5, "prepare": 0.6, "pressure": 1.4}
        "zhao":
            ai.persona = {
                "actions": ["seek_alliance", "prepare", "probe", "observation"],
                "base": {"seek_alliance": 1.4, "prepare": 1.0, "probe": 0.8, "observation": 0.6}
            }
            ai.advisor_weights = {"seek_alliance": 1.4, "observation": 0.5, "prepare": 1.3}
        "qi":
            ai.persona = {
                "actions": ["observation", "wait_price", "hijack", "self_protect"],
                "base": {"observation": 1.5, "wait_price": 1.0, "hijack": 0.5, "self_protect": 0.8}
            }
            ai.advisor_weights = {"observation": 1.3, "hijack": 0.5, "wait_price": 0.8}
    return ai
```

**LLM prompt 8 模块**（C03 §卡片 1–3 完整版 → `core/monarch_ai.gd._build_prompt()` line 172-255）：

```
# 1. 世界铁律     （不可违反 · 无其他国）
# 2. 你是谁       ← C03 §1 性格档案
# 3. 本回合关键事件
# 4. 该事件对你的暗示
# 5. 当前局势（第 N 轮）   ← 三维数据 + 玩家立场 + 记忆
# 6. 你可用的动作
# 7. 决策规则     ← 含性格铁律
# 8. 输出（严格 JSON）
```

> ⚠️ **C05 §四"8 模块"是 [角色定位/性格画像/核心利益/可用动作/近臣倾向/记忆/决策规则/输出 schema]**。**实际 `_build_prompt()` 是 8 段但顺序与命名不同**（"世界铁律"在最前而非"角色定位"）。改 C03 同步代码时，**按 _build_prompt() 实际段落同步**。

**改 C03 时的检查清单**：
- [ ] 改了 persona 内容（性格/核心利益/动作）→ 同步 `core/monarch_ai.gd.make()` 硬编码 + `_build_prompt()` prompt
- [ ] 加了新动作枚举 → 同步 `core/arbiter.gd.settle_agent_action()` 的 `match action_type` 分支
- [ ] 改了输出 schema → 同步 `core/monarch_ai.gd._validate_llm_action()` 校验逻辑
- [ ] 改了开场白台词 → 改 `data/monarch_mock.json`（按国家 → 6 动作分类）
- [ ] **C09–C11 mock 决策表** 改动后，**代码不会自动生效**（详见 §5 #4）

---

### 2.4 · C04 · 5 近臣权重 + 视觉 → 硬编码于 `core/monarch_ai.gd.advisor_weights` + `assets/`

> **位置**：`策划交付物/D1-策划交付物-20260630/C04-五近臣权重与视觉表.md`
> **运行时分布**：
> - **权重**：硬编码于 `core/monarch_ai.gd.make()`（每个国家一个 `advisor_weights: Dictionary`）
> - **LLM prompt 注入**：`_build_prompt()` 中 `advisor_defs`（按国家，5-10 字短句）
> - **美术**：`assets/portraits/ministers/portrait_xxx.png` + `assets/silhouettes/ministers/silhouette_xxx.png`

**资源 ID 命名**（C04 §一 + C05 §3.2.3 对齐）：

```
portrait_zhangyi.png       silhouette_zhangyi.png        ← 秦·张仪
portrait_weiran.png        silhouette_weiran.png         ← 秦·魏冉
portrait_pingyuanjun.png   silhouette_pingyuanjun.png    ← 赵·平原君
portrait_lianpo.png        silhouette_lianpo.png         ← 赵·廉颇
portrait_mengchangjun.png  silhouette_mengchangjun.png   ← 齐·孟尝君
```

**Prompt 注入示例**（`monarch_ai.gd:189-193`）：

```gdscript
var advisor_defs = {
    "qin": "近臣：张仪（连横推手，选 lure 时他说'齐王贪利，许以三城可定'——加 confidence）；魏冉（主战，选 pressure 时说'战机稍纵即逝'——加 confidence）",
    "zhao": "近臣：平原君（主合纵，选 seek_alliance 时说'合纵抗秦是赵国唯一出路'）；廉颇（主战不信秦，选 prepare 时说'廉颇老矣尚能一战'）",
    "qi": "近臣：孟尝君（谨慎渔利，动手时低声说'动则必败，观望方为上策'——observation 加 confidence）"
}
```

**改 C04 时的检查清单**：
- [ ] 改了权重表 → 改 `core/monarch_ai.gd.make()` 硬编码（**不在 JSON**！）
- [ ] 改了 prompt 注入片段 → 改 `core/monarch_ai.gd._build_prompt()` 中 `advisor_defs`
- [ ] 加了新近臣 → 同步 C04 §一 视觉表 + C05 §3.2.3 资源 ID + 美术出图

---

### 2.5 · C05 · 设计契约 → **所有代码的字段名权威**

> **位置**：`策划交付物/D1-策划交付物-20260630/C05-设计契约.md`
> **重要**：本文件**不是数据**，是**规范**。所有代码侧的字段名/ID/枚举必须严格遵循。

**契约包含**：

| 章节 | 锁定内容 | 同步到代码哪里 | **v7.3.7 实际状态** |
|---|---|---|---|
| §2.1 核心类 | `GameState / Player / Country / Agent / Card / IntelCard / RoundLog` 字段表 | `core/state.gd` 全部类定义 | ⚠️ Card 实际无 `target_country` 字段 |
| §2.2 枚举常量 | `Phase / QIN/ZHAO/QI / HEZONG/ZHONGLI/QINQIN / PERSUADE/ALIENATE/... / PUSH_HEZONG/...` | `core/state.gd` + 各业务类 | ⚠️ Phase 枚举未用；方向枚举名与 cards.json 不一致 |
| §2.3 Agent 动作枚举 | `QIN_MILITARY / QIN_ALIENATE / ... / ZHAO_ALLY / ... / QI_WATCH / ...` | `core/arbiter.gd` + `core/monarch_ai.gd` | ⚠️ 实际代码用 `pressure/alienate/lure/prepare/seek_alliance/...`（无前缀） |
| §3.1-3.3 资产命名 | `portrait_qin_king` / `bg_audience_qin` / `card_persuade` 等 | 美术 `assets/` + 程序加载 | ✅ 一致 |
| §4 8 模块 Prompt 字段名 | `# 1. 角色定位 ... # 8. 输出 schema` | `core/monarch_ai.gd._build_prompt()` | ⚠️ 实际顺序为 [世界铁律/你是谁/关键事件/暗示/局势/动作/规则/输出] |
| §七.2 动作枚举中文/英文 | v7.3.7 统一为英文 | 所有 `data/*.json` | ✅ 一致（cards.json 全英文 / monarch_mock.json 国家名+动作 key 英文） |

**改 C05 时的检查清单（重磅变更）**：
- [ ] 改了类字段 → 全局搜索 `state.gd` + 所有业务类
- [ ] 改了枚举常量 → 全局搜索 `core/scripts/` 替换
- [ ] 改了资产 ID → 同步美术 `assets/` 文件名 + 程序加载代码
- [ ] 改了 8 模块字段顺序 → 同步 `core/monarch_ai.gd._build_prompt()` 模板

> ⚠️ **C05 变更必须通知三方**（策划/程序/美术），且需 `C05 §五 变更记录表` 登记。

> ⚠️ **v7.3.7 P1-3 修复**：C05 中 Phase 枚举已统一为 5 阶段（包含 AUDIENCE），但实际代码 `core/turn_manager.gd:9` 的 `PHASES` 数组不包含 AUDIENCE——**文档与代码仍未对齐**。

---

### 2.6 · C06 · 3 立场题库 6 题 → `data/mbti_questions.json`

> **位置**：`策划交付物/D1-策划交付物-20260630/C06-三立场题库6题.md`
> **运行时文件**：`res://data/mbti_questions.json`（**文件名保留 mbti 以兼容旧代码**，内容已改为三立场）
> **触发位置**：`scripts/main.gd._show_mbti_questions_for_round()`

**JSON 实际结构**（v7.3.7）：

```json
{
  "questions": [
    {
      "id": "q1",
      "round": 1,
      "text": "列国君主邀请你入幕。你会？",
      "options": [
        {"text": "接受赵国——合纵若成，赵是盟主", "score": "hezong"},
        {"text": "看谁出价更高——纵横家不站队",   "score": "neutral"},
        {"text": "接受秦国——得时则驾，不得则隐", "score": "qin"}
      ]
    },
    ... 6 题 ...
  ]
}
```

> ⚠️ **与 C05 契约差异**：
> - C05 §2.1 描述 `StanceQuestion` 字段含 `stance / default_on_timeout / timeout_seconds`
> - 实际 JSON 字段是 `score`（值同 stance 字符串）/ **无 `default_on_timeout`** / **无 `timeout_seconds`**
> - 实际超时：未实现（玩家必须回答才能继续）

**读取路径**：
- `core/data_loader.gd:7` `const PATH_MBTI = "res://data/mbti_questions.json"`
- `core/data_loader.gd:37-47` 加载逻辑
- `core/state.gd:24` `var stance_scores: Dictionary = {"hezong": 0, "neutral": 0, "qin": 0}`
- **消费方**：
  - `scripts/main.gd._show_mbti_questions_for_round()` line 130-145（按 round 取 1 题）
  - `scripts/main.gd._pop_mbti()` line 147-166（弹窗 → `State.record_mbti_answer`）

**改 C06 时的检查清单**：
- [ ] 改了题目措辞 → 改 `data/mbti_questions.json` 对应 `text` 字段
- [ ] 改了选项立场归属 → 改 `data/mbti_questions.json` 的 `score` 字段（值：hezong/neutral/qin）
- [ ] 改了计分规则 → 改 `core/state.gd.record_mbti_answer()` line 121-127
- [ ] **加超时** → 改 `scripts/main.gd._pop_mbti()` + `scripts/ui/mbti_popup.gd`（当前未实现）

---

### 2.7 · C07 · 9 评语 + 6 死亡 → `data/endings.json`

> **位置**：`策划交付物/D1-策划交付物-20260630/C07-9评语初稿.md` + `D3/C18-值死亡叙事+9评语终稿.md`
> **运行时文件**：`res://data/endings.json`

**JSON 实际结构**（v7.3.7 · 3 大段）：

```json
{
  "death": {
    "suspected_qin_spy": {"title": "疑为秦间", "text": "..."},
    "hezong_martyr":     {"title": "合纵成·身先死", "text": "..."},
    "silent_end":        {"title": "无声而终", "text": "..."},
    "tall_tree":         {"title": "木秀于林", "text": "..."},
    "no_move":           {"title": "无子可落", "text": "..."},
    "backfire":          {"title": "棋局反噬", "text": "..."}
  },
  "situation": {
    "alliance_victory":  {"title": "合纵却秦", "text": "..."},
    "lianheng_victory":  {"title": "连横破盟", "text": "..."},
    "undecided":         {"title": "纵横未决", "text": "..."}
  },
  "stance_review": {
    "hezong":  {"alliance_victory": "...", "lianheng_victory": "...", "undecided": "..."},
    "neutral": {"alliance_victory": "...", "lianheng_victory": "...", "undecided": "..."},
    "qin":     {"alliance_victory": "...", "lianheng_victory": "...", "undecided": "..."}
  }
}
```

> ⚠️ **与 C05 契约差异**：
> - C05 §2.2 描述 ending_type 为 `hezong_success / lianheng_break / undecided`（v7.3.7 P1-9 加的别名）
> - 实际 JSON `situation` 段 key 是 `alliance_victory / lianheng_victory / undecided`（**不同命名**）
> - 实际 JSON `stance_review` 段才是 3×3=9 评语，对应 C07 9 评语
> - 实际 JSON 字段是 `title / text`（C05 描述 `id / ending_type / stance / text` 不符）

**读取路径**：
- `core/data_loader.gd:10` `const PATH_ENDINGS = "res://data/endings.json"`
- `core/data_loader.gd:74-79` 加载逻辑
- `core/state.gd:47` `var endings: Dictionary`
- **消费方**：
  - `core/arbiter.gd.check_ending()` line 200-214（终局判定 → 返回 type+detail）
  - `core/arbiter.gd.judge_stance()` line 217-227（stance = hezong/neutral/qin）
  - `scripts/main.gd._go_ending()` line 677-686（写入 user://ending.dat → 切到 ending 场景）
  - `scripts/ui/ending.gd`（落幕屏读 ending.dat + `State.endings`）

**改 C07 时的检查清单**：
- [ ] 改了评语文本 → 改 `data/endings.json["stance_review"][stance][situation].text`
- [ ] 加了评语（如 6 种值死亡）→ 同步 `data/endings.json["death"]` 段
- [ ] 改了终局类型 / 立场名 → 同步 `core/arbiter.gd.check_ending()` 的判断条件

---

### 2.8 · C08 · 6 回合关键事件 → `data/key_events.json`

> **位置**：`策划交付物/D1-策划交付物-20260630/C08-总体剧本6回合.md` + `D2/C15-关键事件模板池+教程式首局.md`
> **运行时文件**：`res://data/key_events.json`

**JSON 实际结构**（v7.3.7）：

```json
{
  "events": [
    {
      "round_range": [1, 1],
      "state_tag": "qin_probe_zhao",
      "text": "秦使分赴各国——大棋局正在展开"
    },
    {
      "round_range": [2, 2],
      "state_tag": "zhao_qi_mengxin_low",
      "text": "秦拔宜阳，张仪携重礼入齐——'齐王若观望，三城即日奉上。'"
    }
  ]
}
```

> ⚠️ **与 C05 契约差异**：
> - C05/C08 描述字段 `round / theme / title / description / agent_topics / card_suggestions / stance_question / state_branches`
> - 实际 JSON 字段是 `round_range (Array) / state_tag / text`（**完全不同的 schema**）
> - 实际没有"6 回合各 1 条"的结构，而是每回合有多个候选（按 round_range 命中），随机抽 1 条

**读取路径**：
- `core/data_loader.gd:8` `const PATH_EVENTS = "res://data/key_events.json"`
- `core/data_loader.gd:49-59` 加载逻辑
- `core/state.gd:45` `var events: Array`
- **消费方**：
  - `scripts/main.gd._resolve_key_event()` line 182-199（按当前 round 匹配 round_range → 随机抽 1 条 → 写入 banner）
  - `core/agent_manager.gd.start_free_phase(event_tag, event_text)` line 46-58（传给 LLM prompt）

**改 C08 时的检查清单**：
- [ ] 改了回合事件描述 → 改 `data/key_events.json` 对应条目的 `text` 字段
- [ ] 改了回合范围 → 改 `round_range` 数组（不是 `round` 单值）
- [ ] 改了状态分支 → 通过 `state_tag` 字符串标识（C15 P1-22 已显式 KE_ROUND_5 3 个条件）
- [ ] 加了新回合 → 同步 `data/key_events.json` + `core/state.gd.max_round`（v7.3.7 = 6）

---

## 3 · 交付物版本与源码版本对应

| 交付物版本 | 源码 commit | 关键变更 | **v7.3.7 实际状态** |
|---|---|---|---|
| v7.3.1（D1 锁定） | 旧 | C08 6 回合 · C06 20s 超时（设计） | ✅ 设计稿已落 |
| v7.3.2 | 旧 | C08 6 回合单层 · C06 20s 超时 | ✅ 数据已落 |
| v7.3.3 | 旧 | 情报牌可消耗加成（+5%/张） | ✅ `scripts/main.gd:287` 已实施 |
| v7.3.4 | 旧 | 召见取消成功率/二值裁决 | ✅ 实施 |
| v7.3.5 | 旧 | 召见立场结算 | ⚠️ 简化为 `parse_dialogue` 综合分（**无 stance_aware_actions**） |
| **v7.3.6** | 旧 | RFC-001（玩家三维/单卡惩罚/终局阈值/国家三维 clamp） | ✅ 已实施 |
| **v7.3.7** | 旧（无 git 锚点） | RFC-002（面谈机制重设计）+ 秦国威 +5→+3 + 23 项 P1 修复 | ⚠️ 秦国威 +3 未实施 / stance_aware_actions 未实施 / 投降关键词未实施 / P1 修复已落 |

> ⚠️ **本项目无 git 历史锚点**——`warring-states-strategist/` 目录是干净的 Godot 工程，无 commit 记录。版本号仅在 `project_state.md` 与策划交付物中体现。

---

## 4 · 改交付物时的"反向追溯"流程

当你被命令"按 C0X 改 X 行为"时，按以下顺序操作：

```
1. 读 策划交付物/README.md（总索引）
     ↓
2. 读本文件 §0 总览表 找 C0X → §2 详细章节
     ↓
3. 检查 §2 标注的 ⚠️ 项（实际与契约差异）
     ↓
4. 修改前先 git status 确认无未提交残留（项目根无 .git，跳过）
     ↓
5. 改完用 §2 "改 C0X 时的检查清单" 逐项打勾
     ↓
6. 改 §0 总览表 / §3 版本对应表 / §5 待办（如有）
     ↓
7. 跑 Godot 编辑器加载游戏，验证运行时无报错
```

---

## 5 · 当前待办（v7.3.7 之后 · 代码 ↔ 契约 偏差清单）

> **本节是 v7.3.7 真正的待办**——文档定义了但代码未实施的关键项。

| # | 项 | 阻塞 | 位置 | 状态 |
|---|---|---|---|---|
| 1 | **秦国威漂移 +5→+3**（P0 漏修） | 否（数值调整） | `core/arbiter.gd:195` `State.apply_country_delta("qin", {"guowei": 5})` 改为 3 | ⏳ 待实施 |
| 2 | **stance_aware_actions 三分支**（P0-2/3/4） | 是 | `core/agent_manager.gd.on_player_stance()` 需补 if_hezong/if_qin/if_neutral 三分支 + 读 C12 `stance_aware_actions` 字段 | ⏳ 待实施 |
| 3 | **投降关键词映射中立**（P0-10） | 否 | `core/agent_manager.gd._direction_to_stance()` 需补 "降/投降/乞降/请降/归降" → neutral | ⏳ 待实施 |
| 4 | **C09–C11 mock 决策表 → 代码** | 否（mock 决策） | `data/mock_qin.json` / `mock_zhao.json` / `mock_qi.json` 已落盘但 `DataLoader` 不读。`core/agent_manager.gd` 需加 mock_qin/zhao/qi 加载 + `monarch_ai.gd.pick_action()` 需改造读 JSON 而非硬编码 | ⏳ 待决策（保持硬编码 or 切到 JSON） |
| 5 | **Card 类补 `target_country` 字段**（C05 §2.1） | 否 | `core/state.gd` 中 Card 类的 `target_country`（player 在打牌 UI 时设置，C05 描述为 Card 自带字段） | ⏳ 待决策 |
| 6 | **mbti_questions.json 补 `default_on_timeout` / `timeout_seconds`** | 否 | `data/mbti_questions.json` 当前 6 题都无超时（玩家必须答），C06 描述 20s 超时未实施 | ⏳ 待实施 |
| 7 | **Phase 枚举统一** | 否 | C05 §2.2 描述 `Phase { INIT, FREE_ACTION, ROUND_END, GAME_OVER, AUDIENCE }`，实际 `core/turn_manager.gd:9` 的 `PHASES` 数组是 `["mbti", "event", "draw", "free", "end"]`（含 mbti/event/draw/AUDIENCE 缺失） | ⏳ 待决策 |
| 8 | **Agent 动作枚举统一** | 否 | C05 §2.3 描述 `QIN_MILITARY / QIN_ALIENATE / ...`，实际 `core/arbiter.gd.settle_agent_action()` 用 `pressure/alienate/lure/prepare/...`（无前缀） | ⏳ 待决策 |
| 9 | **三立场题库 Q3 措辞** | 是 | C06 §Q3 + C23 §五 | ⏳ 用户拍板中（v7.3.7 建议方案 3） |
| 10 | **教程弹窗时序 + 顺序** | 否 | C15 §三 / §六.1 / §六.2 | ⏳ D3 试玩验证 |

> 🔒 改以上 #1–#8 任一项需走 RFC：先改 C0X 文档 → 通知策划/程序/美术三方评审 → 改代码 + 同步本指南。

---

## 6 · Autoloads 速查

> 本节速查 Godot 工程实际的 Autoload 注册情况。

| Autoload 名称 | 脚本路径 | 职责 |
|---|---|---|
| `State` | `res://scripts/core/state.gd` | 玩家三维 + 国家三维 + MBTI + 手牌 + 数据缓存 |
| `DataLoader` | `res://scripts/core/data_loader.gd` | JSON 加载（cards/mbti_questions/key_events/monarch_mock/endings） |
| `Arbiter` | `res://scripts/core/arbiter.gd` | 掷骰/裁决/漂移/终局判定/立场判定 |
| `AgentManager` | `res://scripts/core/agent_manager.gd` | 3 君主同步博弈调度（V3） |
| `LLMClient` | `res://scripts/core/llm_client.gd` | DeepSeek API 客户端（异步） |

> ⚠️ **`core/monarch_ai.gd` 不是 Autoload**——它是 `class_name MonarchAI`（RefCounted），由 `AgentManager` 通过 `preload` + `MonarchAIScript.make(country)` 实例化。

---

## 7 · 调用规则（D1–D4 全部 26 个文件 + 关联代码）

> 本章是 **AI Agent 调用策划交付物的强约束规约**。
> 任何 AI（Claude / Gemini / GPT）读 `策划交付物/` 之前，先通读本章；任何程序调用 `data/*.json` 之前，按本章 §7.1–§7.5 校验。

### 7.1 读取顺序规则（按任务类型分流）

| 任务类型 | 必读文件（按顺序） | 可选补充 |
|---|---|---|
| **A. 改某条具体数值/文案** | C0X 单文件 → `data/*.json` → `scripts/core/*.gd` | C05 契约 |
| **B. 新增一张情报牌/事件** | C14 或 C15 模板 → C05 schema → data JSON | C19 近臣台词 |
| **C. 调君主决策风格** | C16 三君主 prompt → C09–C11 mock 表 → `core/monarch_ai.gd` 硬编码 | C17 召见 prompt |
| **D. 改立场问卷/评语** | C06 题库 → C07 评语 → `data/mbti_questions.json` & `data/endings.json` | C18 落幕屏 |
| **E. 排查 bug** | C23 bug 清单 → C20/C21 试玩日志 → `core/*.gd` | — |
| **F. 调平衡参数** | C24 参数表 → `data/cards.json` + `core/arbiter.gd` 硬编码 | C20 试玩分布 |
| **G. 录屏/彩排/签字** | C25 彩排 → C26 签字单+录屏脚本 | C21 黄金路径 |

> ⚠️ **绝对不要** 在没有先读 C05 契约的情况下直接修改 `data/*.json` 字段名——即使实际 JSON 与契约有差异，**契约是规范的源头**，新代码必须向契约对齐（除非先走 RFC 更新契约）。

### 7.2 调用约束（硬性规则）

#### 7.2.1 字段名约束
- **snake_case**（下划线小写）用于所有 `data/*.json` 的 key
- **PascalCase** 用于 Godot 场景节点名、类名
- **不可中英混用**：`proposed_action` ≠ `proposedAction` ≠ `proposed_action_str`
- **校验工具**：每次改 `data/*.json` 后，对照本指南 §2 各 C0X 章节的"v7.3.7 实际结构"小节

#### 7.2.2 monarch_ai 实际调用契约（v7.3.7）

```gdscript
# ✅ 正确调用（v7.3.7 实际接口）
var ai = MonarchAIScript.make("qin")
var ctx: Dictionary = {
    "round": 1,                                   # 1 或 2
    "key_event_tag": "qin_probe_zhao",
    "key_event_text": "秦使分赴各国——大棋局正在展开",
    "country_attrs": State.country_attrs,         # 全部三国三维
    "player_attrs": State.player_attrs,           # 玩家三维
    "player_stance": "",                          # "" / "hezong" / "qin" / "neutral"
    "opponents_history": [],                      # 上一轮各君主动作
    "me_last_action": {}
}
ai.pick_action_async(ctx, func(action: Dictionary):
    # action 字段：actor, target_country, action_type, round, reason, narrative, expected_settle, confidence, source
    # expected_settle ∈ {"summon", "decided"}  (C05 §2.2 描述的 "audience/decision_made" 实际未用)
    # source ∈ {"llm", "mock:no_llm", "mock:persona_drift", "mock:invalid_schema", ...}
    pass
)

# ❌ 错误：旧版 agent_manager.ask_king 风格
var response = await call_llm("秦王", "你要不要和我结盟？")  # 缺 schema 校验
```

#### 7.2.3 LLMClient 实际调用契约（v7.3.7）

```gdscript
# ✅ 正确调用
var llm = Engine.get_main_loop().root.get_node_or_null("LLMClient")
if llm != null and llm.is_ready():
    llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 5.0, "temperature": 0.8, "response_json": true},
        func(parsed: Variant, err: String):
            if parsed == null or err != "":
                # 走 mock 兜底
                return
            # parsed 已是 Dictionary
        )

# ❌ 错误：直接 HTTPRequest
$HTTPRequest.request(...)  # 不走 LLMClient 配置
```

#### 7.2.4 v7.3.5/v7.3.7 面谈机制约束
- `parse_dialogue` 输出 `verdict: accept/reject`（基于综合分），**不输出 stance**
- 玩家三立场表态对应（在 `agent_manager.gd._direction_to_stance()`）：
  - `push_hezong` / `favor_hezong` → `hezong`
  - `push_qin` / `favor_lianheng` → `qin`
  - `neutral` → `neutral`
- **stance_aware_actions 三分支未实现**（详见 §5 #2）
- 判读优先级：**未在代码中实现**（C13 §三.2 描述的"推合纵 > 推亲秦 > 中立"仅在 C13 文档中）

### 7.3 D1–D4 全部 26 个文件索引

#### D1（2026-06-30 · 8 文件）— 数据基础

| 文件 | 落点 |
|---|---|
| `C01-三维度数值锁定表.md` | `data/stats_init.json`（**未落盘**，硬编码 `core/state.gd:14, 17-21`） |
| `C02-5行动牌参数表.md` | `data/cards.json` ✅ |
| `C03-6回合阶段流程.md` | `core/turn_manager.gd` + `scripts/main.gd._start_round_flow()` |
| `C04-终局判定矩阵.md` | `core/arbiter.gd.check_ending()` |
| `C05-设计契约.md` | **唯一权威** · 所有 `data/*.json` |
| `C06-三立场问卷-题库.md` | `data/mbti_questions.json` ✅ |
| `C07-9条评语终稿.md` | `data/endings.json`（`stance_review` 段） |
| `C08-6回合关键事件模板池.md` | `data/key_events.json` ✅ |

#### D2（2026-07-02 · 7 文件）— 行为决策

| 文件 | 落点 |
|---|---|
| `C09-mock决策表-秦王.md` | `data/mock_qin.json`（**DataLoader 不读**，详见 §5 #4） |
| `C10-mock决策表-赵王.md` | `data/mock_zhao.json`（同上） |
| `C11-mock决策表-齐王.md` | `data/mock_qi.json`（同上） |
| `C12-召见困局prompt模板.md` | `data/audience_dilemmas.json`（**未落盘**） |
| `C13-mock召见立场判读规则.md` | `core/agent_manager.gd._direction_to_stance()`（部分实现） |
| `C14-情报牌内容模板.md` | `data/intel_cards.json`（**未落盘**，情报牌由 `arbiter.gd._gen_intel()` 动态生成） |
| `C15-关键事件模板池+教程式首局.md` | `data/key_events.json` ✅ + `data/event_templates.json` ✅ |

#### D3（2026-07-02 · 7 文件）— LLM 联调

| 文件 | 落点 |
|---|---|
| `C16-三君主LLM-prompt终稿.md` | `core/monarch_ai.gd._build_prompt()`（硬编码） |
| `C17-召见打字Agent-prompt终稿.md` | `core/agent_manager.gd`（**未实现 LLM 路径**，仅 mock） |
| `C18-值死亡叙事+9评语终稿.md` | `data/endings.json`（`death` + `stance_review` 段） |
| `C19-近臣台词片段.md` | `core/monarch_ai.gd._build_prompt()` 中 `advisor_defs` |
| `C20-9条评语联调.md` | 联调报告（不落代码） |
| `C21-黄金路径试玩.md` | 测试用例 |
| `C22-LLM局试玩.md` | 测试用例 + 4 bug 记录 |

#### D4（2026-07-02 · 4 文件）— Bug 修复与定稿

| 文件 | 落点 |
|---|---|
| `C23-bug-fix.md` | 修复已合入代码（P0/P1 全部 36 项） |
| `C24-平衡参数调整.md` | `data/cards.json` 参数已调 |
| `C25-彩排2局.md` | 彩排记录 |
| `C26-最终签字+录屏脚本定稿.md` | 签字单归档 |

### 7.4 错误处理（数据缺失/字段错误）

| 错误类型 | 触发条件 | 降级方案 | 校验文件 |
|---|---|---|---|
| **数据文件不存在** | `data/foo.json` FileNotFound | 启动报错 + 提示运行 `tools/init_data.gd` | `core/data_loader.gd:8` |
| **JSON 解析失败** | 语法错 | 启动报错 + 提示行号 | `core/data_loader.gd:96-99` |
| **必填字段缺失** | 缺 `id` / `name` 等 | `null` 跳过 | `core/data_loader.gd:33-35` |
| **LLM 超时（5s/8s）** | mock 兜底 | 记日志 + 走 mock | `core/monarch_ai.gd:97-101` |
| **关键词表无匹配** | 玩家输入不含任何关键词 | 综合分 = 基线 2.0 | `core/arbiter.gd.parse_dialogue()` |
| **评语 ID 不存在** | `endings.json` 缺 key | 走"纵横未决·中立"默认 | `scripts/ui/ending.gd` |
| **6 终局阈值漂移** | stats 数值越界 [0,100] | 钳制到边界 + 警告 | `core/state.gd:82, 97` |
| **教程触发时序错** | round≠1 时触发教程 | 跳过 + 警告 | `scripts/main.gd._resolve_key_event()` |
| **apikey 为空** | `user://config.cfg` 无 `api_key` | 启动警告 + 走 mock 兜底 | `core/llm_client.gd:55-57` |

### 7.5 不可改项清单（v7.3.7 锁定 · 改动需走 RFC）

以下项 **已被 v7.3.7 锁定**，任何 AI / 程序不得擅自修改：

| 锁定项 | 数值/枚举 | 锁定原因 | 引用 |
|---|---|---|---|
| **9 条评语文本** | `data/endings.json["stance_review"][stance][situation].text` | C07 9 评语锁版，录屏脚本依赖 | C07 + C18 |
| **6 死亡叙事文本** | `data/endings.json["death"][key].text` | 6 死亡锁版 | C18 |
| **3 君主 ID** | `qin_king` / `zhao_king` / `qi_king` | C05 契约 | C05 §3.2.1 |
| **5 行动牌 ID** | `persuade` / `message` / `promise` / `alienate` / `spy` (+ `audience` 内置) | C05 契约 | C05 §2.2 |
| **3 立场选项** | `tui_hezhong` / `zhongli_zibao` / `tui_qin`（C13 描述）/ `hezong` / `neutral` / `qin`（C06 实际） | v7.3.5 新增 | C06 + C13 |
| **6 终局阈值** | 合纵：赵盟信≥55 AND 齐盟信≥55 AND 秦国威≤75<br>连横：赵/齐 盟信≤30 AND 秦国威≥80 | C01 §3.1 v7.3.6 | C01 |
| **3 君主 8 模块 prompt** | 见 `monarch_ai.gd._build_prompt()` 实际段落 | C16 调优完成 | C16 |
| **玩家三维初始值** | `{hezong: 40, "mingwang": 50, "xinji": 40}`（v7.3.7 代码实际） | 录制基准 | C01 §一 |
| **国家三维初始值** | 秦 70/30/60 · 赵 50/60/40 · 齐 55/45/25 | 录制基准 | C01 §一 |
| **国家三维取值范围** | 0–100 **clamp**（v7.3.6） | 录制基准 | C01 §三 |
| **单卡方向幅度** | 游说推合纵 合纵+8 / 推亲秦 合纵−8 / 传信 +5 / −5 / 离间分支 / 许诺结盟+3 | v7.3.7 | C01 §1.1 + C02 |
| **齐·中立候盟动作** | 齐 init 分支默认 `observation` | C11 §2.1 | C11 |
| **情报牌消耗加成** | **每张 +5%**（v7.3.4 从 +10% 降为 +5%） | 录制基准 | C02 §三.8 |
| **6 回合结构** | round 1–6 | C03 | C03 |
| **情报牌加成公式** | `+5% / 张，封顶 95%` | v7.3.3 | C02 §五.4 |
| **stance_aware_actions 字段** | `{if_hezong, if_qin, if_neutral}` 三分支（**策划稿，代码未实现**，见 §5 #2） | v7.3.7 新增 | C12 §七 |
| **投降关键词映射** | "降/投降/乞降/请降/归降" → 中立（**策划稿，代码未实现**，见 §5 #3） | v7.3.7 新增 | C13 §2.3 |
| **mbti_questions 字段** | `id / round / text / options[].text / options[].score`（C06 实际） | 录制基准 | C06 |

> 🔒 改以上任何一项必须走 RFC：先改 C0X 文档 → 通知策划/程序/美术三方评审 → 走独立 commit。

### 7.6 跨任务一致性检查清单（修改前必跑）

每次改任意 C0X 文件，**必须**用以下清单自检：

```
[ ] §7.5 不可改项清单：本次修改未触碰任何锁定项
[ ] §7.2.1 字段名约束：所有 key 都是 snake_case
[ ] §2 各 C0X "v7.3.7 实际结构"：新字段与实际 JSON schema 一致
[ ] §5 当前待办：本次修改未触碰 #1–#8（除非走 RFC）
[ ] §7.4 错误处理：异常路径有 mock 兜底
[ ] 跨 C0X 一致性：
    [ ] 改了 cards.json → 同步 C02 5 行动牌参数表
    [ ] 改了 mbti_questions.json → 同步 C06 题库
    [ ] 改了 key_events.json → 同步 C08/C15 关键事件
    [ ] 改了 endings.json → 同步 C07/C18 评语
    [ ] 改了 monarch_ai.gd 硬编码 → 同步 C16 prompt 终稿
[ ] 加载游戏验证：Godot 编辑器运行无报错
[ ] §0 总览表：v7.3.7 状态列已对照过
```

### 7.7 升级流程（C0X → 代码 → 验证）

```
步骤 1: 改 C0X 源文档
   ↓
步骤 2: 同步 data/*.json（按 §7.3 索引）
   ↓
步骤 3: 同步 scripts/core/*.gd（按 §7.3 落点）
   ↓
步骤 4: 加载 Godot 工程 + 运行 main.tscn（无报错即过）
   ↓
步骤 5: 跑黄金路径（按 C21）：6 回合到终局
   ↓
步骤 6: 跑边界路径：6 种值死亡各 1 次
   ↓
步骤 7: 更新本 guide 文件 §0/§2/§5（标 ✓/⚠️/⏳）
   ↓
步骤 8: 等用户明确指令再提交（默认不主动 commit）
```

### 7.8 速查卡（5 秒定位）

| 你想…… | 读这份 | 改这里 |
|---|---|---|
| 改玩家三维数值 | C01 | `core/state.gd:14` |
| 改国家三维初值 | C01 | `core/state.gd:17-21` |
| 改漂移秦国威 | C01 | `core/arbiter.gd:195` ⚠️ |
| 改 5 行动牌参数 | C02 | `data/cards.json` |
| 改方向枚举 | C02 | `data/cards.json` + `core/arbiter.gd.roll_card()` |
| 改情报牌加成 | C02 | `scripts/main.gd:287` |
| 改 6 回合结构 | C03 | `core/state.gd.max_round` + `data/key_events.json` |
| 改终局判定 | C04 | `core/arbiter.gd.check_ending()` |
| 改字段名（谨慎！） | C05 | 全局搜索 + 同步所有 `data/*.json` |
| 改立场问卷 | C06 | `data/mbti_questions.json`（字段 `score`） |
| 改 9 评语 | C07 | `data/endings.json["stance_review"]` |
| 改 6 死亡叙事 | C18 | `data/endings.json["death"]` |
| 改关键事件 | C08 / C15 | `data/key_events.json`（字段 `state_tag/text`） |
| 改 mock 决策（策划稿） | C09 / C10 / C11 | `core/monarch_ai.gd.make()` 硬编码（JSON 未读）⚠️ |
| 改召见困局 | C12 | `data/audience_dilemmas.json`（**未落盘**） |
| 改立场判读 | C13 | `core/agent_manager.gd._direction_to_stance()` |
| 改情报牌 | C14 | `core/arbiter.gd._gen_intel()` 动态生成 |
| 改 LLM prompt | C16 / C17 | `core/monarch_ai.gd._build_prompt()` 硬编码 |
| 改近臣台词 | C19 | `core/monarch_ai.gd._build_prompt()` `advisor_defs` |
| 查试玩日志 | C20 / C21 / C22 | — |
| 查 bug 记录 | C23 | — |
| 调平衡参数 | C24 | `data/cards.json` + `core/arbiter.gd` |
| 查彩排/录屏 | C25 / C26 | — |

---

## 8 · P1 修复总览（v7.3.7 · 23 项）

> **本节是 v7.3.7 P1 修复记录的快速索引**。详细报告见 `质量报告/修复总报告-v7.3.7-20260702.md` 与 `质量报告/P1修复总报告-v7.3.7-20260702.md`。

| 批次 | 修复项 | 范围 |
|---|---|---|
| **A · 字段/枚举一致性** | P1-1, P1-3, P1-5, P1-6, P1-12, P1-19 | C05 契约 + C09–C12 + C17 |
| **B · 数值/阈值/机制** | P1-2, P1-8, P1-9, P1-10, P1-11, P1-13, P1-14, P1-21 | C01/C02/C09/C10 |
| **C · 节奏/顺序/触发** | P1-7, P1-16, P1-22 | C04/C15 |
| **D · prompt/schema** | P1-15, P1-17, P1-18 | C12/C16 |
| **E · 试玩残留** | P1-20, P1-23 | C06/C23 |

---

## 9 · 联系方式

- **策划主笔**：ruohaojing（`@htalk:cdp:group:2522504863:seq61` 群聊可 @）
- **设计文档仓库**：`warring-states-strategist/v7.3.2-纵横RTS/v7-纵横RTS/` 16 篇源文档
- **项目根 README**：`warring-states-strategist/README.md`
- **总索引**：`策划交付物/README.md`

---

> **本文件用途**：让 AI Agent / 程序同事 5 分钟读懂"策划交付物在项目里怎么用"。
>
> **维护者**：策划/程序共同维护。改了 C0X 必须同步更新本指南。
>
> **版本**：v2.0（2026-07-02 v7.3.7 配套 · 与代码实际状态对齐 · 新增 §5 待办清单 + §6 Autoloads + §8 P1 总览）
