# C11 · Mock 决策表·齐王（v7.3.6 · RFC-001 修订）

> **来源**：[C03 §三 齐王田地 persona](../../D1-策划交付物-20260630/C03-三君主persona卡片.md) + [C01 §3.2 Agent 博弈动作影响表](../../D1-策划交付物-20260630/C01-数值系统-锁定表.md) + [C05 §二.3 齐王动作枚举](../../D1-策划交付物-20260630/C05-设计契约.md)
> **任务**：C11（D2 上午 3–4h）· 编写 mock 决策表·齐王
> **目标 JSON 文件**：`data/mock_qi.json`
> **状态**：✅ 终稿（v7.3.6 init 分支修订）
> **修订记录**：
> - v7.3.6（2026-07-02 · RFC-001）：init 分支由"观望渔利"改为"中立候盟"（齐战心/盟信 ±0），避免开局齐盟信必跌（P0-8）

---

## 一、设计要点

齐王是"渔利之主"——低频观望，等别人先动再渔利。Mock 表只设 **6 个分支**（比秦/赵少 1 个），因齐王更被动。

### 1.1 与秦/赵 mock 表的关键差异

| 维度 | 秦王 mock | 赵王 mock | 齐王 mock |
|---|---|---|---|
| 行动频率 | 高频 | 中频 | **低频** |
| 默认动作 | 离间 | 求盟 | **观望渔利** |
| 决策信心 | ≥ 7 | ≤ 6 | **多 ≤ 5** |
| 第 2 轮结果 | 多 "召见" | 多 "召见" | **多 "决策已定"** |
| 分支数 | 7 | 7 | **6** |

---

## 二、6 个状态分支

### 2.1 init（第 1 回合 · v7.3.6 RFC-001 修订）

> **RFC-001 修订**：原"观望渔利"在前 2 轮让齐盟信必跌 −4（45→41），按 v7.3.1 终局 A 阈值 55 几乎不可达。修订为"**中立候盟**"（齐战心/盟信 ±0），避免开局必跌，给玩家后续行动留余地。
> 若 D2 试玩发现齐王过于被动，再启用备选方案（随机触发 50% 观望渔利 / 50% 主动合纵）。

```json
{
  "branch_id": "init",
  "match_condition": "round == 1",
  "round_1": {
    "target_country": null,
    "action": "qi_neutral",
    "reason": "开年让秦赵先斗——我且候。",
    "confidence": 4,
    "expected_effect": "齐战心 ±0，齐盟信 ±0（静候代价为零）。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": null,
    "action": "qi_neutral",
    "reason": "继续候——等秦或赵先出价。",
    "confidence": 4,
    "expected_effect": "齐战心 ±0，齐盟信 ±0。",
    "settle_decision": "decision_made"
  },
  "_v7_3_6_rfc001_note": "替代 v7.3.5 的'观望渔利'分支；齐战心/盟信不再下跌。若试玩发现过于被动，启用 _fallback_random_branch。",
  "_fallback_random_branch": {
    "round_1": {"action": "qi_watch", "probability": 0.5},
    "round_2": {"action": "qi_active_watch", "probability": 0.5}
  }
}
```

### 2.2 hezhong_blocked（赵齐盟信和 < 70 · 第 2/3 回合）

```json
{
  "branch_id": "hezhong_blocked",
  "match_condition": "round in [2,3] AND zhao_mengxin + qi_mengxin < 70",
  "round_1": {
    "target_country": null,
    "action": "qi_watch",
    "reason": "赵齐不合——更不用我出手。",
    "confidence": 5,
    "expected_effect": "齐战心 −2，齐盟信 −2。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "qin",
    "action": "qi_sell",
    "reason": "赵齐不合——秦必来收买。",
    "confidence": 6,
    "expected_effect": "齐与秦盟信 +5。",
    "settle_decision": "decision_made"
  }
}
```

### 2.3 hezhong_stalemate（赵齐盟信和 ≥ 70 · 第 2/3 回合）

```json
{
  "branch_id": "hezhong_stalemate",
  "match_condition": "round in [2,3] AND zhao_mengxin + qi_mengxin >= 70",
  "round_1": {
    "target_country": null,
    "action": "qi_watch",
    "reason": "赵齐合了——但合得越紧，我越值钱。",
    "confidence": 5,
    "expected_effect": "齐战心 −2，齐盟信 −2。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "qin",
    "action": "qi_sell",
    "reason": "合纵成形——秦必出更高价。",
    "confidence": 7,
    "expected_effect": "齐与秦盟信 +5。",
    "settle_decision": "decision_made"
  }
}
```

### 2.4 hezhong_signing（第 4 回合·前三回合赵齐盟信均值 ≥ 60）

```json
{
  "branch_id": "hezhong_signing",
  "match_condition": "round == 4 AND (zhao_mengxin_avg_3rounds + qi_mengxin_avg_3rounds) / 2 >= 60",
  "round_1": {
    "target_country": null,
    "action": "qi_watch",
    "reason": "签字在即——我先看谁出价。",
    "confidence": 5,
    "expected_effect": "齐战心 −2，齐盟信 −2。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "qin",
    "action": "qi_sell",
    "reason": "签不签无所谓——秦给得更多。",
    "confidence": 8,
    "expected_effect": "齐与秦盟信 +5（合纵破局）。",
    "settle_decision": "decision_made"
  }
}
```

### 2.5 qin_dominant（秦国威 ≥ 80 · 第 4/6 回合）

```json
{
  "branch_id": "qin_dominant",
  "match_condition": "round in [4,6] AND qin_guowei >= 80",
  "round_1": {
    "target_country": "qin",
    "action": "qi_sell",
    "reason": "秦势压境——赶紧接秦橄榄枝。",
    "confidence": 9,
    "expected_effect": "齐与秦盟信 +5。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": "qin",
    "action": "qi_sell",
    "reason": "再接一次——让秦觉得我是他的人。",
    "confidence": 8,
    "expected_effect": "齐与秦盟信 +5。",
    "settle_decision": "decision_made"
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
    "target_country": null,
    "action": "qi_watch",
    "reason": "僵持——我渔利空间最大。",
    "confidence": 5,
    "expected_effect": "齐战心 −2，齐盟信 −2。",
    "settle_decision": null
  },
  "round_2": {
    "target_country": null,
    "action": "qi_close",
    "reason": "算了——装作没看见。",
    "confidence": 4,
    "expected_effect": "无变化。",
    "settle_decision": "decision_made"
  }
}
```

### 2.7 audience_state（齐王召见 · v7.3.5 · 较少触发）

```json
{
  "branch_id": "audience_state",
  "match_condition": "current_state == '召见' AND country == 'qi'",
  "audience_response": {
    "opening": "秦许我三城，赵求我结盟——孤该信谁？",
    "proposed_action": "qi_sell",
    "proposed_action_effect_preview": "齐与出价方盟信 +5（按 C01 §3.2）",
    "response_hint": "按 C13 立场判读 → 推合纵/推亲秦=触发该动作；中立=君主自决（默认继续待价）",
    "settle_decision": "audience"
  },
  "_v7_3_5_note": "齐王召见极少触发——只在玩家主动召见齐王时出现。opening 必含'价码权衡'。",
  "_call_rate": "整个 6 回合齐王召见率 < 20%（齐王默认决策已定）"
}
```

---

## 三、近臣权重注入

```json
{
  "minister_weights": {
    "孟尝君": {
      "倾向": "谨慎渔利派",
      "动作权重": {
        "qi_watch": 1.3,
        "qi_raid": 0.5
      },
      "低语": "动则必败，观望方为上策。"
    }
  },
  "weight_application": "齐王仅 1 个近臣 → 权重调整更显著（×1.3）。"
}
```

---

## 四、齐王决策规则（与 C03 §三.6 一致）

```
默认动作：观望渔利
收到秦的连横利诱 → 评估出价是否足够大，足够则 待价而沽
收到赵的求盟 → 不直接拒绝也不接受 → 观望渔利
看到秦或赵明显衰弱 → 趁火打劫
战云压境 → 闭门自保
第 2 轮若仍未表态 → 状态 决策已定（齐王没兴趣）
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
    "target_country": null,
    "action": "qi_watch",
    "reason": "默认渔利——最安全。",
    "confidence": 4,
    "expected_effect": "齐战心 −2，齐盟信 −2。",
    "settle_decision": "decision_made"
  }
}
```

> **跨表引用**：
> - 秦王 fallback 详见 [C09 §五](C09-mock决策表-秦王.md)
> - 赵王 fallback 详见 [C10 §五](C10-mock决策表-赵王.md)
> - 齐王 fallback 详见本节

---

## 六、程序照搬说明

```gdscript
var mock = load_json("res://data/mock_qi.json")
var branch_id = classify_branch(game_state, "qi_king")
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
| `target_country` | String ∈ `{秦, 赵}` 或 null（齐王观望/自保可无目标） |
| `action` | String ∈ `{观望渔利, 待价而沽, 趁火打劫, 闭门自保}` |
| `proposed_action`（audience 状态） | String = 动作枚举之一 |

---

## 八、验收

- [x] 6 状态分支（比秦/赵少 1 个 · 齐王更被动）
- [x] 2 轮决策逻辑就位
- [x] 体现"低频观望"节奏（第 2 轮多"决策已定"）
- [x] 近臣权重（孟尝君·仅 1 个）注入
- [x] v7.3.5 audience 状态 proposed_action 就位
- [x] 字段名与 C05 契约一致
- [x] fallback 兜底

---

## 九、待确认项 ⚠️

1. **齐王 6 分支（vs 秦/赵 7 分支）**——少哪个？答：少"audience_state 内部细分"（齐王极少召见）。**D2 试玩验证召见率 < 20%**
2. **齐王"待价而沽"叠加**——同回合 2 次都选待价 → 盟信 +5 / 次，**单回合不封顶**（与秦王连横一致）
3. **"趁火打劫"** 触发条件需明确——mock 表暂未给独立分支，由"qin_dominant"分支兜底（"看到某方衰弱"），**D2 试玩观察是否够用**
4. **"闭门自保"无变化**——程序需在 schema 中标记 `value_change: {}`
