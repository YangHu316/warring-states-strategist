# C10 · Mock 决策表·赵王（v7.3.5）

> **来源**：[C03 §二 赵王赵何 persona](../../D1-策划交付物-20260630/C03-三君主persona卡片.md) + [C01 §3.2 Agent 博弈动作影响表](../../D1-策划交付物-20260630/C01-数值系统-锁定表.md) + [C05 §二.3 赵王动作枚举](../../D1-策划交付物-20260630/C05-设计契约.md)
> **任务**：C10（D2 上午 1.5–3h）· 编写 mock 决策表·赵王
> **目标 JSON 文件**：`data/mock_zhao.json`
> **状态**：✅ 终稿

---

## 一、设计要点

赵王是"犹疑之主"——默认偏"求盟+观望"，第 2 轮常进入"召见"等待玩家给路。Mock 决策表要体现这种**犹豫节奏**。

### 1.1 与秦王 mock 表的关键差异

| 维度 | 秦王 mock | 赵王 mock |
|---|---|---|
| 行动频率 | 高频主动 | 中等频率 |
| 默认动作 | 离间 / 利诱 | 求盟联齐 |
| 决策信心 | confidence 多 ≥ 7 | confidence 多 ≤ 6 |
| 第 2 轮结果 | 多种 settle | **常 "召见"** |
| 优先目标 | 离间对方 | 联合齐 |

---

## 二、7 个状态分支

### 2.1 init（第 1 回合）

```json
{
  "branch_id": "init",
  "match_condition": "round == 1",
  "round_1": {
    "target_country": "qi",
    "action": "zhao_probe",
    "reason": "开年先探——齐王是否真心抗秦。",
    "confidence": 5,
    "expected_effect": "不改数值，获取齐王意图情报。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "qi",
    "action": "zhao_ally",
    "reason": "试探有回应——联齐是正途。",
    "confidence": 6,
    "expected_effect": "双方盟信 +5。",
    "settle_decision": "audience"
  }
}
```

### 2.2 hezhong_blocked（赵齐盟信和 < 70 · 第 2/3 回合）

```json
{
  "branch_id": "hezhong_blocked",
  "match_condition": "round in [2,3] AND zhao_mengxin + qi_mengxin < 70",
  "round_1": {
    "target_country": "qi",
    "action": "zhao_ally",
    "reason": "盟信低——赶紧联齐保底。",
    "confidence": 7,
    "expected_effect": "双方盟信 +5。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "qin",
    "action": "zhao_probe",
    "reason": "联齐后探秦虚实——是否压境。",
    "confidence": 4,
    "expected_effect": "不改数值。",
    "settle_decision": "audience"
  }
}
```

### 2.3 hezhong_stalemate（赵齐盟信和 ≥ 70 · 第 2/3 回合）

```json
{
  "branch_id": "hezhong_stalemate",
  "match_condition": "round in [2,3] AND zhao_mengxin + qi_mengxin >= 70",
  "round_1": {
    "target_country": "qi",
    "action": "zhao_ally",
    "reason": "盟信已强——继续巩固。",
    "confidence": 8,
    "expected_effect": "双方盟信再 +5。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "qin",
    "action": "zhao_buildup",
    "reason": "盟信稳了——但秦不会停。",
    "confidence": 6,
    "expected_effect": "赵国威 +3，赵战心 +5。",
    "settle_decision": "audience"
  }
}
```

### 2.4 hezhong_signing（第 4 回合·前三回合赵齐盟信均值 ≥ 60）

```json
{
  "branch_id": "hezhong_signing",
  "match_condition": "round == 4 AND (zhao_mengxin_avg_3rounds + qi_mengxin_avg_3rounds) / 2 >= 60",
  "round_1": {
    "target_country": "qi",
    "action": "zhao_ally",
    "reason": "签字在即——必须拉齐。",
    "confidence": 8,
    "expected_effect": "双方盟信 +5，签字筹码足。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "qin",
    "action": "zhao_buildup",
    "reason": "签不签得看秦怎么动——先备好。",
    "confidence": 7,
    "expected_effect": "赵国威 +3，赵战心 +5。",
    "settle_decision": "召见"
  }
}
```

### 2.5 qin_dominant（秦国威 ≥ 80 · 第 4/6 回合）

```json
{
  "branch_id": "qin_dominant",
  "match_condition": "round in [4,6] AND qin_guowei >= 80",
  "round_1": {
    "target_country": "qi",
    "action": "zhao_ally",
    "reason": "秦势压境——必须联齐抗秦。",
    "confidence": 9,
    "expected_effect": "双方盟信 +5。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "qin",
    "action": "zhao_buildup",
    "reason": "联齐后——独战亦未尝不可。",
    "confidence": 7,
    "expected_effect": "赵国威 +3，赵战心 +5。",
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
    "action": "zhao_ally",
    "reason": "僵持——先稳住齐。",
    "confidence": 6,
    "expected_effect": "双方盟信 +5。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": null,
    "action": "zhao_fence",
    "reason": "等——看秦和齐怎么动。",
    "confidence": 3,
    "expected_effect": "赵战心 −2（犹豫代价）。",
    "settle_decision": "audience"
  }
}
```

### 2.7 audience_state（赵王召见 · v7.3.5）

```json
{
  "branch_id": "audience_state",
  "match_condition": "current_state == '召见' AND country == 'zhao'",
  "audience_response": {
    "opening": "齐王始终不肯明确表态，秦使又来施压——孤该如何？",
    "proposed_action": "zhao_ally",
    "proposed_action_effect_preview": "双方盟信 +5（按 C01 §3.2）",
    "response_hint": "按 C13 立场判读 → 推合纵/推亲秦=触发该动作；中立=君主自决（默认求盟）",
    "settle_decision": "audience"
  },
  "_v7_3_5_note": "v7.3.5 赵王 opening 必含'犹疑'语气——'孤该如何'是关键话术。"
}
```

---

## 三、近臣权重注入

```json
{
  "minister_weights": {
    "平原君": {
      "倾向": "主合纵",
      "动作权重": {
        "zhao_ally": 1.4,
        "zhao_fence": 0.5
      },
      "低语": "合纵是赵国唯一出路。"
    },
    "廉颇": {
      "倾向": "主战不信秦",
      "动作权重": {
        "zhao_buildup": 1.3,
        "zhao_fence": 0.5
      },
      "低语": "廉颇老矣，尚能一战。"
    }
  },
  "weight_application": "仲裁器在选定 mock 动作后 → 读取该动作的近臣权重 → 调整 confidence。"
}
```

---

## 四、赵王决策规则（与 C03 §二.6 一致）

```
第 1 轮：遣使试探 或 求盟联齐（试探为主）
第 2 轮：
  ├─ 听到齐王可能联手 → 求盟联齐
  ├─ 感到秦压境且无外援 → 备战固境
  ├─ 完全犹豫 → 骑墙观望
  └─ 仍犹豫 → 状态 召见（等玩家给路）
```

---

## 五、fallback_action

> **v7.3.7 P1-12 跨表交叉引用**：三君主 fallback 动作设计逻辑：
> - **秦王 fallback = 备战蓄力**（蓄力型）：秦国威+3，秦战心+5——秦王永不报错时保守蓄力
> - **赵王 fallback = 求盟联齐**（外交型）：双方盟信+5——赵王永不报错时先稳住齐
> - **齐王 fallback = 观望渔利**（渔利型）：齐战心−2，齐盟信−2——齐王永不报错时最安全
> **设计意图**：三君主 fallback 体现各自核心性格（秦强攻/赵联合/齐渔利），同时 fallback 都不会造成"立即崩盘"。

```json
{
  "fallback_action": {
    "target_country": "qi",
    "action": "zhao_ally",
    "reason": "默认稳健——先稳齐。",
    "confidence": 5,
    "expected_effect": "双方盟信 +5。",
    "settle_decision": null
  }
}
```

> **跨表引用**：
> - 秦王 fallback 详见 [C09 §五](C09-mock决策表-秦王.md)
> - 赵王 fallback 详见本节
> - 齐王 fallback 详见 [C11 §五](C11-mock决策表-齐王.md)

---

## 六、程序照搬说明

```gdscript
var mock = load_json("res://data/mock_zhao.json")
var branch_id = classify_branch(game_state, "zhao_king")
var branch = mock.branches.get(branch_id, mock.fallback_action)
var round_num = game_state.round_in_pair
var action = branch["round_" + str(round_num)]
action.confidence = apply_minister_weights(action, mock.minister_weights)
return action
```

---

## 七、字段名一致性

| 字段 | 约束 |
|---|---|
| `target_country` | String ∈ `{秦, 齐}`（赵王只能选秦/齐） |
| `action` | String ∈ `{求盟联齐, 备战固境, 遣使试探, 骑墙观望}` |
| `proposed_action`（audience 状态） | String = 动作枚举之一 |

---

## 八、验收

- [x] 7 状态分支（含 init/hezhong_*/qin_dominant/stalemate/audience）
- [x] 2 轮决策逻辑就位
- [x] 体现"犹疑"节奏（第 2 轮常召见）
- [x] 近臣权重（平原君 + 廉颇）注入
- [x] v7.3.5 audience 状态 proposed_action 就位
- [x] 字段名与 C05 契约一致
- [x] fallback 兜底

---

## 九、待确认项 ⚠️

1. ~~**赵王第 2 轮 90% "召见"** 是否太频繁？~~ **v7.3.7 P1-14 已调整**：赵王第 2 轮召见率从 90% 改为 **70%**。理由：90% 拖节奏，玩家感到"赵王犹豫太频繁"；70% 保留"犹疑"人设同时给玩家更多推进空间。其他 30% 改为"决策已定"（赵王做出明确决策）。
2. **"骑墙观望"后状态仍是 "召见"** 而非 "决策已定"——赵王犹豫不决时不应给"决策已定"，**保持召见**符合犹疑人设
3. **"遣使试探"不改数值**——程序需在 schema 中标记 `value_change: null`
