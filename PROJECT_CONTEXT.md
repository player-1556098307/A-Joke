---
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: '8f66aceb-1fc6-43a6-9ed1-8374a2cd337f'
  PropagateID: '8f66aceb-1fc6-43a6-9ed1-8374a2cd337f'
  ReservedCode1: '7e40dc62-8d0c-4a91-bc26-378b52d796a9'
  ReservedCode2: '7e40dc62-8d0c-4a91-bc26-378b52d796a9'
---

# A-Joke Test 项目上下文

> 本文件供 AI Agent 快速理解项目全貌，无需重复探索即可开始开发/测试/运维。
> 最后更新：2026-08-20

---

## 1. 项目概况

- **项目名称**: A Joke Test — 回合制石头剪刀布 + 角色对战游戏
- **引擎**: Godot 4.7.1 stable（Forward+ 渲染，D3D12）
- **项目路径**: `E:\ajoke-g\A-Joke`
- **Godot 可执行文件**: `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`（不在 PATH，必须全路径调用）
- **Git 远端**: `https://github.com/player-1556098307/A-Joke.git`（main 分支）
- **游戏模式**: 单机 PvE（vs AI） + 联机 PvP（Nakama + ENet） + HGW 大逃杀（独立子系统）
- **IP**: 不限于火影忍者（线下版多 IP），当前线上版以火影角色为主
- **设计理念**: 灵感来源于三国杀（座位距离机制）+ 石头剪刀布 + 角色技能对战

---

## 2. 目录结构

```
A-Joke/
├── project.godot              # Godot 项目配置（autoload 定义在此）
├── CLAUDE.md                  # 通用编码准则（非项目特定）
├── PROJECT_CONTEXT.md         # ← 本文件
├── icon.svg
├── export_presets.cfg         # 导出预设
├── deploy_server.py           # 服务器部署脚本
├── proxy.ps1                  # 网络代理脚本
├── test_rpc.py                # RPC 测试脚本
│
├── core/                      # 核心逻辑（所有autoload单例+游戏机制）
│   ├── game_manager.gd        # 游戏主循环状态机（~3147行）★最核心
│   ├── player_state.gd        # 玩家运行时状态（~450行）★
│   ├── round_resolver.gd      # 手势结算 + 技能效果执行
│   ├── ai_controller.gd       # AI 决策逻辑（~548行）
│   ├── distance_system.gd     # 环形座位距离计算
│   ├── action_log.gd          # 行动日志
│   ├── match_record.gd        # 对局记录
│   ├── player_match_stats.gd  # 玩家对局统计
│   ├── skill_use_log.gd       # 技能使用日志
│   ├── round_snapshot.gd      # 回合快照
│   ├── player_state_snapshot.gd # 玩家状态快照
│   ├── scene_manager.gd       # 跨场景数据传递（autoload）
│   ├── settings_manager.gd    # 设置持久化（autoload）
│   ├── net/                   # 联机层
│   │   ├── NetworkManager.gd  # Nakama 认证 + ENet 连接（autoload）
│   │   ├── NetworkProtocol.gd # 协议定义 SrvOp(18种) + CliOp(5种)
│   │   ├── NetworkGameHost.gd # 主机：GameManager 信号→RPC 广播
│   │   ├── NetworkGameClient.gd # 客户端：RPC→信号映射
│   │   ├── ClientStateSync.gd # 状态同步
│   │   ├── RoomManager.gd     # 房间生命周期（autoload）
│   │   └── LatencyMonitor.gd  # 延迟监控
│   └── hgw/                   # HGW 大逃杀模式（独立子系统）
│       ├── hgw_game_manager.gd
│       ├── hgw_player_state.gd
│       ├── combat_manager.gd
│       ├── damage_resolver.gd
│       ├── energy_manager.gd
│       ├── event_table.gd
│       ├── grail_manager.gd
│       ├── seal_manager.gd
│       ├── shrink_ring.gd
│       ├── terrain_effect.gd
│       ├── map_generator.gd
│       ├── boss_ai.gd
│       └── hgw_ai_controller.gd
│
├── data/
│   └── characters.gd          # 角色数据表（autoload，硬编码 LIST + get_by_id）
│
├── resources/                 # 资源文件（.tres）
│   ├── character_data.gd      # CharacterData 类定义
│   ├── skill_data.gd          # SkillData 类定义
│   ├── skill_effect.gd        # SkillEffect 类定义（含 EffectType 枚举）
│   ├── characters/            # 15个角色 .tres 文件
│   │   ├── 漩涡鸣人.tres
│   │   ├── 宇智波佐助.tres
│   │   ├── 宇智波佐助（疾风传）.tres
│   │   ├── 春野樱.tres
│   │   ├── 春野樱（疾风传）.tres
│   │   ├── 漩涡鸣人（疾风传）.tres
│   │   ├── 千手柱间.tres
│   │   ├── 千手柱间（秽土转生）.tres
│   │   ├── 迈特凯.tres
│   │   ├── 希耶尔.tres
│   │   ├── 卫宫.tres
│   │   ├── 宇智波泉奈.tres
│   │   ├── 宇智波止水（须佐能）.tres
│   │   ├── 宇智波止水（天劫）.tres
│   │   ├── 波风水门.tres      # 仅在 character_select.gd preload，未注册到 LIST
│   │   ├── portraits/         # 角色立绘图片
│   │   └── skills/            # 止水技能独立资源文件
│   └── portaits/              # （拼写如此，旧目录）
│
├── ui/
│   ├── game_ui.gd             # 主游戏界面（~3316行）★
│   └── references/            # UI 参考资源
│
├── scenes/                    # 场景文件
│   ├── main.tscn              # 主场景入口
│   ├── main_menu.tscn         # 主菜单
│   ├── character_select.gd/.tscn # 角色选择
│   ├── game_ui.tscn           # 游戏界面场景
│   ├── game_over.gd/.tscn     # 游戏结束
│   ├── settings.gd/.tscn      # 设置
│   ├── net/                   # 联机场景
│   └── hgw/                   # HGW 场景
│
├── tests/                     # 测试套件（16个，905断言）
│   ├── *.gd                   # 测试脚本（extends Node）
│   ├── *.tscn                 # 测试场景
│   └── backtrack_test.tscn    # 回溯测试场景（脚本待编写）
│
├── server/
│   └── server_main.gd/.tscn   # 服务端入口（导出为二进制部署）
│
├── addons/
│   ├── com.heroiclabs.nakama/ # Nakama SDK（联机后端）
│   └── character_wizard/      # 角色创建向导插件
│
├── assets/                    # 美术/音效资源
└── tools/                     # 工具脚本
```

---

## 3. Autoload 单例（7个）

在 `project.godot` 的 `[autoload]` 段定义，全局可直接用类名访问：

| 单例名 | 脚本 | 职责 |
|---|---|---|
| `GameManager` | `core/game_manager.gd` | 游戏主循环状态机（~3147行），管理所有玩家/回合/结算/淘汰 |
| `SceneManager` | `core/scene_manager.gd` | 跨场景数据传递 |
| `SettingsManager` | `core/settings_manager.gd` | 设置持久化（ConfigFile → user://settings.cfg） |
| `NetworkManager` | `core/net/NetworkManager.gd` | Nakama 会话 + ENet 游戏连接 |
| `Nakama` | `addons/com.heroiclabs.nakama/Nakama.gd` | 在线后端 SDK |
| `Characters` | `data/characters.gd` | 角色数据表（硬编码 LIST + get_by_id） |
| `RoomManager` | `core/net/RoomManager.gd` | 房间生命周期管理 |

> **测试中直接用 `GameManager` 类名访问**，不需要实例化。

---

## 4. 游戏阶段状态机

```
SETUP → GESTURE_INPUT → RESOLVING → [TIEBREAK_INPUT → TIEBREAK_RESOLVING] →
  PREPARATION → ACTION_INPUT → APPLYING → ELIMINATION → END_PHASE → ROUND_END →
  GESTURE_INPUT（下一回合）... → GAME_OVER
```

| 阶段 | 说明 |
|---|---|
| `SETUP` | 初始化 |
| `GESTURE_INPUT` | 等待所有玩家出拳（麻痹玩家自动 SKIP） |
| `RESOLVING` | 手势结算（0.5秒延时后执行 `_resolve_round`） |
| `TIEBREAK_INPUT` | 多人胜出时加赛出拳 |
| `TIEBREAK_RESOLVING` | 加赛结算 |
| `PREPARATION` | 准备阶段：有准备技能的玩家按逆时针轮询释放（泉奈荣耀/卫宫投影/新止水回溯） |
| `ACTION_INPUT` | 胜者选择行动（聚气/使用技能） |
| `APPLYING` | 执行行动效果 |
| `ELIMINATION` | 淘汰检测（HP<=0 判定） |
| `END_PHASE` | 回合结束前：钟结算 + 招架决策 |
| `ROUND_END` | 回合结束：延迟伤害/九尾推进/状态递减 |
| `GAME_OVER` | 游戏结束 |

### 阶段流转关键规则

1. **GESTURE_INPUT 进入时**：若 `_prev_phase` 不是 RESOLVING/TIEBREAK_RESOLVING（新回合而非平局重出），则 `_current_round_number += 1`，并调用 `_apply_paralyze()`
2. **_resolve_round**：单胜者 → 设 `_sole_winner_id` → 拍快照 → 进入 PREPARATION；多人胜出 → TIEBREAK_INPUT；平局 → 清手势回 GESTURE_INPUT
3. **RESOLVING 延时**：`_resolve_timer.wait_time = 0.5`（非2秒），动画与流程解耦
4. **END_PHASE → 招架决策**：有钟机制的胜者被询问是否招架；人类玩家发 `end_phase_bell_decision_required` 信号等待 UI 回复，**测试中必须连接此信号并回复，否则流程挂起**

---

## 5. 核心数据模型

### 5.1 PlayerState（`core/player_state.gd`，~450行）

存储单个玩家一局完整状态。`class_name PlayerState extends RefCounted`。

**枚举**:
- `Gesture { NONE, ROCK, SCISSORS, PAPER, SKIP }`
- `ActionType { NONE, CHARGE, USE_SKILL }`

**基础字段**:
- `player_id: int` — 玩家ID（0-based）
- `player_name: String`
- `character: CharacterData`
- `hp: float` — 当前生命值
- `energy: int` — 当前能量
- `is_alive: bool` / `is_human: bool`
- `current_gesture: Gesture` — **本回合手势（字段名是 `current_gesture`，不是 `current_round`）**
- `pending_action: ActionType` / `pending_skill_index: int` / `skill_target_id: int`

**跨回合持续状态字段**（按角色/机制分组）:

| 字段 | 类型 | 适用角色/机制 | 说明 |
|---|---|---|---|
| `shield` | int | 通用 | -1=全挡, >0=数值, 0=无 |
| `paralyze_turns` | int | 通用 | 麻痹剩余回合（自动SKIP出拳，不可用任何技能） |
| `knockdown_turns` | int | 通用 | 击飞剩余回合（可猜拳但强制聚气） |
| `knockdown_consumed_this_round` | bool | 通用 | 击飞本回合是否已生效 |
| `clone_count` | int | 通用 | 影分身数量 |
| `delayed_damages` | Array[Dictionary] | 通用 | 延迟伤害队列 [{damage, trigger_in, attacker_id}] |
| `unlocked_skills` | Array[SkillData] | 通用 | 运行时解锁技能 |
| `skill_disabled_turns` | int | 通用 | 失去技能剩余回合 |
| `limited_skills_used` | Array[String] | 通用 | 已用限定技列表 |
| `dealt_damage_this_round` | bool | 通用 | 本回合是否造成伤害（钟获取判定） |
| `took_damage_this_round` | bool | 通用 | 本回合是否受伤（狂战士判定） |
| `bell_count` / `counter_stance` | int / bool | 柱间 | 钟/防反 |
| `gate_count` / `invincible_turns` / `burning` / `berserker` / `consecutive_rounds` / `lost_skills` | - | 迈特凯 | 八门/无敌/燃烧/狂战/连胜/永久失去技能 |
| `pending_hp_payment` | - | 迈特凯 | 血付待定 |
| `ftg_marks` / `ftg_marked_by` / `nine_tails_stage` / `nine_tails_invincible` | - | 水门 | 飞雷神标记/九尾 |
| `can_crit_next` / `crit_checked_this_round` | - | 希耶尔 | 暴击 |
| `max_energy` / `stomp_active` / `force_win_next_round` | - | 秽土柱间 | 气上限/跺脚/强制判胜 |
| `projected_skill` / `projected_used_this_round` / `binding_field_turns` / `binding_field_targets` / `binding_field_skills` / `binding_field_force_win` | - | 卫宫 | 投影/无限剑制 |
| `glory_unlocked` / `glory_used_this_round` / `untargetable_turns` / `uchiha_stance` | - | 泉奈 | 荣耀/招架/不可选 |
| `susanoo_spiral_unlocked` / `has_kotoamatsukami_skill` / `kotoamatsukami_used` / `takeover_active` / `koto_awaiting_confirm` / `last_hit_by_id` | - | 止水(须佐) | 须佐链/夺舍 |
| `phantom_count` / `backtrack_snapshot` | - | 止水(天劫) | 幻影/回溯快照 |

**关键方法**:
- `capture_backtrack_snapshot() -> Dictionary` — 新止水回溯用全体快照（~40字段）
- `restore_from_backtrack_snapshot(snap: Dictionary)` — 从快照恢复全部字段
- `save_pre_takeover_snapshot()` / `restore_pre_takeover_snapshot()` — 旧止水夺舍前后状态
- `reset_round_data()` — 每回合开始重置临时数据（手势/行动/伤害标记等）
- `get_all_skills() -> Array[SkillData]` — 返回角色固有技能 + 解锁技能，过滤禁用/限定/被动等

### 5.2 CharacterData（`resources/character_data.gd`）

```
character_name: String
max_hp: float
basic_attack_cost: int = 1
portrait: Texture2D
alternate_portrait: Texture2D = null
avatar_emoji: String = ""
skills: Array[SkillData]
tags: Array[String] = []     # 战士/法师/坦克/刺客（可多个）
grade: String = "C"          # C/B/A/S（角色选择界面筛选）
```

### 5.3 SkillData（`resources/skill_data.gd`）

```
skill_name: String
description: String
energy_cost: int
min_range: int
max_range: int              # 999=无限
effects: Array[SkillEffect]
bell_cost: int = 0          # 钟消耗
is_limited: bool = false    # 限定技
bonus_if_paralyzed: int = 0 # 禁锢增伤
is_passive: bool = false    # 被动技
can_pay_with_hp: bool = false
ftg_cost: int = 0           # 飞雷神标记消耗
```

### 5.4 SkillEffect（`resources/skill_effect.gd`）

```
effect_type: EffectType
value: float
target: EffectTarget        # ENEMY_SINGLE / ENEMY_ALL / SELF / ENEMY_SPLASH
duration: int = 1           # DELAYED_DAMAGE用
unlock_skill: SkillData     # UNLOCK_SKILL用
splash_range: int = 1       # ENEMY_SPLASH用
bonus_if_paralyzed: int = 0
lose_skill_name: String = ""# LOSE_SKILL用
```

### 5.5 EffectType 完整枚举（32种）

| 值 | 枚举名 | 说明 |
|---|---|---|
| 0 | DAMAGE | 直接伤害，value=伤害量 |
| 1 | SHIELD | 护盾，value=-1全挡/>0数值 |
| 2 | PARALYZE | 麻痹，value=回合数 |
| 3 | CHANGE_DISTANCE | 改变距离，value=偏移量 |
| 4 | HEAL | 治疗，value=回复量 |
| 5 | DELAYED_DAMAGE | 延迟伤害，duration回合后触发 |
| 6 | UNLOCK_SKILL | 永久解锁技能 |
| 7 | CLONE_SHIELD | 影分身（全挡+充能加成） |
| 8 | DISABLE_SKILL | 失去技能，value=回合数 |
| 9 | COUNTER_STANCE | 防反姿态 |
| 10 | TRUE_DAMAGE | 真实伤害（无视盾/分身/防反/无敌） |
| 11 | LOSE_SKILL | 永久移除指定技能 |
| 12 | FTG_MARK | 飞雷神标记（value=0.5伤害+标记） |
| 13 | FTG_CHARGE | 飞雷神聚气（自身+1标记） |
| 14 | FTG_REMOVE | 飞雷神拔除 |
| 15 | NINE_TAILS | 漂泊九尾（三段延迟攻击） |
| 16 | PIERCE_DAMAGE | 穿透伤害（无视盾/无敌/圣盾） |
| 17 | DEATH_SENTENCE | 断罪死（7次猜拳，赢≥4即死） |
| 18 | PROJECT_SKILL | 投影（复制他人技能一次） |
| 19 | BINDING_FIELD | 无限剑制（下次必赢+结界5回合） |
| 20 | UNTARGETABLE | 无法选择，value=回合数 |
| 21 | GLORY_TAKEOVER | 荣耀夺取 |
| 22 | UCHIHA_STANCE | 宇智波流招架 |
| 23 | HIANO_KAGEROHI | 日晕舞（旧止水，多段可中断） |
| 24 | SUSANOO_SLASH | 须佐能乎·斩（本回合无敌+延迟2伤） |
| 25 | SUSANOO_SPIRAL | 须佐能乎·螺旋（3段+无敌+封技+解锁九十九） |
| 26 | SUSANOO_NINETY_NINE | 须佐能乎·九十九（4段+无敌） |
| 27 | KOTOAMATSUKAMI | 别天神·夺舍（旧止水限定技） |
| 28 | KNOCKDOWN | 击飞，value=回合数 |
| 29 | BACKTRACK | 天劫·回溯（新止水，全体快照回滚） |
| 30 | HIROARI | 日影舞（新止水，4段2伤跨目标分配） |
| 31 | PHANTOM_BODY | 幻影瞬身（新止水被动，获幻影+闪避） |
| 32 | DIAMOND_AOE | 送你砖石（黑塔被动：目标血量<50%时对范围1敌人造成1伤） |
| 33 | GENJUTSU | genjutsu（黑塔被动：伤害后目标与大黑塔距离-1） |
| 34 | KAIJI_MARK | 解读（大黑塔被动：伤害后标记【解】，【解】玩家与大黑塔距离-1且受伤+1） |
| 35 | KAIJI_ENERGY | 格局打开（大黑塔被动：【解】玩家受伤后大黑塔+1气） |
| 36 | MAGIC | 魔法（大黑塔主动：3气对目标2伤+对全体【解】1伤） |

> **新增效果类型时**：在 `skill_effect.gd` 的 enum 末尾追加，编号自动递增。同步更新 `game_manager.gd` 中所有匹配该枚举的处理逻辑。

---

## 6. 信号驱动架构

GameManager 通过 **40+ 信号** 驱动 UI（`ui/game_ui.gd` ~3316行），UI 零直接状态查询。

**信号分类**:
- **通用**: `phase_changed`, `round_resolved`, `action_required`, `skill_applied`, `player_charged`, `player_eliminated`, `game_over`, `player_skipped`, `player_paralyzed`, `player_knocked_down`, `player_shielded`, `distance_changed`, `delayed_damage_triggered`, `clone_destroyed`, `skill_unlocked`, `skill_disabled`
- **钟机制**: `bell_gained`, `counter_stance_entered/triggered/ended`, `end_phase_bell_decision_required/made`
- **迈特凯**: `player_invincible`, `player_burning`, `player_berserker`, `gate_changed`, `eighth_gate_opened`, `skill_lost`, `hp_payment_made`, `burn_damage_triggered`
- **波风水门**: `ftg_marks_changed`, `ftg_mark_applied/removed`, `ftg_swap_triggered`, `ftg_dodge_triggered`, `ftg_intercept_required/made`, `rasengan_counter_required/made`, `nine_tails_*`
- **卫宫**: `project_skill_required/made`, `binding_field_started/ended`, `projected_skill_gained/lost`
- **泉奈**: `glory_unlocked_changed`, `glory_takeover`, `glory_required`, `uchiha_stance_entered`, `uchiha_counter_triggered`
- **止水(须佐)**: `hiano_interrupt_required/made`, `susanoo_*`, `kotoamatsukami_required/made/takeover`, `takeover_reverted`
- **止水(天劫)**: `backtrack_required/made/performed`, `phantom_changed`, `phantom_dodge_triggered/required/made`, `hiroari_used`, `hiroari_targets_required/made`

**信号回调模式**: GameManager 在 `_ready()` 中 `connect` 所有决策信号到对应的 `_on_xxx_made` 处理函数。UI 通过 `submit_xxx()` 方法提交决策。

---

## 7. 角色列表（15+2个）

| ID | 角色名 | HP | 定位 | grade | 核心技能 |
|---|---|---|---|---|---|
| naruto | 漩涡鸣人 | 6 | 战士 | - | 螺旋丸·影分身 |
| sasuke | 宇智波佐助 | 6 | 法师 | - | 豪火球·千鸟 |
| sasuke2 | 宇智波佐助（疾风传） | 6 | 刺客 | - | 火遁·铁锤 |
| sakura | 春野樱 | 8 | 坦克 | - | 蓄力拳·治疗 |
| hashirama | 千手柱间（侠影江湖） | 10 | 坦克/法师 | S | 砸钟·招架·木龙之术 |
| mightgai | 迈特凯（夏日限定） | 16 | 战士 | - | 八门遁甲·昼虎·夜凯·夕象 |
| xiye | 希耶尔 | 6 | 战士/刺客 | - | 代行者·相位滑剑·断头台·断罪死 |
| edohashirama | 千手柱间（秽土转生） | 8 | 战士/法师 | - | 仙人之力·树界降诞·木人之术·真数千手 |
| emiya | 卫宫 | 7 | 射手 | - | 投影·伪·螺旋剑·无限剑制 |
| izuna | 宇智波泉奈 | 6 | 刺客/法师 | - | 火遁·宇智波流·宇智波的荣耀 |
| shisui | 宇智波止水（须佐能） | 6 | 刺客/法师 | - | 日晕舞·须佐链·别天神·夺舍 |
| shisui_new | 宇智波止水（天劫） | 6 | 刺客 | A | 幻影瞬身·日影舞·别天神(回溯) |
| sakura_fy | 春野樱（疾风传） | 8 | 战士/坦克 | - | 怪力·恢复 |
| naruto_fy | 漩涡鸣人（疾风传） | 8 | 法师/刺客 | - | 螺旋丸·螺旋手里剑·影分身 |
| minato | 波风水门 | - | - | - | 飞雷神·螺旋丸·九尾（仅在 character_select.gd preload，未注册到 LIST） |
| herta | 黑塔 | 6 | 法师 | B | 普攻·送你砖石(被动)·genjutsu(被动) — EffectType 32/33 |
| big_herta | 大黑塔 | 8 | 法师 | A | 普攻·解读(被动)·格局打开(被动)·魔法 — EffectType 34/35/36 |

**慈悲尖塔专属角色**（`resources/characters/tower/`，仅塔模式使用）:
- 司马懿（狂）
- 漩涡鸣人（仙人模式）
- 破败王者（怒）

### 角色注册（3处硬编码同步）

新增角色时必须同步以下3处：
1. `data/characters.gd` — LIST 数组追加角色字典
2. `scenes/character_select.gd` — `_CHARACTER_PRELOADS` 追加 preload
3. HGW 模式（如需支持）

---

## 8. 关键机制设计规则（易错点）

### 8.1 麻痹 vs 击飞（独立机制，不可混用）

| | 麻痹 (paralyze) | 击飞 (knockdown) |
|---|---|---|
| 猜拳 | 自动SKIP，不参与 | 正常猜拳，可获胜获得回合 |
| 行动 | 无回合 | 有回合但强制只能聚气 |
| 技能 | **不可使用任何技能**（含幻影闪避等被动） | 仅强制聚气，技能不受额外限制 |
| 递减 | `_end_round` 中递减 | 仅在本回合实际生效（强制聚气）后才递减 |

> **易错**: 麻痹状态下不可使用任何技能——包括新止水的幻影闪避。所有检查技能可用性的地方都要加 `paralyze_turns > 0` 校验。

### 8.2 钟机制（仅千手柱间·侠影江湖）

- **钟获取**: 回合结束时，本回合造成过伤害（`dealt_damage_this_round == true`）且有钟机制的角色 +1 钟
- **钟消耗技能**: 砸钟（`bell_cost=1`）和招架（`bell_cost=1`）
- **砸钟不获钟**: `bell_cost > 0` 的技能造成的伤害**不计入** `dealt_damage_this_round`，防止砸钟回钟循环。判定位置：`game_manager.gd` 中4处伤害标记处均包 `if skill.bell_cost <= 0:`
- **招架**: END_PHASE阶段，胜者有钟时被询问是否招架（人类发信号等UI回复）

### 8.3 伤害标记（dealt_damage_this_round）

在 `game_manager.gd` 中有 **4处** 伤害标记位置，所有位置都需检查 `bell_cost <= 0`：
1. `_apply_actions` 主流程（约1102行）
2. `_finalize_skill_use`（约1495行）
3. `_resume_phantom_dodge_action`（约3046行）
4. `_resume_ftg_action`（约3130行）

标记条件：效果类型为 DAMAGE / TRUE_DAMAGE / FTG_MARK / PIERCE_DAMAGE / DEATH_SENTENCE，且 `result.damage_dealt > 0`。

### 8.4 新旧止水区分

| | 新止水（天劫） | 旧止水（须佐能） |
|---|---|---|
| 角色名 | `宇智波止水（天劫）` | `宇智波止水（须佐能）` |
| ID | `shisui_new` | `shisui` |
| 判断依据 | 技能含"日影舞"→ `_is_new_shisui` | 技能含"须佐能乎·斩"→ `_is_shisui` |
| 别天神 | "别天神"（回溯） | "别天神·夺舍" |
| 核心机制 | 幻影瞬身+日影舞+回溯 | 日晕舞+须佐能乎链+夺舍 |

### 8.5 回溯机制（新止水·别天神）

- **触发时机**: 准备阶段（PREPARATION），新止水回合开始时
- **条件**: 有1气 + 上回合不是自己回合（`_prev_round_winner_id != 自己`）+ 上回合快照存在
- **快照滚动**: `_capture_round_pre_snapshot()` 在每次唯一胜者确定后调用，`_prev_round_pre_snapshot = _last_round_pre_snapshot`（旧快照滚动为"上回合快照"），新快照存入 `_last_round_pre_snapshot`
- **恢复逻辑** (`_apply_backtrack`):
  1. 先恢复全体玩家状态（`restore_from_backtrack_snapshot`）
  2. 恢复距离系统（`_distance_system.restore_from_snapshot`）
  3. 重新加入存活但不在座位表的玩家
  4. **最后**扣1气（扣气在恢复之后，不会被快照覆盖）
  5. 清空 `_prev_round_pre_snapshot`
- **快照字段**: ~40个字段（hp/energy/shield/paralyze/knockdown/clone_count/is_alive/phantom_count/consecutive_rounds 等）
- **注意**: `delayed_damages` **不在** backtrack 快照中（仅在 pre_takeover_snapshot 中）
- **跳过处理**: `submit_backtrack_decision(pid, false)` → 清空快照 + 继续推进准备阶段（不耗气）
- **死亡复活**: 回溯恢复已死亡玩家时，由 GameManager 重新加入距离系统

### 8.6 幻影瞬身（新止水被动）

- 普攻命中 +1 幻影（至多3）
- 每个幻影使普攻伤害 +0.5（浮点）
- 受击时可消耗 1气 + 1幻影 闪避（完全免疫伤害）
- 闪避可在一回合内多次触发（受资源限制）
- 闪避是可选的（人类弹窗决策，AI自动判断）
- **麻痹时不可闪避**（3处校验：`_check_phantom_dodge_intercept` / `_on_phantom_dodge_made` / `_apply_phantom_dodge`）

### 8.7 无敌机制

- `invincible_turns > 0` 时无视所有伤害和控制
- 递减：`_end_round` 中递减

### 8.8 距离系统（环形座位）

- 玩家按入座顺序围成环形
- 距离 = min(顺时针, 逆时针) + 永久偏移量，最小1
- 技能射程校验：`min_range <= dist <= max_range`
- 死亡玩家从距离系统移除（`remove_player`）
- `modify_distance(from, to, delta)` 修改永久偏移
- `swap_seats(a, b)` 交换座位（飞雷神换位）

---

## 9. 联机架构

| 层 | 文件 | 职责 |
|---|---|---|
| 顶层 | `NetworkManager.gd` | Nakama认证 + ENet连接 |
| 协议 | `NetworkProtocol.gd` | SrvOp(18种) + CliOp(5种)，JSON序列化 |
| 服务器 | `NetworkGameHost.gd` | 包装GameManager→RPC广播 |
| 客户端 | `NetworkGameClient.gd` | 接收RPC→映射同名信号 |
| 状态同步 | `ClientStateSync.gd` | 写入本地GameManager缓存 |
| 房间 | `RoomManager.gd` | lobby+game生命周期 |

**网络适配新角色/新机制时需同步**:
- `NetworkProtocol.gd` — 新增 SrvOp/CliOp
- `NetworkGameHost.gd` — 信号→RPC广播
- `NetworkGameClient.gd` — RPC→信号映射
- `ClientStateSync.gd` — 状态字段同步
- `game_ui.gd` — UI弹窗/显示

---

## 10. HGW 模式（独立子系统）

`core/hgw/` 是独立的大逃杀/圣杯战争模式，有独立的状态机和子系统：
- 六边形地图、圣杯王座、三印系统、缩圈
- 独立的 `hgw_game_manager.gd` / `hgw_player_state.gd` / `combat_manager.gd` 等
- **与单机/联机模式完全独立**，不共享 GameManager

---

## 11. 测试规范

### 11.1 命令格式

```powershell
& "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "E:\ajoke-g\A-Joke" res://tests/xxx_test.tscn
```

**关键规则**:
- **必须用场景运行**（`res://tests/xxx_test.tscn`），**不能用 `--script`**（autoload 会挂起）
- Godot 不在 PATH 中，必须用全路径
- `--headless` 无头模式
- 单个测试超时设 90 秒（大部分 5-10 秒完成）

### 11.2 后台运行并落盘日志（避免超时）

```powershell
$p = Start-Process -FilePath "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" `
    -ArgumentList '--headless','--path','E:\ajoke-g\A-Joke','res://tests/xxx_test.tscn' `
    -RedirectStandardOutput "E:\ajoke-g\.temp\test_out.log" `
    -RedirectStandardError "E:\ajoke-g\.temp\test_err.log" `
    -PassThru -NoNewWindow
if (-not $p.WaitForExit(90000)) { $p.Kill(); "TIMEOUT_KILLED" }
else { "EXIT_CODE=$($p.ExitCode)" }
Get-Content "E:\ajoke-g\.temp\test_out.log" -Tail 30
```

### 11.3 批量回归测试

```powershell
$tests = @('bugfix_test','new_shisui_test','ui_popup_smoke_test','naruto_fy_test',
            'shisui_test','izuna_test','emiya_test','edo_hashirama_test',
            'xiye_test','ftg_intercept_test','minato_test','might_gai_fix_test',
            'might_gai_e2e_test','might_gai_test','core_logic_test','crossover_scenario_test')
$results = @()
foreach ($t in $tests) {
    $out = "E:\ajoke-g\.temp\reg_$t.log"
    $err = "E:\ajoke-g\.temp\reg_${t}_err.log"
    $p = Start-Process -FilePath "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" `
        -ArgumentList '--headless','--path','E:\ajoke-g\A-Joke',("res://tests/$t.tscn") `
        -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -NoNewWindow
    $ok = $p.WaitForExit(90000)
    if (-not $ok) { $p.Kill(); $results += "$t : TIMEOUT" }
    else { $tail = Get-Content $out -Tail 5 | Out-String; $results += "$t : EXIT=$($p.ExitCode) :: $($tail.Trim())" }
}
$results
```

### 11.4 测试编写规范

每个测试套件由两个文件组成：
- `tests/xxx_test.gd` — 测试脚本（extends Node）
- `tests/xxx_test.tscn` — 场景文件

**.tscn 模板**:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/xxx_test.gd" id="1_test"]

[node name="XxxTest" type="Node"]
script = ExtResource("1_test")
```

**测试编写关键规则**:

| 规则 | 说明 |
|---|---|
| `is_human=true` | 所有玩家设为人类，避免AI自动行动干扰 |
| `current_gesture` | **字段名是 `current_gesture`，不是 `current_round`** |
| `gm.call("_resolve_round")` | 直接调用 `_resolve_round` 跳过0.5秒延时 |
| `await get_tree().process_frame` | `setup_game` 后必须等一帧，让 `call_deferred` 执行 |
| 能量手动设置 | `_resolve_round` 后手动 `p.energy = N`，不依赖聚气 |
| 钟机制信号 | 有钟机制角色参与时，**必须连接 `end_phase_bell_decision_required` 并自动回复**，否则流程挂起 |
| 弹窗信号 | 新止水闪避/回溯/日影舞、水门拦截等弹窗需连接对应信号并提交决策 |
| `_process_end_phase` | **不要手动调用**，END_PHASE阶段会自动执行。手动调用可能触发招架弹窗导致挂起 |
| 多段伤害 | 日影舞等多段技能需逐段提交目标 |

**断言计数**：每个测试文件末尾输出 `=== xxx测试结束：PASS=NN FAIL=0 ===`，退出码 0=全过，1=有失败。

### 11.5 现有测试套件（30个，1257断言）

**核心对战测试**:

| 文件 | 角色/功能 | 断言数 |
|---|---|---|
| `bugfix_test` | 通用bug修复（钟获取+麻痹禁技） | 23 |
| `new_shisui_test` | 新止水（天劫）完整机制 | 88 |
| `ui_popup_smoke_test` | UI弹窗冒烟 | 23 |
| `naruto_fy_test` | 鸣人（疾风传） | 44 |
| `shisui_test` | 旧止水（须佐能） | 66 |
| `izuna_test` | 泉奈 | 61 |
| `emiya_test` | 卫宫 | 71 |
| `edo_hashirama_test` | 秽土柱间 | 127 |
| `xiye_test` | 希耶尔 | 76 |
| `ftg_intercept_test` | 飞雷神拦截 | 59 |
| `minato_test` | 波风水门 | 62 |
| `might_gai_fix_test` | 迈特凯修复 | 16 |
| `might_gai_e2e_test` | 迈特凯端到端 | 25 |
| `might_gai_test` | 迈特凯基础 | 49 |
| `core_logic_test` | 底层逻辑专项（状态机/手势/状态字段） | 57 |
| `crossover_scenario_test` | 多角色组合场景 | 58 |
| `herta_test` | 黑塔完整机制 | 37 |
| `big_herta_test` | 大黑塔完整机制 | 48 |

**慈悲尖塔测试**:

| 文件 | 功能 | 断言数 |
|---|---|---|
| `tower_mode_test` | 塔模式基础流程 | - |
| `tower_select_test` | 角色选择 | - |
| `tower_team_test` | 队伍编成 | - |
| `tower_gate_test` | 塔门交互 | - |
| `tower_enemy_test` | 敌人生成 | - |
| `tower_battle_test` | 塔内战斗 | - |
| `tower_battle_floor_test` | 楼层推进 | - |
| `tower_mingemon_test` | 明怪机制 | - |
| `tower_layout_check` | 布局检查 | - |
| `mingemon_test` | 明怪独立测试 | - |
| `shisui_bt_pve_test` | 新止水PvE回溯测试 | - |
| `shisui_bt_pvp_test` | 新止水PvP回溯测试 | - |
| `backtrack_test` | 回溯多场景专项（脚本待编写） | - |

### 11.6 常见测试问题排查

| 症状 | 可能原因 | 解决 |
|---|---|---|
| 测试超时（120s无响应） | 流程挂起等待信号 | 检查是否有未连接的弹窗信号（招架/闪避/回溯等） |
| `Invalid assignment of property 'current_round'` | 字段名误用 | 改为 `current_gesture` |
| `--script` 运行挂起 | autoload冲突 | 改用场景运行 `res://tests/xxx.tscn` |
| Nakama认证日志干扰 | 网络模块初始化 | 正常现象，不影响测试结果 |
| 中文乱码 | PowerShell编码 | 不影响断言判断，看 PASS/FAIL 计数即可 |

---

## 12. Git 提交规范

```powershell
cd E:\ajoke-g\A-Joke
git add <修改的文件>
git commit -m "fix/feat/test: 简要描述"
git push origin main
```

**提交信息格式**:
- `fix: 修复描述` — bug修复
- `feat: 新功能描述` — 新功能/新角色
- `test: 测试描述` — 新增测试
- 可多行，首行简短

**最近提交记录**:
```
7da8f16 test: 新增底层逻辑专项测试(56断言)+多角色组合场景测试(57断言)
51cbea5 fix: 砸钟伤害不计入钟获取+麻痹状态禁用幻影闪避
87ce096 fix: 别天神回溯跳过无反应（跳过时清空快照防循环弹窗）
5ba437e fix: 别天神回溯撤销上一回合（快照滚动至 _prev_round_pre_snapshot）
1ac9ffd fix: 修复创建房间后 Nakama storage 未生成房间实例的问题
49afc80 feat: 联机对战系统 — ENet+Nakama网络架构、服务器部署、房间列表修复
3448636 feat: HGW对战系统、角色编辑器插件、UI修复
3f4cce7 Initial commit
```

> **注意**: commit `7da8f16` 因 GitHub 网络超时未推送成功，待网络恢复后执行 `git push origin main`。

### 12.1 当前未提交变更（2026-08-20）

以下文件已修改或新增但**尚未 commit**，新对话接手时需注意：

**已修改文件**（12个）：
- `core/ai_controller.gd` — 黑塔/大黑塔AI策略
- `core/game_manager.gd` — 黑塔/大黑塔技能处理 + EffectType 32~36
- `core/player_state.gd` — 新增字段
- `core/round_resolver.gd` — 新效果结算
- `core/scene_manager.gd`
- `data/characters.gd` — LIST 追加黑塔/大黑塔
- `resources/characters/宇智波止水（天劫）.tres`
- `resources/characters/宇智波止水（须佐能）.tres`
- `resources/skill_effect.gd` — EffectType 枚举新增 32~36
- `scenes/character_select.gd` — preload 追加黑塔/大黑塔
- `scenes/main_menu.gd` / `main_menu.tscn` — 慈悲尖塔入口
- `tests/might_gai_test.gd` / `ui/game_ui.gd`

**新增文件**：
- 角色：`resources/characters/黑塔.tres`、`大黑塔.tres`
- 立绘：`portraits/黑塔.png`(+.import)、`大黑塔.png`(+.import)
- 慈悲尖塔：`resources/characters/tower/`（3个敌人角色）、`scenes/tower/`（5个场景脚本）
- 测试：`herta_test`、`big_herta_test`、`mingemon_test`、`shisui_bt_pve_test`、`shisui_bt_pvp_test`、`tower_*_test`（9个）
- 上下文：`PROJECT_CONTEXT.md`

> **建议**：下次对话首要任务 = 将以上变更分批 commit + push。

**.gitignore**: `.godot/`、`.claude/`、`.temp/`、`/android/` 被忽略。

---

## 13. 部署规范

### 13.1 部署决策

- **游戏逻辑改动**（game_manager/player_state/角色资源等）：需重新导出服务端二进制后部署，**通常暂缓**，由用户确认
- **部署前确认**: 询问用户是否需要部署

### 13.2 服务器信息

- **服务器**: 122.51.184.165（SSH端口22）
- **晨会平台路径**: /opt/morning-meeting/（这是另一个独立项目，不在本游戏项目中）
- **游戏服务器**: 独立部署（需导出 Godot 服务端二进制到 `server/` 目录）

### 13.3 Git 三端同步

```
本地 ↔ GitHub (origin/main) ↔ 服务器
```
- GitHub不通时用 SFTP 回退
- 服务器 fetch 受 packed-refs 缓存影响时用 `git reset --hard <hash>` 绕过

---

## 14. 高频易错点速查

| 易错点 | 正确做法 |
|---|---|
| 字段名 `current_round` | 正确为 `current_gesture` |
| `--script` 运行测试 | 必须用场景 `res://tests/xxx.tscn` |
| 测试卡死 | 钟机制角色需连接 `end_phase_bell_decision_required` 信号 |
| 砸钟回钟 | 4处伤害标记都加 `if skill.bell_cost <= 0` |
| 麻痹可用技能 | 麻痹状态不可使用任何技能（含被动），所有触发点加 `paralyze_turns > 0` |
| 新旧止水混淆 | 新止水按"日影舞"判断(`_is_new_shisui`)，旧止水按"须佐能乎·斩"(`_is_shisui`) |
| 角色不显示 | 3处硬编码同步：`characters.gd` LIST + `character_select.gd` _CHARACTER_PRELOADS + HGW |
| `setup_game` 后直接测试 | 需 `await get_tree().process_frame` 等 `call_deferred` 执行 |
| 手动调 `_process_end_phase` | 不要手动调用，END_PHASE会自动执行，手动调用可能触发招架弹窗挂起 |
| 回溯扣气顺序 | 扣气在快照恢复**之后**，不会被快照覆盖 |
| 回溯快照不含 delayed_damages | `delayed_damages` 仅在 pre_takeover_snapshot 中，backtrack 快照不含 |

---

## 15. 新角色开发流程

1. **创建角色资源**: `resources/characters/角色名.tres`（基于 CharacterData）
2. **创建技能资源**: 在角色 .tres 中内联或 `resources/characters/skills/` 下独立 .tres（基于 SkillData + SkillEffect）
3. **注册3处硬编码**:
   - `data/characters.gd` — LIST 数组追加
   - `scenes/character_select.gd` — `_CHARACTER_PRELOADS` 追加
   - HGW 模式（如需支持）
4. **导入立绘**: 复制到 `resources/characters/portraits/`，用 Godot `--import` 导入并回填 uid
5. **AI 策略**: 如需特殊 AI 逻辑，在 `core/ai_controller.gd` 中添加角色专用策略
6. **GameManager 适配**: 新机制需在 `game_manager.gd` 中添加处理逻辑
7. **网络适配**: 新增 SrvOp/CliOp + Host/Client 信号映射 + 状态同步
8. **专项测试**: 编写 `tests/xxx_test.gd + .tscn`
9. **全量回归**: 运行全部16个套件确认 0 FAIL
10. **Git 提交推送**: `git add → commit → push origin main`

---

## 17. 慈悲尖塔模式（Roguelike PvE）

独立于对战模式的 PvE 爬塔玩法，肉鸽循环：选队→爬层→战斗→死亡→重来。

**目录结构**:
```
scenes/tower/
├── tower_manager.gd      # 塔模式主管理器（层推进/存档/重开）
├── tower_gate.gd/.tscn   # 塔门交互（神官·梅塔特隆对话）
├── tower_select.gd/.tscn # 角色选择
└── tower_battle.gd/.tscn # 塔内战斗

resources/characters/tower/  # 塔模式专属敌人
├── 司马懿（狂）.tres
├── 漩涡鸣人（仙人模式）.tres
└── 破败王者（怒）.tres
```

**文案**：神官·梅塔特隆（原创角色，神话锚点=犹太教天书记官）开场白+死亡对话已设计，见长期记忆。

---

## 16. 关于本文件

本文件由 AI Agent（星辰超级智能体 TeleAgent）根据项目源码自动生成和维护，用于跨会话/跨 Agent 传递项目上下文。如需更新，可直接编辑本文件。

对应的技能配置文件位于：`C:\Users\占子健\.config\TeleAgent\skills\ajoke-dev\`