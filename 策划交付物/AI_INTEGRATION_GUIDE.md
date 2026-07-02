# 策划交付物 · AI 集成指南（v7.3.5 · 2026-07-02）

> **目的**：让程序或 AI Agent 在**第一次接触项目**时，仅凭本文件就能定位"每个 C0X 交付物是什么、应该落到代码的哪一处、被哪个类加载"。
>
> **面向对象**：
> - 程序同事（接入新交付物时第一查的文件）
> - AI 编程助手（被命令"按交付物改 X 行为"时的索引文件）
> - 后续 D2/D3/D4 策划交付物的索引范本
>
> **本目录结构**：
> ```
> 策划交付物/
> └── AI_INTEGRATION_GUIDE.md            ← 本文件（你正在读）
> └── D1-策划交付物-20260630/            ← D1 全部交付物（8 个 C0X）
>     ├── README.md                      ← D1 进度总览
>     ├── C01-数值系统-锁定表.md
>     ├── C02-卡牌效果与方向选择-锁定表.md
>     ├── C03-三君主persona卡片.md
>     ├── C04-五近臣权重与视觉表.md
>     ├── C05-设计契约.md
>     ├── C06-三立场题库6题.md
>     ├── C07-9评语初稿.md
>     └── C08-总体剧本6回合.md
> ```
>
> **版本对应**：v7.3.5（召见面谈立场结算 · 2026-07-02 ea86f2d 修正版）

---

## 0 · 30 秒总览（先看这张表）

> **改了策划交付物 → 改项目里哪里？** 一图回答。

| 交付物 | 锁定什么 | **落到 `data/` 的 JSON** | **被 `scripts/` 哪个类读取** | **同步源文档** |
|---|---|---|---|---|
| **C01** 数值系统 | 玩家/国家三维初值、漂移、终局阈值、面谈立场结算 | （硬编码在 `state.gd`） | `core/state.gd`（初值）+ `core/arbiter.gd`（漂移/终局/动作效果表） | `03-数值系统.md` §一 §二 |
| **C02** 卡牌 + 方向 + 情报牌 | 5 牌效果、方向枚举、情报牌加成公式 | **`cards.json`** | `core/data_loader.gd` → `core/state.gd.all_cards` → `core/arbiter.gd`（掷骰）+ `core/turn_manager.gd`（打牌 UI） | `05-卡牌设计.md` §一 §二 |
| **C03** 3 君主 persona | 性格/核心利益/可用动作/近臣/记忆/决策规则/输出 schema | **`monarch_mock.json`**（仅 mock 决策表） | `core/data_loader.gd` → `core/state.gd.monarch_mock` → `core/monarch_ai.gd.pick_action()`（mock 路径）<br>**LLM 路径**：注入到 `core/agent_manager.gd` 8 模块 system prompt | `04-Agent架构.md` + `11b-角色设计稿-程序.md` |
| **C04** 5 近臣权重 + 视觉 | 近臣权重表 + Prompt 注入片段 + 视觉关键词 | `monarch_mock.json`（权重部分）<br>`assets/portraits/` `assets/silhouettes/`（视觉部分） | mock：同 C03<br>LLM：注入到 `agent_manager.gd` 8 模块 §5"近臣倾向"<br>美术：依 ID 命名加载 | `04-Agent架构.md` §四 + `11a-角色设计稿-美术.md` |
| **C05** 设计契约 | 类名/字段名/资产 ID/prompt 字段名（**唯一权威**） | （**不是数据，是规范**）<br>所有 json 的字段必须按本契约命名 | `core/state.gd`（类字段）+ `core/data_loader.gd`（路径常量）+ `core/agent_manager.gd`（8 模块 prompt 字段名）+ 美术资产加载 | 全 v7-纵横RTS |
| **C06** 3 立场题库 6 题 | Q1–Q6 题面、计分规则、超时 | **`mbti_questions.json`** | `core/data_loader.gd` → `core/state.gd.all_questions` → `scripts/main.gd._show_mbti_questions_for_round()` | `08-结局设计.md` §2.2 |
| **C07** 9 评语 | 3 终局 × 3 立场 = 9 条 | **`endings.json`** | `core/data_loader.gd` → `core/state.gd.endings` → `core/arbiter.gd`（终局匹配） | `08-结局设计.md` §六 |
| **C08** 6 回合关键事件 | 6 回合主题、状态分支、调用接口 | **`key_events.json`** | `core/data_loader.gd` → `core/state.gd.events` → `core/turn_manager.gd`（回合开始注入） → `core/agent_manager.gd`（关键事件注入 prompt） | `12-总体剧本.md`（结构已改造为 6 回合单层） |

> **核心原则**：策划交付物**只产出 markdown + JSON 数据**；**不直接生成代码**。所有代码侧的字段名、ID、枚举必须严格遵循 **C05 设计契约**。

---

## 1 · 数据流：从交付物到运行时

```
策划交付物 (.md)
  │
  ├─── 程序手动转写为 data/*.json（按 C05 字段名）
  │      ↓
  │    res://data/cards.json
  │    res://data/mbti_questions.json
  │    res://data/key_events.json
  │    res://data/monarch_mock.json
  │    res://data/endings.json
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
  │      ├── core/arbiter.gd        (C01 数值 / C02 牌效果 / C07 评语匹配)
  │      ├── core/monarch_ai.gd     (C03/C04 mock 决策)
  │      ├── core/agent_manager.gd  (C03/C04 LLM 决策 · 8 模块 prompt)
  │      ├── core/turn_manager.gd   (C08 关键事件注入)
  │      ├── core/llm_client.gd     (LLM 通信)
  │      ├── scripts/main.gd        (C06 立场问卷触发)
  │      └── scripts/ui/dialogue.gd (C03 persona · C07 评语展示)
```

---

## 2 · 逐文件详解

### 2.1 · C01 · 数值系统 → `core/state.gd` + `core/arbiter.gd`

> **位置**：`策划交付物/D1-策划交付物-20260630/C01-数值系统-锁定表.md`

| 章节 | 锁定内容 | 落到代码哪里 |
|---|---|---|
| §一 玩家三维初值 | `{hezong:40, mingwang:50, xinji:40}` | `core/state.gd` 第 14 行 `var player_attrs: Dictionary` |
| §一 国家三维初值 | 秦 70/30/60 · 赵 50/60/40 · 齐 55/45/25 | `core/state.gd` 第 17–21 行 `var country_attrs: Dictionary` |
| §1.2 面谈立场结算 | 推合纵/推亲秦=背书 → 国家三维生效；中立=君主自决 | `core/agent_manager.gd`（`on_player_stance()`）；**待 D3 LLM 接入后实现** |
| §1.3 面谈超时降级 | 关键词：合/纵/盟/抗秦 → 推合纵；横/连横/亲秦 → 推亲秦 | `core/agent_manager.gd`（fallback mock） |
| §二 漂移参数 | 每 2 回合触发：合纵 −4、名望 −2、心计 −3、秦国威 +5 等 6 项 | `core/turn_manager.gd._apply_drift()`（每 2 回合开始时调用） |
| §3.1 终局阈值 | 三条件：合纵却秦 / 连横破盟 / 纵横未决 | `core/arbiter.gd.check_ending()` |
| §3.2 Agent 动作影响 | 11 项动作的国威/盟信/战心变化 | `core/arbiter.gd` 的动作效果表（`ACTION_EFFECTS`） |
| §四 二值判定公式 | `clamp(基础 + 对应数值 × 系数 + 消耗情报牌数 × 5%, 5%, 95%)` | `core/arbiter.gd.roll_success()` |
| §五 6 种值死亡叙事 | 6 段文言叙事 | `core/arbiter.gd` 或独立 `data/death_narratives.json`（**待补**） |

**改 C01 时的检查清单**：
- [ ] 改了玩家/国家三维初值 → 改 `core/state.gd` 第 14/17–21 行
- [ ] 改了动作效果表 → 改 `core/arbiter.gd` 的 `ACTION_EFFECTS` 常量
- [ ] 改了终局阈值 → 改 `core/arbiter.gd.check_ending()`
- [ ] 改了成功率公式 → 改 `core/arbiter.gd.roll_success()`
- [ ] 改面谈立场语义 → 改 `core/agent_manager.gd`（v7.3.5 新增 `player_stance` 结算路径）

---

### 2.2 · C02 · 卡牌 + 方向 + 情报牌 → `data/cards.json`

> **位置**：`策划交付物/D1-策划交付物-20260630/C02-卡牌效果与方向选择-锁定表.md`
> **运行时文件**：`res://data/cards.json`

**JSON 结构**（与 C05 §2.1 `Card` 类对应）：

```json
{
  "cards": [
    {
      "type": "PERSUADE",                     // 枚举见 C05 §2.2
      "name_zh": "游说",
      "base_rate": 40,                        // 基础成功率
      "bonus_attr": "mingwang",               // 加成来源（hezong/mingwang/xinji）
      "bonus_coef": 0.3,
      "needs_direction": true,                // 必选方向
      "directions": ["PUSH_HEZONG", "PUSH_QIN", "NEUTRAL_ADVICE"],
      "effects_on_success": {
        "PUSH_HEZONG":      {"hezong": 8, "mingwang": 3, "xinji": 3, "intel_card": 1},
        "PUSH_QIN":         {"hezong": -8, "mingwang": 3, "xinji": 3, "intel_card": 1},
        "NEUTRAL_ADVICE":   {"mingwang": 5, "xinji": 3, "intel_card": 1}
      },
      "effect_on_fail": {"mingwang": -3}
    },
    ... ALIENATE / SPY / PROMISE / DISPATCH ...
  ]
}
```

**读取路径**：
- `core/data_loader.gd:6` `const PATH_CARDS = "res://data/cards.json"`
- `core/data_loader.gd:21-35` 加载逻辑
- `core/state.gd:43` `var all_cards: Array = []`
- **消费方**：`core/turn_manager.gd`（打牌 UI）+ `core/arbiter.gd`（掷骰/结算）

**关键参数（v7.3.3 → v7.3.4 改过）**：
- 情报牌加成 `INTEL_BONUS_PER_CARD = 5`（每张 +5%，v7.3.4 由 +10% 调整）
- 加成公式 `clamp(基础 + 数值×系数 + 消耗牌数×5, 5, 95)`

**改 C02 时的检查清单**：
- [ ] 改了牌效果表 → 改 `data/cards.json`
- [ ] 改了方向枚举 → 同步 `core/state.gd` 的 `Card.direction` 字段 + `C05 §2.2`
- [ ] 改了情报牌加成 → 改 `core/state.gd` 的 `INTEL_BONUS_PER_CARD` 常量
- [ ] 加了新牌 → 同步 `core/scripts/ui/dialogue.gd`（牌 UI）+ `assets/ui/cards/card_xxx.png`

---

### 2.3 · C03 · 3 君主 persona → `data/monarch_mock.json` + LLM prompt

> **位置**：`策划交付物/D1-策划交付物-20260630/C03-三君主persona卡片.md`

**双路径使用**：

| 路径 | 落到哪里 | 内容 |
|---|---|---|
| **Mock 决策路径**（LLM 不可用时） | `data/monarch_mock.json` → `core/monarch_ai.gd.pick_action()` | 性格 → 动作权重表（决策表） |
| **LLM 决策路径** | `core/agent_manager.gd` 8 模块 system prompt | 8 模块完整 prompt（性格画像/核心利益/可用动作/近臣倾向/记忆/决策规则/输出 schema） |

**`monarch_mock.json` 结构示例**：

```json
{
  "qin": {
    "name": "秦王嬴稷",
    "personality": "雄猜",
    "actions": {
      "军事施压":  {"weight": 1.0, "conditions": ["any"]},
      "遣使离间":  {"weight": 1.2, "conditions": ["hezhong_sign_detected"]},
      "连横利诱":  {"weight": 1.0, "conditions": ["target_hesitant"]},
      "备战蓄力":  {"weight": 0.6, "conditions": ["need_consolidate"]}
    },
    "minister_weights": {
      "张仪": {"连横利诱": 1.5, "备战蓄力": 0.6},
      "魏冉": {"军事施压": 1.4}
    },
    "decision_priority": ["遣使离间", "连横利诱", "军事施压", "备战蓄力"]
  },
  "zhao": { ... },
  "qi":   { ... }
}
```

**LLM prompt 8 模块**（C03 §卡片 1–3 完整版 → `core/agent_manager.gd._build_system_prompt(country)`）：

```
# 1. 角色定位       ← C03 §1 性格档案
# 2. 性格画像       ← C03 §1 性格档案
# 3. 核心利益       ← C03 §1 核心利益/最害怕
# 4. 可用动作       ← C03 §2 可用博弈动作（4 个）
# 5. 近臣倾向       ← C04 §2.2 Prompt 注入片段（5–10 字短句）
# 6. 记忆滚动摘要   ← 运行时由 arbiter.gd 每轮生成
# 7. 决策规则       ← C03 §6 LLM 决策关键词
# 8. 输出 schema    ← C03 §7 输出 JSON 模板
```

**改 C03 时的检查清单**：
- [ ] 改了 persona 内容（性格/核心利益/动作）→ 同步两处：`data/monarch_mock.json` + `core/agent_manager.gd` 8 模块
- [ ] 加了新动作枚举 → 同步 `C05 §2.3` 动作常量 + `C03 §2` 动作表
- [ ] 改了输出 schema → 同步 `core/monarch_ai.gd` 的 JSON 解析
- [ ] 改了决策规则优先级 → 同步 mock 决策表的 `decision_priority`

---

### 2.4 · C04 · 5 近臣权重 + 视觉 → `data/monarch_mock.json` + `assets/`

> **位置**：`策划交付物/D1-策划交付物-20260630/C04-五近臣权重与视觉表.md`

**双轨使用**：

| 维度 | 落到哪里 |
|---|---|
| **程序权重** | `data/monarch_mock.json` 的 `minister_weights` 字段（与 C03 同文件） |
| **LLM Prompt 注入** | `core/agent_manager.gd` 8 模块 §5"近臣倾向" |
| **美术视觉** | `assets/portraits/ministers/portrait_xxx.png` + `assets/silhouettes/ministers/silhouette_xxx.png` |

**资源 ID 命名（与 C05 §3.2.3 对齐）**：

```
portrait_zhangyi.png       silhouette_zhangyi.png
portrait_weiran.png        silhouette_weiran.png
portrait_pingyuanjun.png   silhouette_pingyuanjun.png
portrait_lianpo.png        silhouette_lianpo.png
portrait_mengchangjun.png  silhouette_mengchangjun.png
```

**Prompt 注入示例**（秦王 C04 §2.2 张仪片段）：

```markdown
# 5. 近臣倾向
- **张仪**（连横第一推手）：当你想用"连横利诱"时，他低声说："齐王贪利，许以三城可定。"
  权重影响：连横利诱动作的 confidence +2。
- **魏冉**（穰侯）：当你犹豫时，他低声说："战机稍纵即逝。"
  权重影响：军事施压动作的 confidence +1。
```

**改 C04 时的检查清单**：
- [ ] 改了权重表 → 改 `data/monarch_mock.json` 的 `minister_weights`
- [ ] 改了 prompt 注入片段 → 改 `core/agent_manager.gd` 8 模块 §5
- [ ] 加了新近臣 → 同步 `C04 §一` 视觉表 + `C05 §3.2.3` 资源 ID + 美术出图

---

### 2.5 · C05 · 设计契约 → **所有代码的字段名权威**

> **位置**：`策划交付物/D1-策划交付物-20260630/C05-设计契约.md`
> **重要**：本文件**不是数据**，是**规范**。所有代码侧的字段名/ID/枚举必须严格遵循。

**契约包含**：

| 章节 | 锁定内容 | 同步到代码哪里 |
|---|---|---|
| §2.1 核心类 | `GameState / Player / Country / Agent / Card / IntelCard / RoundLog` 字段表 | `core/state.gd` 全部类定义 |
| §2.2 枚举常量 | `Phase / QIN/ZHAO/QI / HEZONG/ZHONGLI/QINQIN / PERSUADE/ALIENATE/... / PUSH_HEZONG/...` | `core/state.gd` + 各业务类 |
| §2.3 Agent 动作枚举 | `QIN_MILITARY / QIN_ALIENATE / ... / ZHAO_ALLY / ... / QI_WATCH / ...` | `core/arbiter.gd` + `core/monarch_ai.gd` |
| §3.1-3.3 资产命名 | `portrait_qin_king` / `bg_audience_qin` / `card_persuade` 等 | 美术 `assets/` + 程序加载 |
| §4 8 模块 Prompt 字段名 | `# 1. 角色定位 ... # 8. 输出 schema` | `core/agent_manager.gd._build_system_prompt()` |

**改 C05 时的检查清单（重磅变更）**：
- [ ] 改了类字段 → 全局搜索 `state.gd` + 所有业务类
- [ ] 改了枚举常量 → 全局搜索 `core/scripts/` 替换
- [ ] 改了资产 ID → 同步美术 `assets/` 文件名 + 程序加载代码
- [ ] 改了 8 模块字段顺序 → 同步 `core/agent_manager.gd` 模板

> ⚠️ **C05 变更必须通知三方**（策划/程序/美术），且需 `C05 §五 变更记录表` 登记。

---

### 2.6 · C06 · 3 立场题库 6 题 → `data/mbti_questions.json`

> **位置**：`策划交付物/D1-策划交付物-20260630/C06-三立场题库6题.md`
> **运行时文件**：`res://data/mbti_questions.json`（**文件名保留 mbti 以兼容旧代码**，内容已改为三立场）
> **触发位置**：`scripts/main.gd._show_mbti_questions_for_round()`

**JSON 结构**（与 C05 `StanceQuestion` 类对应）：

```json
{
  "questions": [
    {
      "id": "Q1",
      "round": 1,
      "scene_hint": "列国君主邀请你入幕。你会？",
      "options": [
        {"key": "A", "text": "接受赵国——合纵若成，赵是盟主",  "stance": "hezong"},
        {"key": "B", "text": "看谁出价更高——纵横家不站队",    "stance": "zhongli"},
        {"key": "C", "text": "接受秦国——得时则驾，不得则隐",  "stance": "qinqin"}
      ],
      "default_on_timeout": "B",
      "timeout_seconds": 20
    },
    ... Q2-Q6 ...
  ]
}
```

**读取路径**：
- `core/data_loader.gd:7` `const PATH_MBTI = "res://data/mbti_questions.json"`
- `core/data_loader.gd:37-47` 加载逻辑
- `core/state.gd:24-25` `var stance_scores: Dictionary`
- **消费方**：`scripts/main.gd._show_mbti_questions_for_round()`（每回合开始弹 1 题）

**改 C06 时的检查清单**：
- [ ] 改了题目措辞 → 改 `data/mbti_questions.json` 对应题目
- [ ] 改了选项立场归属 → 改 `data/mbti_questions.json` 的 `stance` 字段
- [ ] 改了超时时长 → 改 `data/mbti_questions.json` 的 `timeout_seconds`
- [ ] 改了计分规则 → 改 `core/arbiter.gd` 的 `stance_score` 累加逻辑

---

### 2.7 · C07 · 9 评语 → `data/endings.json`

> **位置**：`策划交付物/D1-策划交付物-20260630/C07-9评语初稿.md`
> **运行时文件**：`res://data/endings.json`

**JSON 结构**：

```json
{
  "endings": [
    {
      "id": "E01",
      "ending_type": "hezong_success",       // 3 种：hezong_success / lianheng_break / undecided
      "stance": "hezong",                      // 3 种：hezong / zhongli / qinqin
      "text": "函谷关外，六国旌旗猎猎。你站在盟旗下，热泪盈眶——..."
    },
    ... 共 9 条（3 终局 × 3 立场）...
  ]
}
```

**读取路径**：
- `core/data_loader.gd:10` `const PATH_ENDINGS = "res://data/endings.json"`
- `core/data_loader.gd:74-79` 加载逻辑
- `core/state.gd:47` `var endings: Dictionary`
- **消费方**：`core/arbiter.gd`（终局判定后查表：`endings.find(e => e.ending_type == cur_ending && e.stance == player_stance)`）

**改 C07 时的检查清单**：
- [ ] 改了评语文本 → 改 `data/endings.json` 对应条目的 `text` 字段
- [ ] 加了评语（如 6 种值死亡）→ 同步 `core/arbiter.gd` 的查表逻辑
- [ ] 改了终局类型 / 立场名 → 同步 `C05 §2.2` 枚举

---

### 2.8 · C08 · 6 回合关键事件 → `data/key_events.json`

> **位置**：`策划交付物/D1-策划交付物-20260630/C08-总体剧本6回合.md`
> **运行时文件**：`res://data/key_events.json`

**JSON 结构**：

```json
{
  "events": [
    {
      "round": 1,
      "theme": "初露锋芒",
      "title": "秦使分赴各国——大棋局正在展开",
      "description": "秦王遣内史腾携国书入赵...与此同时，张仪未至但秦的国书已先一步送到临淄...",
      "agent_topics": {
        "秦": "试探赵的虚实 + 评估赵齐关系 + 留下连横伏笔",
        "赵": "要不要接见秦使？",
        "齐": "渔利派得意——让秦赵先斗"
      },
      "card_suggestions": ["游说-推合纵-赵", "刺探-秦", "传信-利好合纵-齐"],
      "stance_question": "Q1",
      "state_branches": null
    },
    {
      "round": 2,
      ...
      "state_branches": [
        {"condition": "prev_zhao_qi_mengxin_sum < 70",  "template": "秦拔宜阳，张仪携重礼入齐——'齐王若观望，三城即日奉上。'"},
        {"condition": "prev_zhao_qi_mengxin_sum >= 70", "template": "秦急遣使分赴赵齐——'谁先动，秦就先打谁。'离间之计，赤裸裸摆在台面上。"}
      ]
    },
    ... 3-6 ...
  ]
}
```

**读取路径**：
- `core/data_loader.gd:8` `const PATH_EVENTS = "res://data/key_events.json"`
- `core/data_loader.gd:49-59` 加载逻辑
- `core/state.gd:45` `var events: Array`
- **消费方**：
  - `core/turn_manager.gd`（回合开始时注入 banner）
  - `core/agent_manager.gd`（注入到 3 君主 prompt 的"# 本回合关键事件"段）

**状态分支阈值（C08 §六）**：

| 阈值 | 数值 | 用途 |
|---|---|---|
| 第 2/3 回合"赵齐盟信和 < 70" | 70 | 状态分支 A/B 选择 |
| 第 4 回合"前三回合赵齐盟信均值 ≥ 60" | 60 | 模板 A 触发 |
| 第 4 回合"秦国威 ≥ 80" | 80 | 模板 B 触发 |
| 第 6 回合"秦国威 ≥ 80" | 80 | 决战/求和选择 |

**改 C08 时的检查清单**：
- [ ] 改了回合事件描述 → 改 `data/key_events.json` 对应 round 的 `description`
- [ ] 改了状态分支阈值 → 改 `C08 §六` 数值 + 同步 `core/turn_manager.gd` 的判断逻辑
- [ ] 加了新回合事件 → 同步 `core/state.gd.max_round` + `C06` 立场问卷题数

---

## 3 · 交付物版本与源码版本对应

| 交付物版本 | 源码 commit | 关键变更 |
|---|---|---|
| v7.3.1（D1 锁定） | `a020999`（已废）→ `9a22827`（revert 后） | 召见二值裁决（错版） |
| **v7.3.2** | `9a22827` 之前 | C08 6 回合单层 · C06 20s 超时 |
| **v7.3.3** | `9a22827` 之前 | 情报牌可消耗加成（+5%/张） |
| **v7.3.4** | `9a22827` 之前 | 召见取消成功率/二值裁决 |
| **v7.3.5** | **`ea86f2d` 当前 main HEAD** | **召见立场结算：推合纵/推亲秦=背书影响国家三维；中立=君主自决** |

> ⚠️ **重要**：v7.3.5 修正版**已合入 main**（commit `ea86f2d`）。后续所有 C0X 修改必须基于此 commit 推进。
> 错版 commit `a020999`（"赞同/反对/中立"二值裁决）已被覆盖，**不要 revert**。

---

## 4 · 改交付物时的"反向追溯"流程

当你被命令"按 C0X 改 X 行为"时，按以下顺序操作：

```
1. 读 AI_INTEGRATION_GUIDE.md（本文件）
     ↓
2. 找到对应 C0X 的"落到哪里"映射
     ↓
3. 检查 §0 总览表的三处修改点：
   - data/*.json          （数据）
   - scripts/core/*.gd    （代码）
   - v7-纵横RTS/*.md      （源文档，同步）
     ↓
4. 修改前先 git status 确认无未提交残留
     ↓
5. 改完用 §0 检查清单逐项打勾
     ↓
6. 独立 commit（参照 v7.3.5 修正 commit 模式）
     ↓
7. push 到 origin/main
```

---

## 5 · 当前待办（v7.3.5 之后）

| # | 项 | 阻塞 | 位置 |
|---|---|---|---|
| 1 | C05 §六 三方签字 | 是（程序/美术未签字） | `C05-设计契约.md` §六 |
| 2 | C05 §七 Agent 动作枚举中文/英文统一 | 是 | `C05-设计契约.md` §七.2 |
| 3 | 面谈立场结算代码侧实现（v7.3.5 新增） | 是 | `core/agent_manager.gd`（`on_player_stance()` 待补） |
| 4 | 6 种值死亡叙事 → `data/death_narratives.json` | 否 | C01 §五 |
| 5 | 情报牌文案 ≥ 30 条 → 移交 C14 | 否 | C02 §五.4 |

---

## 6 · 联系方式

- **策划主笔**：ruohaojing（`@htalk:cdp:group:2522504863:seq61` 群聊可 @）
- **设计文档仓库**：[`v7.3.2-纵横RTS/v7-纵横RTS/`](../../v7.3.2-纵横RTS/v7-纵横RTS/) 16 篇源文档
- **项目根 README**：[`../../README.md`](../../README.md)

---

> **本文件用途**：让 AI Agent / 程序同事 5 分钟读懂"策划交付物在项目里怎么用"。
>
> **维护者**：策划/程序共同维护。改了 C0X 必须同步更新本指南。
>
> **版本**：v1.0（2026-07-02 ea86f2d 配套）
