# C09 · Mock 决策表·秦王（v7.3.5）

> **来源**：[C03 §一 秦王嬴稷 persona](../../D1-策划交付物-20260630/C03-三君主persona卡片.md) + [C01 §3.2 Agent 博弈动作影响表](../../D1-策划交付物-20260630/C01-数值系统-锁定表.md) + [C05 §二.3 秦王动作枚举](../../D1-策划交付物-20260630/C05-设计契约.md)
> **任务**：C09（D2 上午 0–1.5h）· 编写 mock 决策表·秦王（规则版：状态→动作选择，含 2 轮决策逻辑）
> **目标 JSON 文件**：`data/mock_qin.json`（程序照搬本表生成）
> **状态**：✅ 终稿

---

## 一、设计要点

### 1.1 秦王博弈循环（每对国家 ≤ 2 轮）

```
第 N 轮开始（仲裁器读取 GameState）
  ├─ 读取 3 君主当前动作 + 上一轮日志
  ├─ 匹配状态分支（见 §二）→ 查 mock 表
  ├─ mock 表返回：{target_country, action, reason, confidence, expected_effect, settle_decision}
  └─ 仲裁器按 C01 §3.2 应用数值变动 → 写入事件流
```

### 1.2 mock 表结构（与 C05 §四 Agent 8 模块输出 schema 对齐）

```json
{
  "agent_id": "qin_king",
  "version": "v7.3.5",
  "min_mock_branches": 7,
  "branches": {
    "init": { ... },
    "hezhong_blocked": { ... },
    "hezhong_stalemate": { ... },
    "hezhong_signing": { ... },
    "qin_dominant": { ... },
    "default_round_3_4": { ... },
    "audience_state": { ... }
  },
  "minister_weights": { ... },
  "fallback_action": { ... }
}
```

### 1.3 v7.3.5 适配：召见状态返回 `proposed_action`

召见状态下，mock 表返回的 `proposed_action` 字段 = 君主提议让玩家背书的博弈动作（影响国家三维）。**无成功率、无综合分判读**——直接按玩家后续立场表态（推合纵/推亲秦=背书生效；中立=君主自决）。

---

## 二、7 个状态分支（mock_qin.json 完整内容）

> 程序照搬以下结构生成 JSON。

### 2.1 init（第 1 回合开局 · 无前序状态）

```json
{
  "branch_id": "init",
  "match_condition": "round == 1",
  "round_1": {
    "target_country": "zhao",
    "action": "qin_alienate",
    "reason": "开年大棋先破合纵——赵齐最易离间。",
    "confidence": 7,
    "expected_effect": "赵齐盟信 −8，瓦解初期合纵萌芽。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "qi",
    "action": "qin_bribe",
    "reason": "齐王贪利——三城足以定其心。",
    "confidence": 8,
    "expected_effect": "齐盟信向秦 +5，连横开局。",
    "settle_decision": null
  }
}
```

### 2.2 hezhong_blocked（赵齐盟信和 < 70）

```json
{
  "branch_id": "hezhong_blocked",
  "match_condition": "round in [2,3] AND zhao_mengxin + qi_mengxin < 70",
  "round_1": {
    "target_country": "zhao",
    "action": "qin_alienate",
    "reason": "赵齐关系弱——此时离间成本最低。",
    "confidence": 8,
    "expected_effect": "赵齐盟信再 −8。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "zhao",
    "action": "qin_military",
    "reason": "离间后趁势加压——让赵无喘息。",
    "confidence": 7,
    "expected_effect": "赵国威 −5，秦战心 +3。",
    "settle_decision": "audience"
  }
}
```

### 2.3 hezhong_stalemate（赵齐盟信和 ≥ 70 · v7.3.7 P1-13 单回合封顶）

> **P1-13 修订**：原 v7.3.5 中 hezhong_stalemate 分支 round_1+round_2 连续两次连横利诱 = +10 齐盟信，无封顶，**破坏平衡**（玩家无法阻止）。
> **v7.3.7 锁定（v7.3.7 修）**：
> - **单回合封顶 +5**——连横利诱每回合最多 +5 齐盟信，不可叠加
> - round_2 改为其他动作（利诱已边际递减，改为备战蓄力 / 离间）
> - 玩家在 2 轮内最多承受 +5 齐盟信损失（**可应对**）

```json
{
  "branch_id": "hezhong_stalemate",
  "match_condition": "round in [2,3] AND zhao_mengxin + qi_mengxin >= 70",
  "round_1": {
    "target_country": "qi",
    "action": "qin_bribe",
    "reason": "赵齐已合——先从齐下手，许以重利。",
    "confidence": 7,
    "expected_effect": "齐盟信向秦 +5（v7.3.7 P1-13 单回合封顶）。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "qi",
    "action": "qin_alienate",
    "reason": "利诱已边际递减，改为离间赵齐——撕开口子后再压。",
    "confidence": 7,
    "expected_effect": "赵齐盟信 −8（利诱不再叠加）。",
    "settle_decision": "audience"
  }
}
```

### 2.4 hezhong_signing（前三回合赵齐盟信均值 ≥ 60 · 第 4 回合）

```json
{
  "branch_id": "hezhong_signing",
  "match_condition": "round == 4 AND (zhao_mengxin_avg_3rounds + qi_mengxin_avg_3rounds) / 2 >= 60",
  "round_1": {
    "target_country": "qi",
    "action": "qin_bribe",
    "reason": "合纵签字前——最后机会拉齐倒戈。",
    "confidence": 9,
    "expected_effect": "齐盟信向秦 +5，让齐王临阵倒戈。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "zhao",
    "action": "qin_alienate",
    "reason": "齐若动——赵必震，此时离间最有效。",
    "confidence": 8,
    "expected_effect": "赵齐盟信 −8，签字流产。",
    "settle_decision": "audience"
  }
}
```

### 2.5 qin_dominant（秦国威 ≥ 80 · 第 4/6 回合）

```json
{
  "branch_id": "qin_dominant",
  "match_condition": "round in [4,6] AND qin_guowei >= 80",
  "round_1": {
    "target_country": "zhao",
    "action": "qin_military",
    "reason": "势已在我——直接压。",
    "confidence": 10,
    "expected_effect": "赵国威 −5，秦战心 +3。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "zhao",
    "action": "qin_military",
    "reason": "继续压——不战而屈人之兵。",
    "confidence": 9,
    "expected_effect": "赵国威再 −5，秦战心 +3。",
    "settle_decision": "audience"
  }
}
```

### 2.6 default_round_3_4（其余 · 第 3/4 回合兜底 · v7.3.7 P1-21 重命名）

> **P1-21 重命名说明**：原 branch_id `stalemate` 容易与 §2.3 `hezhong_stalemate` 混淆。改名为 `default_round_3_4` 明确这是"第 3/4 回合兜底分支"，避免误导。

```json
{
  "branch_id": "default_round_3_4",
  "match_condition": "round in [3,4] AND not (hezhong_signing OR qin_dominant)",
  "round_1": {
    "target_country": "qi",
    "action": "qin_bribe",
    "reason": "僵持——先撬齐。",
    "confidence": 6,
    "expected_effect": "齐盟信向秦 +5。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "zhao",
    "action": "qin_alienate",
    "reason": "撬齐未成——再从赵下手。",
    "confidence": 6,
    "expected_effect": "赵齐盟信 −8。",
    "settle_decision": "decision_made"
  }
}
```

### 2.7 audience_state（玩家已抵达秦 · 召见状态 · v7.3.5）

```json
{
  "branch_id": "audience_state",
  "match_condition": "current_state == '召见' AND country == 'qin'",
  "audience_response": {
    "opening": "齐王始终不肯归顺于秦，寡人有意实施进一步的强制措施——兵临宜阳，足下以为如何？",
    "proposed_action": "军事施压",
    "proposed_action_effect_preview": "目标国威 −5，秦战心 +3（按 C01 §3.2）",
    "response_hint": "等玩家输入表态——按 C13 立场判读 → 推合纵/推亲秦=触发该动作；中立=君主自决（仍按本动作执行）",
    "settle_decision": "audience"
  },
  "_v7_3_5_note": "本分支 v7.3.5 起不再返回综合分/verdict，改为返回 proposed_action + opening，由玩家立场触发数值变动。详见 C13 §一。"
}
```

---

## 三、近臣权重注入（minister_weights · 11b §三 + C04 §二）

```json
{
  "minister_weights": {
    "张仪": {
      "倾向": "连横第一推手",
      "动作权重": {
        "连横利诱": 1.5,
        "备战蓄力": 0.6
      },
      "低语": "齐王贪利，许以三城可定。"
    },
    "魏冉": {
      "倾向": "穰侯·务实扩张",
      "动作权重": {
        "军事施压": 1.4
      },
      "低语": "战机稍纵即逝。"
    }
  },
  "weight_application": "仲裁器在选定 mock 动作后，读取该动作的近臣权重 → 调整 confidence：连横利诱 confidence ×1.5；军事施压 confidence ×1.4；备战蓄力 confidence ×0.6。"
}
```

---

## 四、决策规则优先级（与 C03 §一.6 一致）

```
1. 离间（遣使离间） → 察觉赵齐有联合迹象时优先
2. 利诱（连横利诱） → 目标国犹豫不决时
3. 军事施压 → 任何时候可施压
4. 备战蓄力 → 需要巩固自身时
```

> **mock 决策表执行顺序**：分支匹配 → 动作选择 → 近臣权重调整 confidence → 输出 schema。

---

## 五、fallback_action（默认兜底 · 永不报错）

> **v7.3.7 P1-12 跨表交叉引用**：三君主 fallback 动作设计逻辑：
> - **秦王 fallback = 备战蓄力**（蓄力型）：秦国威+3，秦战心+5——秦王永不报错时保守蓄力
> - **赵王 fallback = 求盟联齐**（外交型）：双方盟信+5——赵王永不报错时先稳住齐
> - **齐王 fallback = 观望渔利**（渔利型）：齐战心−2，齐盟信−2——齐王永不报错时最安全
> **设计意图**：三君主 fallback 体现各自核心性格（秦强攻/赵联合/齐渔利），同时 fallback 都不会造成"立即崩盘"。

```json
{
  "fallback_action": {
    "target_country": "zhao",
    "action": "qin_buildup",
    "reason": "默认稳健——不轻举妄动。",
    "confidence": 5,
    "expected_effect": "秦国威 +3，秦战心 +5。",
    "settle_decision": null
  }
}
```

> **跨表引用**：
> - 秦王 fallback 详见本节
> - 赵王 fallback 详见 [C10 §五](C10-mock决策表-赵王.md)
> - 齐王 fallback 详见 [C11 §五](C11-mock决策表-齐王.md)

---

## 六、程序照搬说明

程序在 `data/mock_qin.json` 中按本文件 §二结构生成 JSON。加载逻辑（`scripts/core/llm_client.gd`）：

```gdscript
# 伪代码
var mock = load_json("res://data/mock_qin.json")
var branch_id = classify_branch(game_state, "qin_king")
var branch = mock.branches.get(branch_id, mock.fallback_action)
var round_num = game_state.round_in_pair  # 1 或 2
var action = branch["round_" + str(round_num)]
# 应用近臣权重
action.confidence = apply_minister_weights(action, mock.minister_weights)
return action
```

---

## 七、字段名一致性

| 字段 | 来源 | 类型 |
|---|---|---|
| `agent_id` | C05 §2.3 | String = `"qin_king"` |
| `target_country` | C05 §2.3 | String ∈ `{zhao, qi}`（秦王只能选赵/齐） |
| `action` | C05 §2.3 秦王动作枚举 | String ∈ `{军事施压, 遣使离间, 连横利诱, 备战蓄力}` |
| `confidence` | C03 §一.7 schema | int (0–10) |
| `settle_decision` | C03 §一.7 schema | String ∈ `{召见, 决策已定, null}` |
| `proposed_action`（audience 状态） | C01 §1.2 + 11b §四 | String = 动作枚举之一 |
| `opening`（audience 状态） | C01 §1.2 + 11b §四 | String ≤ 100 字 |

---

## 八、验收

- [x] mock 决策表 JSON 完整结构（7 状态分支 + fallback）
- [x] 2 轮决策逻辑（round_1 + round_2）就位
- [x] 近臣权重（张仪 + 魏冉）注入
- [x] **v7.3.5 audience 状态 proposed_action 字段**就位
- [x] 字段名与 C05 契约完全一致
- [x] 程序照搬说明
- [x] 决策规则优先级就位
- [x] fallback 兜底就位

---

## 九、待确认项 ⚠️

1. **2 轮博弈每轮 5–8 个动作枚举**（C01 §3.2 11 项 + 连横可叠加）—— D2/D3 验证是否平衡
2. **齐王"连横利诱可叠加"**（同回合 2 次都选连横）—— 是否设单回合不封顶？**D3 校准**
3. **mock 与 LLM 切换**（ENG-14 降级链）—— `llm_client.gd` 需支持按 agent_id 切换 mock/llm，**程序主导**
4. **fallback 选 "备战蓄力"**——秦王永不报错时的兜底，是否过于保守？**D2 试玩验证**
