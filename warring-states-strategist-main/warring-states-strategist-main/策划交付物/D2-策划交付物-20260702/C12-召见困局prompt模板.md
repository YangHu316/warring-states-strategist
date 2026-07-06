# C12 · 召见困局 Prompt 模板（v7.3.7 · RFC-002 重设计 · P0-2/3/4 修复）

> **来源**：[C03 §一/二/三 §4 困局类型](../../D1-策划交付物-20260630/C03-三君主persona卡片.md) + [C05 §四 Agent Prompt 字段](../../D1-策划交付物-20260630/C05-设计契约.md) + [C08 关键事件](../../D1-策划交付物-20260630/C08-总体剧本6回合.md) + [C01 §1.2 v7.3.7 面谈机制](../../D1-策划交付物-20260630/C01-数值系统-锁定表.md)
> **任务**：C12（D2 下午 4–5h）· 设计召见困局 prompt 模板（每种君主 3–5 个困局方向）
> **总数量**：**14 个**（秦 5 + 赵 5 + 齐 4 = 14 个）
> **目标 JSON 文件**：`data/prompts/audience_dilemmas.json`（LLM Agent 调用）
> **状态**：✅ 终稿（**v7.3.7 RFC-002 重设计**：每个困局增加 `stance_aware_actions` 三分支）

---

## 零、v7.3.7 重大变更（RFC-002）

**问题（v7.3.5 旧）**：玩家"推合纵 = 背书执行 proposed_action"——若君主 proposed_action 是离间/备战/军事施压（反合纵动作），推合纵玩家实际在帮秦——**核心逻辑悖论**。

**修复（v7.3.7 新）**：每个困局 JSON 增加 `stance_aware_actions` 三分支：
- `if_hezong`：玩家推合纵背书 → **合纵侧结果**（反制原 proposed_action + 合纵巩固）
- `if_qin`：玩家推亲秦背书 → **亲秦侧结果**（强化原 proposed_action）
- `if_neutral`：中立/君主自决 → 原 proposed_action 效果

**效果**：3 立场有完全不同的国家三维结果（P0-2/3/4 解决）。

---

## 一、设计原则

1. **每个困局 = `{opening, proposed_action, scenario_hint, stance_aware_actions}` 四元组**
2. **困局对应 C03 中"困局类型"**——是君主在该局面下会问的"问题"
3. **v7.3.7 适配**：`stance_aware_actions` 决定不同立场下执行哪个 `national_delta`
4. **困局与关键事件挂钩**——每回合弹哪 1 个困局由当前关键事件 + 该君主状态决定

---

## 二、秦王·嬴稷 5 个困局

### D-Q1 · 试探合纵虚实

```json
{
  "dilemma_id": "QIN_D1",
  "君主": "qin_king",
  "scenario_hint": {
    "and": [
      {"var": "round", "op": ">=", "value": 2},
      {"var": "qin_perceived_zhao_qi_alliance", "op": "==", "value": true}
    ]
  },
  "opening": "赵齐真联了？联的是什么？孤想知道。",
  "proposed_action": "遣使离间",
  "proposed_action_effect": "原动作：赵齐盟信 −8（按 C01 §3.2）",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "劝阻离间 + 反制",
      "effect_summary": "玩家推合纵=劝秦不要离间；秦暂缓离间 + 合纵巩固",
      "national_delta": "赵齐盟信 +3"
    },
    "if_qin": {
      "action_name": "协助离间",
      "effect_summary": "玩家主动为秦出谋划策，强化离间效果",
      "national_delta": "赵齐盟信 −10"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "秦王按原 proposed_action 执行",
      "national_delta": "赵齐盟信 −8"
    }
  },
  "expected_player_stance": "推合纵（玩家多半不愿背书离间）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

### D-Q2 · 展示实力后的威慑性提问

```json
{
  "dilemma_id": "QIN_D2",
  "君主": "qin_king",
  "scenario_hint": "round >= 1 AND 玩家刚抵达秦",
  "opening": "你替赵来游说？可知函谷关外已是秦土？",
  "proposed_action": "备战蓄力",
  "proposed_action_effect": "原动作：秦国威 +3，秦战心 +5",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "劝缓备战 + 离间反制",
      "effect_summary": "玩家推合纵=劝秦缓兵；秦战心降低，合纵巩固",
      "national_delta": "秦战心 −3，赵齐盟信 +2"
    },
    "if_qin": {
      "action_name": "协助备战",
      "effect_summary": "玩家主动为秦谋划，强备战",
      "national_delta": "秦国威 +5，秦战心 +7"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "秦王按原 proposed_action 执行",
      "national_delta": "秦国威 +3，秦战心 +5"
    }
  },
  "expected_player_stance": "推合纵（玩家硬顶）或推亲秦（玩家顺势）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

### D-Q3 · 要求纵横家表态站队

```json
{
  "dilemma_id": "QIN_D3",
  "君主": "qin_king",
  "scenario_hint": "round >= 3 AND 玩家合纵信号明显",
  "opening": "六国盟书是否经你之手？足下与赵究竟是什么关系？",
  "proposed_action": "遣使离间",
  "proposed_action_effect": "原动作：赵齐盟信 −8",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "否认 + 反制离间",
      "effect_summary": "玩家否认 + 主动揭穿秦离间意图",
      "national_delta": "赵齐盟信 +4（揭穿离间=合纵巩固）"
    },
    "if_qin": {
      "action_name": "投诚 + 协助离间",
      "effect_summary": "玩家投诚，主动为秦谋划",
      "national_delta": "赵齐盟信 −10，秦国威 +2"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "秦王按原 proposed_action 执行",
      "national_delta": "赵齐盟信 −8"
    }
  },
  "expected_player_stance": "推合纵（玩家多否认）或推亲秦（玩家投诚）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

### D-Q4 · 决战前最终施压

```json
{
  "dilemma_id": "QIN_D4",
  "君主": "qin_king",
  "scenario_hint": "round == 6",
  "opening": "函谷关外秦军已集——明日决战。足下以为如何？",
  "proposed_action": "军事施压",
  "proposed_action_effect": "原动作：目标国威 −5，秦战心 +3",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "劝退 + 反施压",
      "effect_summary": "玩家推合纵=劝秦退兵；秦暂缓施压",
      "national_delta": "秦国威 −2，秦战心 −3"
    },
    "if_qin": {
      "action_name": "背书施压",
      "effect_summary": "玩家主动推动军事行动",
      "national_delta": "赵国威 −7，秦战心 +5"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "秦王按原 proposed_action 执行",
      "national_delta": "赵国威 −5，秦战心 +3"
    }
  },
  "expected_player_stance": "推合纵（玩家劝退）或推亲秦（玩家背书）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

### D-Q5 · 和谈伪装

```json
{
  "dilemma_id": "QIN_D5",
  "君主": "qin_king",
  "scenario_hint": "round == 6 AND qin_guowei < 60",
  "opening": "兵者凶器——孤有意与赵讲和。足下以为如何？",
  "proposed_action": "备战蓄力",
  "proposed_action_effect": "原动作：秦国威 +3，秦战心 +5",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "推合纵 + 监督讲和",
      "effect_summary": "玩家推合纵=推动真讲和 + 合纵巩固",
      "national_delta": "赵齐盟信 +4，秦国威 −2（真讲和）"
    },
    "if_qin": {
      "action_name": "假讲和真备战",
      "effect_summary": "玩家配合秦伪装，强备战",
      "national_delta": "秦国威 +5，秦战心 +6"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "秦王按原 proposed_action 执行",
      "national_delta": "秦国威 +3，秦战心 +5"
    }
  },
  "expected_player_stance": "推合纵（玩家可趁机巩固）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

---

## 三、赵王·赵何 5 个困局

### D-Z1 · 齐王不出兵的困局

```json
{
  "dilemma_id": "ZHAO_D1",
  "君主": "zhao_king",
  "scenario_hint": "round >= 2 AND zhao_mengxin < 60",
  "opening": "齐王说让孤先动，可孤若先动，秦必攻赵。",
  "proposed_action": "求盟联齐",
  "proposed_action_effect": "原动作：双方盟信 +5",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "劝赵主动联齐",
      "effect_summary": "玩家推合纵=主动推赵联齐，效果强化",
      "national_delta": "赵齐盟信 +7"
    },
    "if_qin": {
      "action_name": "劝赵别动",
      "effect_summary": "玩家推亲秦=劝赵按兵不动（让秦得利）",
      "national_delta": "赵战心 −3，秦国威 +2"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "赵王按原 proposed_action 执行",
      "national_delta": "赵齐盟信 +5"
    }
  },
  "expected_player_stance": "推合纵（玩家劝赵主动联齐）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

### D-Z2 · 近臣意见冲突

```json
{
  "dilemma_id": "ZHAO_D2",
  "君主": "zhao_king",
  "scenario_hint": "round >= 3 AND 关键事件触发'秦使分赴'",
  "opening": "平原君说联齐，廉颇说独战——孤该听谁的？",
  "proposed_action": "求盟联齐",
  "proposed_action_effect": "原动作：双方盟信 +5",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "支持联齐",
      "effect_summary": "玩家推合纵=支持平原君",
      "national_delta": "赵齐盟信 +7"
    },
    "if_qin": {
      "action_name": "支持独战",
      "effect_summary": "玩家推亲秦=支持廉颇独战（让秦坐收渔利）",
      "national_delta": "赵战心 +5，秦国威 +1"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "赵王犹豫后按原 proposed_action",
      "national_delta": "赵齐盟信 +5"
    }
  },
  "expected_player_stance": "推合纵或中立（玩家犹豫）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

### D-Z3 · 秦的离间计

```json
{
  "dilemma_id": "ZHAO_D3",
  "君主": "zhao_king",
  "scenario_hint": "round == 3 OR round == 4",
  "opening": "秦遣使来——'谁先动，秦就先打谁'。这是离间？还是警告？",
  "proposed_action": "备战固境",
  "proposed_action_effect": "原动作：赵国威 +3，赵战心 +5",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "劝赵备战 + 联齐",
      "effect_summary": "玩家推合纵=看穿离间+推备战+联齐",
      "national_delta": "赵国威 +3，赵战心 +5，赵齐盟信 +3"
    },
    "if_qin": {
      "action_name": "劝赵相信秦",
      "effect_summary": "玩家推亲秦=劝赵相信秦的'警告'",
      "national_delta": "赵战心 −3，赵齐盟信 −3"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "赵王按原 proposed_action 执行",
      "national_delta": "赵国威 +3，赵战心 +5"
    }
  },
  "expected_player_stance": "推合纵（玩家劝备战）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

### D-Z4 · 合纵签字与否

```json
{
  "dilemma_id": "ZHAO_D4",
  "君主": "zhao_king",
  "scenario_hint": "round == 4",
  "opening": "六国使节齐聚邯郸——签还是不签？",
  "proposed_action": "求盟联齐",
  "proposed_action_effect": "原动作：双方盟信 +5",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "劝赵签",
      "effect_summary": "玩家推合纵=力劝赵签，效果强化",
      "national_delta": "赵齐盟信 +8（合纵签字效果）"
    },
    "if_qin": {
      "action_name": "劝赵别签",
      "effect_summary": "玩家推亲秦=劝赵不要签字",
      "national_delta": "赵齐盟信 −5，秦国威 +2"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "赵王犹豫后按原 proposed_action",
      "national_delta": "赵齐盟信 +5"
    }
  },
  "expected_player_stance": "推合纵（玩家劝签）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

### D-Z5 · 决战前赵王求路

```json
{
  "dilemma_id": "ZHAO_D5",
  "君主": "zhao_king",
  "scenario_hint": "round == 6",
  "opening": "秦军压境——孤该如何？降？战？",
  "proposed_action": "备战固境",
  "proposed_action_effect": "原动作：赵国威 +3，赵战心 +5",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "劝赵战",
      "effect_summary": "玩家推合纵=劝赵坚守",
      "national_delta": "赵国威 +3，赵战心 +7"
    },
    "if_qin": {
      "action_name": "劝赵降",
      "effect_summary": "玩家推亲秦=劝赵投降（注意：v7.3.7 改后 '降' 关键词映射中立）",
      "national_delta": "赵战心 −5，赵国威 −2"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "赵王按原 proposed_action 执行",
      "national_delta": "赵国威 +3，赵战心 +5"
    }
  },
  "expected_player_stance": "推合纵（玩家劝战）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

---

## 四、齐王·田地 4 个困局

### D-Qi1 · 许诺价码权衡

```json
{
  "dilemma_id": "QI_D1",
  "君主": "qi_king",
  "scenario_hint": "round >= 2 AND 收到秦或赵的利诱",
  "opening": "秦许我三城，赵求我结盟——孤该信谁？",
  "proposed_action": "待价而沽",
  "proposed_action_effect": "原动作：与出价方盟信 +5",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "劝齐签合纵",
      "effect_summary": "玩家推合纵=劝齐投合纵阵营",
      "national_delta": "齐赵盟信 +7，秦齐盟信 −3"
    },
    "if_qin": {
      "action_name": "劝齐亲秦",
      "effect_summary": "玩家推亲秦=劝齐接受秦的价码",
      "national_delta": "齐秦盟信 +7，赵齐盟信 −3"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "齐王按原 proposed_action 执行",
      "national_delta": "与出价方盟信 +5"
    }
  },
  "expected_player_stance": "推合纵（玩家劝齐签合纵）或推亲秦（玩家劝齐亲秦）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

### D-Qi2 · 安全顾虑

```json
{
  "dilemma_id": "QI_D2",
  "君主": "qi_king",
  "scenario_hint": "round >= 3 AND qin_guowei >= 75",
  "opening": "若我出兵，秦会不会先来打我？",
  "proposed_action": "闭门自保",
  "proposed_action_effect": "原动作：无变化",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "劝齐勇",
      "effect_summary": "玩家推合纵=劝齐加入合纵",
      "national_delta": "齐战心 +3，赵齐盟信 +4"
    },
    "if_qin": {
      "action_name": "劝齐保",
      "effect_summary": "玩家推亲秦=劝齐自保不出兵（让秦放心）",
      "national_delta": "齐战心 −2，秦国威 +1"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "齐王按原 proposed_action 执行（闭门自保）",
      "national_delta": "无变化"
    }
  },
  "expected_player_stance": "推合纵（玩家劝齐勇）或推亲秦（玩家劝齐保）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

### D-Qi3 · 合纵签字压力

```json
{
  "dilemma_id": "QI_D3",
  "君主": "qi_king",
  "scenario_hint": "round == 4",
  "opening": "六国使节齐聚邯郸签字在即——我要不要签？",
  "proposed_action": "待价而沽",
  "proposed_action_effect": "原动作：与出价方盟信 +5",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "劝齐签",
      "effect_summary": "玩家推合纵=力劝齐签合纵",
      "national_delta": "齐赵盟信 +7"
    },
    "if_qin": {
      "action_name": "劝齐别签",
      "effect_summary": "玩家推亲秦=劝齐拒绝签字",
      "national_delta": "齐秦盟信 +5，赵齐盟信 −5"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "齐王按原 proposed_action 执行",
      "national_delta": "与出价方盟信 +5"
    }
  },
  "expected_player_stance": "推合纵（玩家劝签）或推亲秦（玩家劝别签）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

### D-Qi4 · 决战前齐王求价

```json
{
  "dilemma_id": "QI_D4",
  "君主": "qi_king",
  "scenario_hint": "round == 6 AND 齐王被召见（极少见）",
  "opening": "函谷关外决战在即——齐国要不要援赵？",
  "proposed_action": "待价而沽",
  "proposed_action_effect": "原动作：与出价方盟信 +5",
  "stance_aware_actions": {
    "if_hezong": {
      "action_name": "劝齐援赵",
      "effect_summary": "玩家推合纵=力劝齐援赵决战",
      "national_delta": "齐战心 +3，赵齐盟信 +5"
    },
    "if_qin": {
      "action_name": "劝齐观望",
      "effect_summary": "玩家推亲秦=劝齐不出兵",
      "national_delta": "齐战心 −2，秦国威 +2"
    },
    "if_neutral": {
      "action_name": "君主自决",
      "effect_summary": "齐王按原 proposed_action 执行（继续待价）",
      "national_delta": "与出价方盟信 +5"
    }
  },
  "expected_player_stance": "推合纵（玩家劝援）",
  "fallback_if_neutral": "if_neutral 分支"
}
```

---

## 五、困局与关键事件联动表

| 回合 | 关键事件 | 可触发困局（按君主） |
|---|---|---|
| 1 | 秦使分赴各国 | QIN_D2 · ZHAO_D1 · — |
| 2 | 秦拔宜阳 + 张仪入齐 | QIN_D1 · QIN_D2 · ZHAO_D1 · QI_D1 |
| 3 | 合纵之议成形 vs 秦离间 | QIN_D1 · QIN_D3 · ZHAO_D2 · ZHAO_D3 · QI_D2 |
| 4 | 合纵签字 vs 秦军压境 | QIN_D3 · ZHAO_D4 · QI_D3 |
| 5 | 决战前夕 | QIN_D1 · ZHAO_D3 · QI_D2 |
| 6 | 函谷关外最后一搏 | QIN_D4 · QIN_D5 · ZHAO_D5 · QI_D4 |

---

## 六、Json 完整结构（程序照搬 · v7.3.7）

```json
{
  "version": "v7.3.7",
  "dilemmas": {
    "QIN_D1": { "...": "..." },
    "QIN_D2": { "...": "..." },
    "...": "..."
  },
  "match_logic": {
    "description": "程序按 scenario_hint 动态匹配当前回合 + 关键事件 → 选择 1 个 dilemma",
    "stance_resolution": "程序读 dilemma.stance_aware_actions[player_stance] → 执行 national_delta"
  }
}
```

---

## 七、v7.3.7 字段对齐

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `dilemma_id` | String | 是 | `QIN_D1` / `ZHAO_D1` / `QI_D1` 等 |
| `君主` | String | 是 | `qin_king` / `zhao_king` / `qi_king`（v7.3.7 P1-6 英文化） |
| `scenario_hint` | String | 是 | 触发条件（结构化 JSON，**v7.3.7 P1-15 重构**：详见 §九） |
| `opening` | String ≤ 100 字 | 是 | 君主开场白（与 LLM 输出的 `opening` 字段对应） |
| `proposed_action` | String | 是 | 提议动作（与 C05 §2.3 动作枚举对应） |
| `proposed_action_effect` | String | 是 | 效果说明（仅 UI 显示，程序按 C01 §3.2 实际计算） |
| `stance_aware_actions` | Object | **是（v7.3.7 新增）** | 三立场分支：`if_hezong` / `if_qin` / `if_neutral` |
| `stance_aware_actions.if_hezong.national_delta` | String | 是 | 推合纵背书时执行的国家三维变动（程序按此计算） |
| `stance_aware_actions.if_qin.national_delta` | String | 是 | 推亲秦背书时执行的国家三维变动 |
| `stance_aware_actions.if_neutral.national_delta` | String | 是 | 中立/君主自决时执行的国家三维变动 |
| `expected_player_stance` | String | 否 | 策划推测的玩家立场（仅供 AI 调优参考） |
| `fallback_if_neutral` | String | 是 | 中立时的君主自决行为（v7.3.7 改指向 `if_neutral` 分支） |

---

## 八、验收

- [x] 14 个困局模板（秦 5 + 赵 5 + 齐 4 = 14 · ≥ 3/君主）
- [x] **v7.3.7 全部 14 困局含 `stance_aware_actions` 三分支**（P0-2/3/4 修复）
- [x] v7.3.5 schema 对齐（opening + proposed_action）→ v7.3.7 升级 stance_aware
- [x] 困局与 6 关键事件联动表就位
- [x] 字段名与 C05 契约一致
- [x] 中立 fallback 规则就位（指向 if_neutral 分支）

---

## 九、v7.3.7 scenario_hint 结构化 JSON 重构（P1-15）

> **P1-15 修订**：原 `scenario_hint` 为中文表达式（如 `"round >= 2 AND 秦察觉赵齐有联合迹象"`），程序需自建 DSL 解析器。**v7.3.7 改为结构化 JSON**，统一用 `and` 列表 + 原子条件对象：

### 9.1 结构化 JSON 格式

```json
{
  "scenario_hint": {
    "and": [
      {"var": "round", "op": ">=", "value": 2},
      {"var": "qin_perceived_zhao_qi_alliance", "op": "==", "value": true}
    ]
  }
}
```

> **支持的 `var` 字段**：
> - `round` (int) - 当前回合
> - `qin_perceived_zhao_qi_alliance` (bool) - 秦是否察觉赵齐联盟
> - `qin_guowei` / `zhao_mengxin` / `qi_mengxin` (int) - 国家三维
> - `prev_zhao_qi_mengxin_sum` / `prev_zhao_qi_mengxin_avg` (int) - 上回合统计
> - `current_state` (String) - 当前君主状态（`audience` / `decision_made` / null）
> - `country` (String) - 君主归属国（`qin` / `zhao` / `qi`）
>
> **支持的 `op` 操作**：
> - `==` / `!=` / `>=` / `<=` / `>` / `<` - 数值比较
> - `in` - 值在列表中（`{"var": "round", "op": "in", "value": [2, 3]}`）
> - `not` - 取反（包在 `and` / `or` 外层）
>
> **逻辑组合**：
> - `{"and": [...]}` - 全部满足
> - `{"or": [...]}` - 任一满足
> - `{"not": {...}}` - 取反

### 9.2 示例对照

| 原中文表达式 | v7.3.7 结构化 JSON |
|---|---|
| `"round == 1"` | `{"var": "round", "op": "==", "value": 1}` |
| `"round >= 1 AND 玩家刚抵达秦"` | `{"and": [{"var": "round", "op": ">=", "value": 1}, {"var": "player_at_qin", "op": "==", "value": true}]}` |
| `"round in [2,3] AND zhao_mengxin + qi_mengxin >= 70"` | `{"and": [{"var": "round", "op": "in", "value": [2, 3]}, {"var": "prev_zhao_qi_mengxin_sum", "op": ">=", "value": 70}]}` |
| `"round == 4 AND (zhao_mengxin_avg_3rounds + qi_mengxin_avg_3rounds) / 2 >= 60"` | `{"and": [{"var": "round", "op": "==", "value": 4}, {"var": "prev_zhao_qi_mengxin_avg", "op": ">=", "value": 60}]}` |

### 9.3 14 个困局 scenario_hint 改写示例（详见各章节 JSON）

> 全部 14 个困局 JSON 中的 `scenario_hint` 字段已重构为结构化 JSON（详见 §二 - §四 各个 JSON 块）。本节展示 3 个典型示例（QIN_D1 / ZHAO_D1 / QI_D1），其余 11 个按相同模式重构。

### 9.4 待确认项

1. ~~**scenario_hint 是中文表达式**——程序需写一个简易 DSL 解析器~~ **v7.3.7 P1-15 已重构为结构化 JSON**（详见本节 §9.1-9.3）
2. **同回合同君主可能触发多个候选**——目前用"随机选 1 个"，是否改为"按 history 去重"（避免同一 dilemma 重复弹）？**D2 验证**
3. **QIN_D5 / QI_D4 触发概率极低**——保留以备 D3 调优（D4 ENG-22 可能用到）
4. **stance_aware_actions 的 national_delta 文本表达式**——程序需解析类似"赵齐盟信 +3 / 秦战心 −2"格式，**程序主导** D2 实现解析器。若太复杂 → 改为结构化 JSON delta 表。
