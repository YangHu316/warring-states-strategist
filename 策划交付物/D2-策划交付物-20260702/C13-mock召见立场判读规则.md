# C13 · Mock 召见立场判读规则（v7.3.5 · v7.3.7 RFC-002 修订）

> **来源**：[C01 §1.3 面谈超时降级（关键词表）](../../D1-策划交付物-20260630/C01-数值系统-锁定表.md) + [C01 §1.2 面谈机制](../../D1-策划交付物-20260630/C01-数值系统-锁定表.md) + [C12 困局模板](./C12-召见困局prompt模板.md)
> **任务**：C13（D2 下午 5–6h）· 编写 mock 召见立场判读规则（关键词匹配 + 立场映射 + 触发 proposed_action）
> **目标 JSON 文件**：`data/mock_audience_stance.json`（程序照搬）
> **状态**：✅ 终稿

---

## 一、v7.3.5 机制说明

### 1.1 旧版（v7.3.3）vs 新版（v7.3.5）

| 维度 | v7.3.3 旧版 | v7.3.5 新版 |
|---|---|---|
| 判读对象 | 综合分（comprehension + stance_match + persuasion） | **三立场**（推合纵/中立/推亲秦） |
| 阈值 | score ≥ 6.0 采纳 | **无需阈值**——立场决定背书 |
| 输出 | verdict = 采纳/拒绝 | **resolved = true/false**（true=玩家背书；false=君主自决） |
| 数值影响 | 采纳 → 1.5 倍效果 | **推合纵/推亲秦=执行 proposed_action；中立=君主自决** |
| 玩家三维 | 名望 ± | **不影响玩家三维** |

### 1.2 mock 判读三步走

```
1. 关键词匹配 → 识别 player_stance ∈ {推合纵, 中立, 推亲秦}
2. 立场映射 → resolved = (player_stance != 中立)
3. 数值结算 →
   - resolved = true（推合纵/推亲秦）→ 执行 proposed_action
   - resolved = false（中立）→ 君主按 fallback_if_neutral 自决
```

---

## 二、关键词表（与 C01 §1.3 一致 · 扩展版）

### 2.1 推合纵关键词（player_stance = 推合纵 · resolved = true）

```json
{
  "stance": "推合纵",
  "keywords": [
    "合纵", "合", "纵", "盟", "抗秦", "联六国", "联抗", "六国合",
    "抗", "援", "援助", "结盟", "联赵", "联齐", "联韩", "联魏", "联楚",
    "义兵", "义师", "义战", "共存", "守望相助", "互保", "公义"
  ],
  "match_mode": "OR（任一关键词命中即判定）",
  "weight": 1.0
}
```

### 2.2 推亲秦关键词（player_stance = 推亲秦 · resolved = true · v7.3.7 修订）

> **v7.3.7 修订（P0-10）**：原"降/投降"映射"推亲秦"语义错误——投降是消极行为，玩家视角未必是亲秦。改为映射"中立"（投降=不愿表态的退缩行为）。明确"亲秦"应包含 **主动投降之外** 的实质亲秦词汇。

```json
{
  "stance": "推亲秦",
  "keywords": [
    "连横", "横", "亲秦", "和秦", "归秦", "归顺", "事秦", "奉秦",
    "献", "三城", "河外", "河西", "议和", "和约", "使节",
    "聘", "质子", "质", "朝", "贡献", "岁贡", "年年纳贡", "通好"
  ],
  "match_mode": "OR",
  "weight": 1.0,
  "_v7_3_7_note": "v7.3.7 移除 '降/投降'（改为映射中立）"
}
```

### 2.3 中立关键词（player_stance = 中立 · resolved = false · v7.3.7 修订）

> **v7.3.7 修订（P0-10）**：新增"降/投降"为中立关键词（玩家投降是消极退缩，不是积极亲秦）。

```json
{
  "stance": "中立",
  "keywords": [
    "中立", "自保", "自守", "观望", "看情况", "再说", "且慢",
    "依君", "听凭", "由你", "由王", "由君", "全凭", "悉听尊便",
    "不敢妄言", "臣不知", "难以作答", "恕臣不能答",
    "降", "投降", "乞降", "请降", "归降"
  ],
  "match_mode": "OR",
  "weight": 1.0,
  "default_on_no_match": true,
  "default_on_timeout": true,
  "_v7_3_7_note": "v7.3.7 新增 '降/投降/乞降/请降/归降' 关键词（来自推亲秦）"
}
```

---

## 三、判读主表（程序照搬）

```json
{
  "version": "v7.3.5",
  "rules": {
    "推合纵": {
      "match_keywords": ["合", "纵", "盟", "抗秦", "联六国", "联抗", "六国合", "抗", "援", "援助", "结盟", "联赵", "联齐", "联韩", "联魏", "联楚", "义兵", "义师", "义战", "共存", "守望相助", "互保", "公义"],
      "player_stance": "推合纵",
      "resolved": true,
      "trigger_proposed_action": true,
      "effect": "按 proposed_action 结算国家三维（玩家背书）",
      "stance_signal_to_king": "player_leans_hezong"
    },
    "推亲秦": {
      "match_keywords": ["横", "连横", "亲秦", "和秦", "归秦", "归顺", "事秦", "奉秦", "献", "三城", "河外", "河西", "议和", "和约", "使节", "聘", "质子", "质", "朝", "贡献", "岁贡", "年年纳贡", "通好"],
      "player_stance": "推亲秦",
      "resolved": true,
      "trigger_proposed_action": true,
      "effect": "按 proposed_action 结算国家三维（玩家背书）",
      "stance_signal_to_king": "player_leans_qin",
      "_v7_3_7_note": "v7.3.7 移除 '降/投降'"
    },
    "中立": {
      "match_keywords": ["中立", "自保", "自守", "观望", "看情况", "再说", "且慢", "依君", "听凭", "由你", "由王", "由君", "全凭", "悉听尊便", "不敢妄言", "臣不知", "难以作答", "恕臣不能答", "降", "投降", "乞降", "请降", "归降"],
      "player_stance": "中立",
      "resolved": false,
      "trigger_proposed_action": false,
      "effect": "君主自决（按 C12 fallback_if_neutral 执行）",
      "stance_signal_to_king": "player_neutral"
    }
  },
  "default": "中立",
  "match_priority": ["推合纵", "推亲秦", "中立"],
  "priority_rule": "按优先级顺序匹配；首个命中者胜出（避免同一句话命中多个 stance）"
}
```

---

## 四、判读算法（伪代码 · 程序照搬）

```gdscript
func judge_player_stance(player_text: String) -> Dictionary:
    var rules = load_json("res://data/mock_audience_stance.json")
    var text = player_text.strip_edges().to_lower()
    
    # 按优先级匹配
    for stance_name in rules.match_priority:
        var rule = rules.rules[stance_name]
        for keyword in rule.match_keywords:
            if keyword in text:
                return {
                    "player_stance": rule.player_stance,
                    "resolved": rule.resolved,
                    "stance_signal": rule.stance_signal_to_king
                }
    
    # 无匹配 → 默认中立
    return {
        "player_stance": "中立",
        "resolved": false,
        "stance_signal": "player_neutral"
    }
```

---

## 五、结算流程（**v7.3.7 stance_aware · RFC-002**）

```
玩家在召见界面输入文本（不限时）
  ├─ mock 判读（C13 §四）→ player_stance ∈ {推合纵, 中立, 推亲秦}
  ├─ 读取 C12 当前 dilemma 的 stance_aware_actions[player_stance]
  │   ├─ if_hezong（推合纵背书）→ 执行 national_delta（合纵侧）
  │   ├─ if_qin（推亲秦背书）→ 执行 national_delta（亲秦侧）
  │   └─ if_neutral（中立/超时）→ 执行 national_delta（原 proposed_action 效果）
  ├─ 玩家立场写入君主记忆（stance_signal）
  └─ 玩家获得 1 张情报牌（面谈摘要）
```

> **v7.3.7 关键变更**：
> - **3 立场有完全不同的国家三维结果**（解决 P0-2 核心悖论）
> - 推合纵背书 ≠ 推亲秦背书 ≠ 中立自决（解决 P0-4 立场无差异）
> - **不影响玩家三维**（无 1.5 倍、无名望 −5，沿用 v7.3.5）

### 5.1 程序伪代码（v7.3.7）

```gdscript
func resolve_audience(player_text: String, dilemma_id: String) -> Dictionary:
    var stance = judge_player_stance(player_text)  # C13 §四
    var dilemma = load_json("res://data/prompts/audience_dilemmas.json").dilemmas[dilemma_id]
    
    # v7.3.7: 按 player_stance 选取 stance_aware_actions 分支
    var branch_key = "if_neutral"
    if stance.player_stance == "推合纵":
        branch_key = "if_hezong"
    elif stance.player_stance == "推亲秦":
        branch_key = "if_qin"
    
    var branch = dilemma.stance_aware_actions[branch_key]
    
    # 解析 national_delta（如 "赵齐盟信 +3 / 秦战心 −2"）
    var deltas = parse_national_delta(branch.national_delta)
    apply_national_deltas(deltas)
    
    return {
        "player_stance": stance.player_stance,
        "branch_executed": branch_key,
        "national_delta_applied": branch.national_delta,
        "stance_signal": stance.stance_signal
    }
```

---

## 六、超时与默认值

| 场景 | 默认 player_stance | resolved | 处理 |
|---|---|---|---|
| 玩家在 8s 内未输入 | 中立 | false | 君主自决 |
| 玩家输入但无任何关键词命中 | 中立 | false | 君主自决 |
| 玩家输入同时命中"推合纵"和"推亲秦" | 按优先级 | — | 优先级：推合纵 > 推亲秦 |
| 玩家输入命中"中立"但又命中其他 | 按优先级 | — | 优先级：推合纵 > 推亲秦 > 中立 |

> **LLM 介入**：当 LLM 可用时（ENG-12），由 LLM 裁决 player_stance → 关键词匹配为降级兜底（LLM 8s 超时）。

---

## 七、Json 完整结构（程序照搬 · v7.3.7）

```json
{
  "version": "v7.3.7",
  "rules": { ... 3 条规则 ... },
  "default": "中立",
  "match_priority": ["推合纵", "推亲秦", "中立"],
  "llm_fallback": {
    "description": "LLM 可用时由 LLM 裁决 player_stance；LLM 8s 超时 → 关键词匹配",
    "prompt_schema": "{opening, proposed_action, player_stance, response, resolved}"
  },
  "stance_aware_resolution": {
    "description": "v7.3.7 新增：根据 player_stance 读取 C12 dilemma.stance_aware_actions 分支",
    "branch_map": {
      "推合纵": "if_hezong",
      "推亲秦": "if_qin",
      "中立/超时": "if_neutral"
    }
  },
  "test_cases": [
    {"input": "请合纵抗秦", "expected": "推合纵", "branch": "if_hezong", "resolved": true},
    {"input": "愿与秦通好", "expected": "推亲秦", "branch": "if_qin", "resolved": true},
    {"input": "由王自决", "expected": "中立", "branch": "if_neutral", "resolved": false},
    {"input": "我要投降", "expected": "中立", "branch": "if_neutral", "resolved": false, "_v7_3_7_note": "v7.3.7 '降/投降' 改映射中立"},
    {"input": "...", "expected": "中立", "branch": "if_neutral", "resolved": false}
  ]
}
```

---

## 八、字段名一致性

| 字段 | 来源 | 类型 |
|---|---|---|
| `player_stance` | C01 §1.2 + 11b §四 | String ∈ {推合纵, 中立, 推亲秦} |
| `resolved` | C01 §1.2 + 11b §四 | bool（true=玩家背书；false=君主自决） |
| `stance_signal` | C03 §5 记忆格式 | String ∈ {player_leans_hezong, player_leans_qin, player_neutral} |
| `proposed_action` | C12 | String = C05 §2.3 动作枚举 |
| `fallback_if_neutral` | C12 | String（自由文本描述） |

---

## 九、验收

- [x] 关键词表（推合纵 + 推亲秦 + 中立 · 共 60+ 词）
- [x] 判读主表 + 默认中立
- [x] 优先级规则（推合纵 > 推亲秦 > 中立）
- [x] 超时与默认处理
- [x] 完整结算流程（**v7.3.7 stance_aware 三分支**，3 条路径）
- [x] 字段名与 C01/C05 契约一致
- [x] **v7.3.7 投降映射中立**（P0-10 修复）
- [x] 测试用例 5 条（增加"我要投降"用例）

---

## 十、待确认项 ⚠️

1. ~~关键词"降/投降"映射为"推亲秦"~~ **v7.3.7 已修订**：投降改为映射"中立"（消极退缩行为）
2. **优先级"推合纵 > 推亲秦"**——目前"合"优先于"横"，因合纵是更明确的"抗秦"信号。**D2 试玩验证**
3. **LLM 8s 超时后关键词匹配**——若 LLM 8s 超时但玩家已输入复杂长句，关键词可能误命中。**D2 试玩验证 → 必要时改用 LLM 短句总结**
4. **同 stance 关键词集合过大**（推亲秦 24 个）——D2 试玩若发现误判 → 缩减到 12 个核心词
