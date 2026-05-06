# 联机模式扩展实现指南

> **阅读须知**  
> 本文档覆盖从 0 到可上线的全部步骤，按章节顺序完成即可得到完整联机功能。  
> 每章末尾有"完成验证"小节，确认通过后再进入下一章。

---

## 架构总览

```
┌──────────────────────────────────────────────────────┐
│  大厅层：Nakama Server（Docker）                      │
│  职责：账号认证 / 房间列表 / 组队 / 匹配队列 / 通知  │
└────────────────────┬─────────────────────────────────┘
                     │  匹配完成后下发游戏服务器地址
┌────────────────────▼─────────────────────────────────┐
│  游戏层：Godot 无头服务器（ENet UDP 7777）            │
│  职责：权威游戏逻辑 / 状态同步 / 断线托管 / 延迟监控 │
│  运行现有 GameManager / RoundResolver（零改动）       │
└──────────────────────────────────────────────────────┘
```

**数据流向**

```
[客户端] ──HTTPS──▶ Nakama（认证/大厅/匹配）
[客户端] ◀──WS──── Nakama（推送：匹配结果/房间更新）
[客户端] ──UDP───▶ Godot游戏服务器（游戏输入）
[客户端] ◀──UDP─── Godot游戏服务器（状态广播/AI事件）
```

---

## 新增文件清单

```
core/
  net/
    NetworkManager.gd       ← Autoload，管理Nakama会话 + ENet连接
    NetworkProtocol.gd      ← OpCode枚举 + 消息序列化工具
    NetworkGameHost.gd      ← 服务器端：包装GameManager，输入转RPC
    NetworkGameClient.gd    ← 客户端：接收RPC，重建本地状态
    RoomManager.gd          ← 服务器端：多房间管理
    LatencyMonitor.gd       ← Ping/Pong + 高延迟警告
scenes/
  net/
    lobby.gd / lobby.tscn   ← 大厅场景（房间列表/创建/匹配）
    char_select_net.gd      ← 联机版武将选择
server/
  server_main.gd            ← 无头服务器入口（export时使用）
```

`GameManager.gd`、`PlayerState.gd`、`RoundResolver.gd`、`AIController.gd`——**均不改动原有逻辑**，只在 `PlayerState` 追加两个字段、在 `GameManager._check_elimination()` 追加团队判断。

---

## 第一章：Nakama 服务器搭建

### 1.1 本地开发环境（Docker Compose）

新建文件 `tools/nakama/docker-compose.yml`：

```yaml
version: "3"
services:
  postgres:
    image: postgres:14-alpine
    environment:
      POSTGRES_DB: nakama
      POSTGRES_PASSWORD: localdb
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  nakama:
    image: heroiclabs/nakama:3.21.1
    depends_on:
      - postgres
    ports:
      - "7350:7350"   # HTTP API
      - "7351:7351"   # gRPC
      - "7352:7352"   # Console Web UI
    environment:
      - NAKAMA_RUNTIME_JS_ENTRYPOINT=/nakama/data/modules/index.js
    volumes:
      - ./modules:/nakama/data/modules
    command: >
      --config /nakama/data/config.yml
      --database.address postgres:5432/nakama?password=localdb&user=postgres

volumes:
  pgdata:
```

启动：

```bash
cd tools/nakama
docker compose up -d
# 管理控制台：http://localhost:7352  admin/password
```

### 1.2 Nakama 服务端模块（TypeScript/JS）

Nakama 使用服务端模块处理匹配逻辑。创建 `tools/nakama/modules/index.ts`（安装 `nakama-runtime` 类型后编译为 JS）：

```typescript
// 房间元数据校验 + 匹配器规则
function InitModule(ctx: nkruntime.Context, logger: nkruntime.Logger,
                   nk: nkruntime.Nakama, initializer: nkruntime.Initializer): void {

  // 匹配器：按模式和段位匹配
  initializer.registerMatchmakerMatched(matchmakerMatched);
}

// 匹配完成后：创建一个关联的 Nakama match，把游戏服务器地址写入 match metadata
const matchmakerMatched: nkruntime.MatchmakerMatchedFunction =
  (ctx, logger, nk, matches) => {
    // 从环境变量读取游戏服务器地址
    const gameServerAddr = nk.environmentsGet()["GAME_SERVER_ADDR"] ?? "127.0.0.1:7777";
    const matchId = nk.matchCreate("lobby_match", { gameServerAddr });
    return matchId;
  };
```

> 简化版：生产环境可用 Nakama 官方 TypeScript 模板，此处只需匹配逻辑。  
> 若不想写 TypeScript，可跳过此文件，使用 Nakama HTTP API 手动创建 match。

---

## 第二章：Nakama Godot SDK 安装

### 2.1 下载 SDK

访问 https://github.com/heroiclabs/nakama-godot/releases 下载最新 `nakama-godot-*.zip`，解压后将 `addons/nakama/` 复制到项目根目录 `addons/nakama/`。

### 2.2 启用插件

Godot 编辑器 → `项目 → 项目设置 → 插件 → Nakama → 启用`。

### 2.3 project.godot 追加自动加载

在 `project.godot` 的 `[autoload]` 段追加：

```ini
NetworkManager="*res://core/net/NetworkManager.gd"
```

（追加在现有 `GameManager`、`SceneManager`、`SettingsManager` 之后）

---

## 第三章：NetworkProtocol（消息协议）

新建 `core/net/NetworkProtocol.gd`：

```gdscript
class_name NetworkProtocol
extends RefCounted

# ── 服务器 → 客户端 OpCode ────────────────────────────────────
enum SrvOp {
    PHASE_ENTER          = 10,  # 进入新阶段，附带阶段数据
    GESTURES_REVEALED    = 11,  # 所有手势揭示（RESOLVING阶段）
    ACTION_RESULT        = 12,  # 技能/充能结果
    FULL_STATE_SYNC      = 13,  # 完整状态快照（断线重连用）
    PLAYER_DISCONNECTED  = 21,  # 某玩家断线，AI接管
    PLAYER_RECONNECTED   = 22,  # 某玩家重连
    HIGH_LATENCY         = 23,  # 某玩家高延迟警告
    PONG                 = 30,  # 响应Ping
    GAME_OVER_RESULT     = 40,
}

# ── 客户端 → 服务器 OpCode ────────────────────────────────────
enum CliOp {
    SUBMIT_GESTURE  = 1,   # {gesture: int}
    SUBMIT_ACTION   = 2,   # {action: int, skill_index: int, target_id: int}
    RECONNECT_REQ   = 3,   # {room_id: String, token: String}
    PING            = 10,  # {ts: float}
    SPECTATE_JOIN   = 20,  # {}
}

# 序列化：Dictionary → PackedByteArray（JSON）
static func encode(op: int, payload: Dictionary) -> PackedByteArray:
    var msg := {"op": op, "d": payload}
    return JSON.stringify(msg).to_utf8_buffer()

# 反序列化：PackedByteArray → {op, payload}
static func decode(data: PackedByteArray) -> Dictionary:
    var text := data.get_string_from_utf8()
    var parsed = JSON.parse_string(text)
    if parsed == null:
        return {}
    return {"op": int(parsed["op"]), "d": parsed.get("d", {})}

# 将 PlayerState 序列化为可网络传输的 Dictionary
static func serialize_player_state(p: PlayerState) -> Dictionary:
    return {
        "id":             p.player_id,
        "name":           p.player_name,
        "team":           p.team_id,
        "hp":             p.hp,
        "energy":         p.energy,
        "shield":         p.shield,
        "paralyze":       p.paralyze_turns,
        "clone":          p.clone_count,
        "alive":          p.is_alive,
        "char_id":        p.character.resource_path,
        "delayed_dmg":    p.delayed_damages,
    }
```

---

## 第四章：NetworkManager（Autoload）

新建 `core/net/NetworkManager.gd`：

```gdscript
## NetworkManager — 管理 Nakama 会话和 ENet 游戏连接
extends Node

# ── 配置（开发/生产分离）─────────────────────────────────────
const NAKAMA_HOST    := "127.0.0.1"
const NAKAMA_PORT    := 7350
const NAKAMA_KEY     := "defaultkey"           # 与 Nakama 服务器配置一致
const GAME_SERVER_IP := "127.0.0.1"
const GAME_SERVER_PORT := 7777

# ── 信号 ──────────────────────────────────────────────────────
signal authenticated(user_id: String, username: String)
signal auth_failed(error: String)
signal match_found(match_info: Dictionary)          # Nakama 匹配完成
signal connected_to_game_server()
signal disconnected_from_game_server()
signal game_message_received(op: int, data: Dictionary)

# ── Nakama 大厅层 ──────────────────────────────────────────────
var _client: NakamaClient
var _session: NakamaSession
var _socket: NakamaSocket

# ── ENet 游戏层 ────────────────────────────────────────────────
var _enet_peer: ENetMultiplayerPeer
var is_connected_to_game := false
var my_game_peer_id: int = 0

# ── 本地状态 ───────────────────────────────────────────────────
var reconnect_token: String = ""
var current_room_id: String = ""

func _ready() -> void:
    _client = Nakama.create_client(NAKAMA_KEY, NAKAMA_HOST, NAKAMA_PORT, "http")
    _try_restore_session()

# ─────────────────────────────────────────────────────────────
# 认证
# ─────────────────────────────────────────────────────────────

func _try_restore_session() -> void:
    var token := _load_pref("session_token", "")
    var refresh_token := _load_pref("refresh_token", "")
    if token == "" or refresh_token == "":
        return
    _session = NakamaClient.restore_session(token, refresh_token)
    if _session.is_expired():
        var result := await _client.session_refresh_async(_session)
        if result.is_exception():
            return
        _session = result
        _save_session()

## 设备匿名登录（首次启动）
func login_device() -> void:
    var device_id := OS.get_unique_id()
    var result := await _client.authenticate_device_async(device_id, null, true)
    if result.is_exception():
        auth_failed.emit(result.get_exception().message)
        return
    _session = result
    _save_session()
    authenticated.emit(_session.user_id, _session.username)

## 邮箱注册/登录（可选，用于跨设备账号）
func login_email(email: String, password: String, create: bool) -> void:
    var result := await _client.authenticate_email_async(email, password, null, create)
    if result.is_exception():
        auth_failed.emit(result.get_exception().message)
        return
    _session = result
    _save_session()
    authenticated.emit(_session.user_id, _session.username)

func _save_session() -> void:
    _save_pref("session_token", _session.token)
    _save_pref("refresh_token", _session.refresh_token)

func is_authenticated() -> bool:
    return _session != null and not _session.is_expired()

# ─────────────────────────────────────────────────────────────
# Nakama 实时 Socket（大厅通知）
# ─────────────────────────────────────────────────────────────

func connect_socket() -> void:
    if _socket != null:
        return
    _socket = Nakama.create_web_socket()
    _socket.received_notification.connect(_on_nakama_notification)
    _socket.received_match_state.connect(_on_nakama_match_state)
    await _socket.connect_async(_session)

func _on_nakama_notification(event) -> void:
    pass  # 扩展：处理好友邀请、系统消息等

func _on_nakama_match_state(event: NakamaRTAPI.MatchData) -> void:
    # Nakama relay 传来的消息（武将选择阶段用）
    var op := event.op_code
    var data: Dictionary = JSON.parse_string(event.data) if event.data else {}
    game_message_received.emit(op, data)

# ─────────────────────────────────────────────────────────────
# ENet 游戏连接
# ─────────────────────────────────────────────────────────────

func connect_to_game_server(ip: String, port: int, token: String) -> void:
    reconnect_token = token
    _enet_peer = ENetMultiplayerPeer.new()
    var err := _enet_peer.create_client(ip, port)
    if err != OK:
        return
    get_tree().get_multiplayer().multiplayer_peer = _enet_peer
    get_tree().get_multiplayer().connected_to_server.connect(_on_game_connected)
    get_tree().get_multiplayer().server_disconnected.connect(_on_game_disconnected)

func _on_game_connected() -> void:
    my_game_peer_id = get_tree().get_multiplayer().get_unique_id()
    is_connected_to_game = true
    connected_to_game_server.emit()

func _on_game_disconnected() -> void:
    is_connected_to_game = false
    disconnected_from_game_server.emit()
    _attempt_reconnect()

func _attempt_reconnect() -> void:
    if reconnect_token == "" or current_room_id == "":
        return
    await get_tree().create_timer(3.0).timeout
    connect_to_game_server(GAME_SERVER_IP, GAME_SERVER_PORT, reconnect_token)

# ─────────────────────────────────────────────────────────────
# 匹配队列
# ─────────────────────────────────────────────────────────────

## mode: "ffa_2" / "ffa_4" / "team_2v2" / "team_3v3"
func join_matchmaker(mode: String) -> void:
    if _socket == null:
        await connect_socket()
    var min_count := 2
    var max_count := 2
    match mode:
        "ffa_4":   min_count = 4; max_count = 4
        "team_2v2": min_count = 4; max_count = 4
        "team_3v3": min_count = 6; max_count = 6
    var ticket = await _socket.add_matchmaker_async("*", min_count, max_count,
        {"mode": mode})
    if ticket.is_exception():
        push_error("Matchmaker error: " + ticket.get_exception().message)
        return
    # matched 事件通过 received_matchmaker_matched 信号到达
    _socket.received_matchmaker_matched.connect(_on_matched, CONNECT_ONE_SHOT)

func _on_matched(event: NakamaRTAPI.MatchmakerMatched) -> void:
    # event.match 包含服务器在 match metadata 里写入的游戏服务器地址
    var match_id := event.match_id
    # 加入 Nakama relay match（武将选择阶段通信用）
    var match_obj = await _socket.join_match_async(match_id)
    current_room_id = match_id
    # 读取游戏服务器地址（由 Nakama 模块写入 match label）
    var game_addr: String = match_obj.label if match_obj.label else "%s:%d" % [GAME_SERVER_IP, GAME_SERVER_PORT]
    var parts := game_addr.split(":")
    var ip := parts[0]
    var port := int(parts[1]) if parts.size() > 1 else GAME_SERVER_PORT
    match_found.emit({"match_id": match_id, "ip": ip, "port": port,
                      "users": event.users})

# ─────────────────────────────────────────────────────────────
# 房间（私人/密码房）
# ─────────────────────────────────────────────────────────────

## 创建带密码的私人房间（写入 Nakama storage）
func create_private_room(config: Dictionary) -> String:
    # config: {name, password, mode, max_spectators}
    var write_obj := NakamaWriteStorageObject.new()
    write_obj.collection = "rooms"
    write_obj.key = _generate_room_code()
    write_obj.value = JSON.stringify(config)
    write_obj.permission_read = 2   # 公开可读
    write_obj.permission_write = 1  # 只有创建者可写
    var result = await _client.write_storage_objects_async(_session, [write_obj])
    if result.is_exception():
        return ""
    current_room_id = write_obj.key
    return write_obj.key

## 列出公开房间
func list_rooms() -> Array:
    var result = await _client.list_storage_objects_async(_session, "rooms", "", 20)
    if result.is_exception():
        return []
    var rooms := []
    for obj in result.objects:
        rooms.append(JSON.parse_string(obj.value))
    return rooms

func _generate_room_code() -> String:
    const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    var code := ""
    for i in 6:
        code += CHARS[randi() % CHARS.length()]
    return code

# ─────────────────────────────────────────────────────────────
# 本地存储工具
# ─────────────────────────────────────────────────────────────

func _save_pref(key: String, value: String) -> void:
    var cfg := ConfigFile.new()
    cfg.load("user://network.cfg")
    cfg.set_value("auth", key, value)
    cfg.save("user://network.cfg")

func _load_pref(key: String, default: String) -> String:
    var cfg := ConfigFile.new()
    if cfg.load("user://network.cfg") != OK:
        return default
    return cfg.get_value("auth", key, default)
```

**完成验证**：运行游戏，调用 `NetworkManager.login_device()`，Nakama 控制台（localhost:7352）能看到新用户注册。

---

## 第五章：武将选择同步

武将选择在游戏服务器启动前完成，通过 **Nakama relay socket** 广播（不需要 ENet）。

新建 `scenes/net/char_select_net.gd`：

```gdscript
extends Node

## 当前 match 中所有玩家的武将选择
## key = nakama user_id, value = char_resource_path
var selections: Dictionary = {}
var locked: Dictionary = {}   # user_id → true 表示已锁定
var my_user_id: String = ""
var match_id: String = ""

const OP_SELECT  := 100  # 选择武将（未锁定）
const OP_LOCK    := 101  # 锁定武将
const OP_ALL_LOCKED := 102  # 全员锁定，准备开始

func _ready() -> void:
    my_user_id = NetworkManager._session.user_id
    match_id = NetworkManager.current_room_id
    NetworkManager.game_message_received.connect(_on_message)

func select_character(char_path: String) -> void:
    selections[my_user_id] = char_path
    _send(OP_SELECT, {"char": char_path})

func lock_character() -> void:
    if not selections.has(my_user_id):
        return
    locked[my_user_id] = true
    _send(OP_LOCK, {"char": selections[my_user_id]})
    _check_all_locked()

func _on_message(op: int, data: Dictionary) -> void:
    var uid: String = data.get("uid", "")
    match op:
        OP_SELECT:
            selections[uid] = data.get("char", "")
            # 更新 UI：显示对方选的武将
        OP_LOCK:
            selections[uid] = data.get("char", "")
            locked[uid] = true
            _check_all_locked()

func _check_all_locked() -> void:
    # 所有已加入玩家都锁定后，房主广播 ALL_LOCKED
    # 此处简化：判断 locked 数量 == match 人数
    pass

func _send(op: int, payload: Dictionary) -> void:
    payload["uid"] = my_user_id
    NetworkManager._socket.send_match_state_async(match_id, op,
        JSON.stringify(payload))
```

**2v2 同角色规则**：不做任何去重校验，`selections` 允许重复 char_path。

---

## 第六章：Godot 游戏服务器

### 6.1 PlayerState 追加团队字段

在 `core/player_state.gd` 末尾追加（不改动其他任何行）：

```gdscript
## 团队 ID：0 = FFA（无队伍），1/2 = 团队编号
var team_id: int = 0
## 是否当前由 AI 托管（断线替补）
var is_ai_controlled: bool = false
```

### 6.2 GameManager 团队胜负判定

打开 `core/game_manager.gd`，找到 `_check_elimination()` 方法，将胜利判断部分改为：

```gdscript
# 原代码（第442行附近）：
#   if alive.size() <= 1 or _is_human_dead():
#       _enter_phase(GamePhase.GAME_OVER)
# 替换为：

var alive := get_alive_players()
if alive.size() <= 1:
    _enter_phase(GamePhase.GAME_OVER)
    return
# 团队模式：所有存活者属于同一队则该队获胜
if alive.any(func(p): return p.team_id != 0):
    var first_team: int = alive[0].team_id
    if alive.all(func(p): return p.team_id == first_team):
        _enter_phase(GamePhase.GAME_OVER)
        return
# 保留原有"人类死亡则结束"逻辑（单机模式用）
if _is_human_dead() and not _is_network_game:
    _enter_phase(GamePhase.GAME_OVER)
    return
_enter_phase(GamePhase.ROUND_END)
```

在 `game_manager.gd` 顶部变量区追加：

```gdscript
## 联机模式标志（服务器设置为 true，关闭单机"人类死亡即结束"逻辑）
var _is_network_game: bool = false
```

### 6.3 RoomManager（服务器端）

新建 `core/net/RoomManager.gd`：

```gdscript
## RoomManager — 仅在服务器进程中运行，管理所有游戏房间
class_name RoomManager
extends Node

## key = room_id(String), value = NetworkGameHost 节点
var _rooms: Dictionary = {}
## key = peer_id(int), value = room_id(String)
var _peer_to_room: Dictionary = {}
## key = token(String), value = {room_id, player_id, peer_id}
var _reconnect_tokens: Dictionary = {}

func _ready() -> void:
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func create_room(room_id: String, config: Dictionary) -> void:
    var host := preload("res://core/net/NetworkGameHost.gd").new()
    host.name = "Room_" + room_id
    host.room_id = room_id
    host.room_config = config
    add_child(host)
    _rooms[room_id] = host

func assign_peer_to_room(peer_id: int, room_id: String, token: String) -> void:
    _peer_to_room[peer_id] = room_id
    if _rooms.has(room_id):
        _rooms[room_id].on_player_join(peer_id, token)

func _on_peer_connected(peer_id: int) -> void:
    pass  # 等待客户端发送 RECONNECT_REQ 或 JOIN_ROOM 消息

func _on_peer_disconnected(peer_id: int) -> void:
    var room_id: String = _peer_to_room.get(peer_id, "")
    if room_id == "" or not _rooms.has(room_id):
        return
    _rooms[room_id].on_player_disconnect(peer_id)

func get_room(room_id: String) -> Node:
    return _rooms.get(room_id)
```

### 6.4 NetworkGameHost（房间权威逻辑）

新建 `core/net/NetworkGameHost.gd`：

```gdscript
## NetworkGameHost — 服务器端，包装 GameManager，将信号转为 RPC 广播
class_name NetworkGameHost
extends Node

var room_id: String = ""
var room_config: Dictionary = {}

## key = peer_id, value = player_id
var _peer_to_player: Dictionary = {}
## key = player_id, value = peer_id（-1表示断线中）
var _player_to_peer: Dictionary = {}
## key = token, value = player_id（断线重连用）
var _tokens: Dictionary = {}

var _game_manager: GameManager
var _spectator_peers: Array[int] = []

const RECONNECT_TIMEOUT := 60.0  # 断线后保留槽位的秒数

func _ready() -> void:
    _game_manager = GameManager.new()
    _game_manager._is_network_game = true
    add_child(_game_manager)
    _connect_signals()

func _connect_signals() -> void:
    _game_manager.phase_changed.connect(_on_phase_changed)
    _game_manager.gesture_submitted.connect(_on_gesture_submitted)
    _game_manager.round_resolved.connect(_on_round_resolved)
    _game_manager.action_required.connect(_on_action_required)
    _game_manager.skill_applied.connect(_on_skill_applied)
    _game_manager.player_charged.connect(_on_player_charged)
    _game_manager.player_eliminated.connect(_on_player_eliminated)
    _game_manager.game_over.connect(_on_game_over)
    _game_manager.player_paralyzed.connect(_on_player_paralyzed)
    _game_manager.player_shielded.connect(_on_player_shielded)
    _game_manager.clone_destroyed.connect(_on_clone_destroyed)
    _game_manager.skill_unlocked.connect(_on_skill_unlocked)
    _game_manager.delayed_damage_triggered.connect(_on_delayed_damage)
    _game_manager.distance_changed.connect(_on_distance_changed)
    _game_manager.tiebreak_started.connect(_on_tiebreak_started)
    _game_manager.tiebreak_resolved.connect(_on_tiebreak_resolved)

# ─────────────────────────────────────────────────────────────
# 玩家加入/断线
# ─────────────────────────────────────────────────────────────

func on_player_join(peer_id: int, token: String) -> void:
    # 尝试断线重连
    if _tokens.has(token):
        var player_id: int = _tokens[token]
        _player_to_peer[player_id] = peer_id
        _peer_to_player[peer_id] = player_id
        # 恢复人类控制
        var player := _game_manager.get_player(player_id)
        if player:
            player.is_ai_controlled = false
            player.is_human = true
        _send_full_sync(peer_id)
        _broadcast(NetworkProtocol.SrvOp.PLAYER_RECONNECTED,
            {"player_id": player_id}, _spectator_peers)
        return
    # 新玩家
    var player_id := _peer_to_player.size()  # 简单递增ID
    _peer_to_player[peer_id] = player_id
    _player_to_peer[player_id] = peer_id
    var new_token := _make_token(peer_id)
    _tokens[new_token] = player_id
    # 返回给客户端
    rpc_id(peer_id, "receive_join_ack",
        {"player_id": player_id, "token": new_token, "room_id": room_id})
    _maybe_start_game()

func on_player_disconnect(peer_id: int) -> void:
    if not _peer_to_player.has(peer_id):
        return
    var player_id: int = _peer_to_player[peer_id]
    _player_to_peer[player_id] = -1
    # 切换为 AI 托管
    var player := _game_manager.get_player(player_id)
    if player and player.is_alive:
        player.is_human = false
        player.is_ai_controlled = true
    _broadcast(NetworkProtocol.SrvOp.PLAYER_DISCONNECTED,
        {"player_id": player_id}, [])
    # 60秒后若未重连，保持AI（不删除槽位）

func _maybe_start_game() -> void:
    var expected: int = room_config.get("max_players", 2)
    if _peer_to_player.size() >= expected:
        _start_game()

func _start_game() -> void:
    _game_manager.setup_game(room_config)

# ─────────────────────────────────────────────────────────────
# 接收客户端输入（RPC any_peer）
# ─────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func client_submit_gesture(gesture: int) -> void:
    var peer_id := multiplayer.get_remote_sender_id()
    var player_id: int = _peer_to_player.get(peer_id, -1)
    if player_id < 0:
        return
    _game_manager.submit_gesture(player_id, gesture as PlayerState.Gesture)

@rpc("any_peer", "reliable")
func client_submit_action(action: int, skill_index: int, target_id: int) -> void:
    var peer_id := multiplayer.get_remote_sender_id()
    var player_id: int = _peer_to_player.get(peer_id, -1)
    if player_id < 0:
        return
    _game_manager.submit_action(player_id,
        action as PlayerState.ActionType, skill_index, target_id)

@rpc("any_peer", "unreliable")
func client_ping(ts: float) -> void:
    var peer_id := multiplayer.get_remote_sender_id()
    rpc_id(peer_id, "server_pong", ts)

# ─────────────────────────────────────────────────────────────
# GameManager 信号 → RPC 广播
# ─────────────────────────────────────────────────────────────

func _on_phase_changed(phase: GameManager.GamePhase) -> void:
    _broadcast(NetworkProtocol.SrvOp.PHASE_ENTER, {"phase": phase}, _spectator_peers)

func _on_round_resolved(result: Dictionary) -> void:
    # RESOLVING 阶段才揭示手势
    var gestures: Dictionary = {}
    for p in _game_manager._players:
        if p.is_alive:
            gestures[p.player_id] = p.current_gesture
    _broadcast(NetworkProtocol.SrvOp.GESTURES_REVEALED,
        {"gestures": gestures, "result": result}, _spectator_peers)

func _on_action_required(player_id: int) -> void:
    # 仅通知胜者
    var peer_id: int = _player_to_peer.get(player_id, -1)
    if peer_id > 0:
        rpc_id(peer_id, "server_broadcast",
            NetworkProtocol.SrvOp.PHASE_ENTER,
            {"phase": GameManager.GamePhase.ACTION_INPUT, "winner_id": player_id})

func _on_skill_applied(logs: Array[Dictionary]) -> void:
    _broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
        {"type": "skill", "logs": logs}, _spectator_peers)

func _on_player_charged(player_id: int, new_energy: int) -> void:
    _broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
        {"type": "charge", "player_id": player_id, "energy": new_energy},
        _spectator_peers)

func _on_player_eliminated(player_id: int) -> void:
    _broadcast(NetworkProtocol.SrvOp.PHASE_ENTER,
        {"phase": GameManager.GamePhase.ELIMINATION, "player_id": player_id},
        _spectator_peers)

func _on_game_over(winner_id: int, _record) -> void:
    _broadcast(NetworkProtocol.SrvOp.GAME_OVER_RESULT,
        {"winner_id": winner_id}, _spectator_peers)

func _on_player_paralyzed(player_id: int, turns: int) -> void:
    _broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
        {"type": "paralyze", "player_id": player_id, "turns": turns},
        _spectator_peers)

func _on_player_shielded(player_id: int, shield_value: int) -> void:
    _broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
        {"type": "shield", "player_id": player_id, "value": shield_value},
        _spectator_peers)

func _on_clone_destroyed(player_id: int) -> void:
    _broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
        {"type": "clone_destroyed", "player_id": player_id}, _spectator_peers)

func _on_skill_unlocked(player_id: int, skill_name: String) -> void:
    _broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
        {"type": "skill_unlocked", "player_id": player_id, "skill": skill_name},
        _spectator_peers)

func _on_delayed_damage(player_id: int, damage: int, remaining_hp: int) -> void:
    _broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
        {"type": "delayed_damage", "player_id": player_id,
         "damage": damage, "hp": remaining_hp}, _spectator_peers)

func _on_distance_changed(from_id: int, to_id: int, new_distance: int) -> void:
    _broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
        {"type": "distance", "from": from_id, "to": to_id, "dist": new_distance},
        _spectator_peers)

func _on_tiebreak_started(candidates: Array[int]) -> void:
    _broadcast(NetworkProtocol.SrvOp.PHASE_ENTER,
        {"phase": GameManager.GamePhase.TIEBREAK_INPUT, "candidates": candidates},
        _spectator_peers)

func _on_tiebreak_resolved(winner_id: int) -> void:
    _broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
        {"type": "tiebreak_winner", "player_id": winner_id}, _spectator_peers)

# ─────────────────────────────────────────────────────────────
# 广播工具
# ─────────────────────────────────────────────────────────────

## 向所有玩家（及可选的观战者）广播
func _broadcast(op: int, data: Dictionary, extra_peers: Array[int]) -> void:
    for player_id in _player_to_peer:
        var peer_id: int = _player_to_peer[player_id]
        if peer_id > 0:
            rpc_id(peer_id, "server_broadcast", op, data)
    for peer_id in extra_peers:
        rpc_id(peer_id, "server_broadcast", op, data)

## 向单个 peer 发送当前完整状态（用于重连）
func _send_full_sync(peer_id: int) -> void:
    var state := []
    for p in _game_manager._players:
        state.append(NetworkProtocol.serialize_player_state(p))
    rpc_id(peer_id, "server_broadcast",
        NetworkProtocol.SrvOp.FULL_STATE_SYNC,
        {"players": state, "phase": _game_manager._current_phase,
         "round": _game_manager._current_round_number})

func _make_token(peer_id: int) -> String:
    return "%d_%d_%s" % [peer_id, Time.get_ticks_msec(), randf()]
```

---

## 第七章：NetworkGameClient（客户端适配层）

新建 `core/net/NetworkGameClient.gd`：

```gdscript
## NetworkGameClient — 客户端，接收服务器 RPC，映射到本地 UI 信号
class_name NetworkGameClient
extends Node

## 透传给 UI 层的信号（与 GameManager 信号名一致，方便 UI 兼容）
signal phase_changed(phase: int)
signal gestures_revealed(gestures: Dictionary, result: Dictionary)
signal action_result(data: Dictionary)
signal full_state_received(state: Array, phase: int, round: int)
signal player_disconnected_notice(player_id: int)
signal player_reconnected_notice(player_id: int)
signal high_latency_notice(player_id: int, ms: int)
signal game_over_received(winner_id: int)

var my_player_id: int = -1
var reconnect_token: String = ""
var room_id: String = ""

## 服务器调用此 RPC 将消息推送到客户端
@rpc("authority", "reliable")
func server_broadcast(op: int, data: Dictionary) -> void:
    match op:
        NetworkProtocol.SrvOp.PHASE_ENTER:
            phase_changed.emit(data.get("phase", 0))
        NetworkProtocol.SrvOp.GESTURES_REVEALED:
            gestures_revealed.emit(data.get("gestures", {}), data.get("result", {}))
        NetworkProtocol.SrvOp.ACTION_RESULT:
            action_result.emit(data)
        NetworkProtocol.SrvOp.FULL_STATE_SYNC:
            full_state_received.emit(
                data.get("players", []),
                data.get("phase", 0),
                data.get("round", 0))
        NetworkProtocol.SrvOp.PLAYER_DISCONNECTED:
            player_disconnected_notice.emit(data.get("player_id", -1))
        NetworkProtocol.SrvOp.PLAYER_RECONNECTED:
            player_reconnected_notice.emit(data.get("player_id", -1))
        NetworkProtocol.SrvOp.HIGH_LATENCY:
            high_latency_notice.emit(data.get("player_id", -1), data.get("ms", 0))
        NetworkProtocol.SrvOp.GAME_OVER_RESULT:
            game_over_received.emit(data.get("winner_id", -1))

## 服务器调用：确认加入成功，返回 token 和 player_id
@rpc("authority", "reliable")
func receive_join_ack(info: Dictionary) -> void:
    my_player_id = info.get("player_id", -1)
    reconnect_token = info.get("token", "")
    room_id = info.get("room_id", "")
    # 持久化 token（用于断线重连）
    NetworkManager._save_pref("reconnect_token", reconnect_token)
    NetworkManager._save_pref("reconnect_room", room_id)

## 服务器调用：响应 Ping
@rpc("authority", "unreliable")
func server_pong(client_ts: float) -> void:
    var rtt := (Time.get_unix_time_from_system() - client_ts) * 1000.0
    LatencyMonitor.update_latency(rtt)

# ─────────────────────────────────────────────────────────────
# 客户端发送输入
# ─────────────────────────────────────────────────────────────

func submit_gesture(gesture: PlayerState.Gesture) -> void:
    rpc_id(1, "client_submit_gesture", gesture)  # 1 = server peer_id

func submit_action(action: PlayerState.ActionType, skill_index: int, target_id: int) -> void:
    rpc_id(1, "client_submit_action", action, skill_index, target_id)

func send_ping() -> void:
    rpc_id(1, "client_ping", Time.get_unix_time_from_system())
```

---

## 第八章：延迟监控

新建 `core/net/LatencyMonitor.gd`（Autoload，追加到 project.godot）：

```gdscript
extends Node

signal latency_updated(ms: float)
signal high_latency_warning(ms: float)   ## > 200ms
signal disconnection_risk(ms: float)     ## > 5000ms

const PING_INTERVAL   := 3.0
const WARN_THRESHOLD  := 200.0
const DISCO_THRESHOLD := 5000.0

var current_latency_ms: float = 0.0
var _ping_timer: float = 0.0
var _client: NetworkGameClient

func _process(delta: float) -> void:
    if _client == null or not NetworkManager.is_connected_to_game:
        return
    _ping_timer += delta
    if _ping_timer >= PING_INTERVAL:
        _ping_timer = 0.0
        _client.send_ping()

func update_latency(rtt_ms: float) -> void:
    current_latency_ms = rtt_ms
    latency_updated.emit(rtt_ms)
    if rtt_ms > DISCO_THRESHOLD:
        disconnection_risk.emit(rtt_ms)
    elif rtt_ms > WARN_THRESHOLD:
        high_latency_warning.emit(rtt_ms)

func set_client(client: NetworkGameClient) -> void:
    _client = client
```

**服务器端延迟广播**：在 `NetworkGameHost` 的 `client_ping` 处理后，将延迟广播给所有人（可选，让所有人看到谁延迟高）：

```gdscript
@rpc("any_peer", "unreliable")
func client_ping(ts: float) -> void:
    var peer_id := multiplayer.get_remote_sender_id()
    rpc_id(peer_id, "server_pong", ts)
    # 计算并广播延迟警告（服务器侧 RTT 估算）
    var rtt_ms := (Time.get_unix_time_from_system() - ts) * 1000.0
    if rtt_ms > 200.0:
        var player_id: int = _peer_to_player.get(peer_id, -1)
        if player_id >= 0:
            _broadcast(NetworkProtocol.SrvOp.HIGH_LATENCY,
                {"player_id": player_id, "ms": rtt_ms}, _spectator_peers)
```

---

## 第九章：观战系统

### 9.1 加入观战

在 `NetworkGameHost` 追加：

```gdscript
@rpc("any_peer", "reliable")
func client_request_spectate() -> void:
    var peer_id := multiplayer.get_remote_sender_id()
    if _spectator_peers.size() >= room_config.get("max_spectators", 0):
        rpc_id(peer_id, "server_broadcast", 99, {"error": "spectator_full"})
        return
    _spectator_peers.append(peer_id)
    _send_full_sync(peer_id)  # 立即同步当前完整状态
```

### 9.2 观战数据过滤

观战者收到所有广播，但 **不收到** `action_required`（行动选择通知仅发给当事玩家）。手势在 `RESOLVING` 阶段之前不揭示——`_on_round_resolved` 的广播在调用时已经是揭示时机，无需额外延迟。

---

## 第十章：服务器入口

新建 `server/server_main.gd`：

```gdscript
## 无头服务器入口 — 仅在 --headless 模式下使用
extends Node

const PORT := 7777
const MAX_CLIENTS := 64

var _room_manager: RoomManager

func _ready() -> void:
    if not OS.has_feature("dedicated_server") and not DisplayServer.get_name() == "headless":
        return  # 非服务器模式不执行
    print("[Server] 启动，监听端口 %d" % PORT)
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_server(PORT, MAX_CLIENTS)
    if err != OK:
        push_error("[Server] 端口绑定失败: %d" % err)
        get_tree().quit()
        return
    get_tree().get_multiplayer().multiplayer_peer = peer
    _room_manager = RoomManager.new()
    add_child(_room_manager)
    print("[Server] 就绪，等待连接...")
```

将 `server_main.gd` 对应的场景设置为 `--headless` 启动时的主场景（在项目导出配置中指定）。

---

## 第十一章：客户端游戏场景接入

### 11.1 联机版主场景初始化

修改 `scenes/main.gd`，在现有 `_ready()` 前检测是否为联机模式：

```gdscript
var _net_client: NetworkGameClient

func _ready() -> void:
    # 判断是联机还是单机
    if SceneManager.last_game_config.get("is_network", false):
        _init_network_mode()
    else:
        _init_local_mode()

func _init_network_mode() -> void:
    _net_client = NetworkGameClient.new()
    add_child(_net_client)
    LatencyMonitor.set_client(_net_client)
    # 连接 NetworkGameClient 的信号到 UI（与单机 GameManager 信号同名）
    _net_client.phase_changed.connect($GameUI._on_phase_changed)
    _net_client.gestures_revealed.connect($GameUI._on_gestures_revealed)
    _net_client.action_result.connect($GameUI._on_action_result)
    _net_client.full_state_received.connect($GameUI._on_full_state_sync)
    _net_client.game_over_received.connect($GameUI._on_game_over)
    # UI 操作改为通过 NetworkGameClient 发送
    $GameUI.gesture_chosen.connect(_net_client.submit_gesture)
    $GameUI.action_chosen.connect(func(a, s, t): _net_client.submit_action(a, s, t))
    # 告知服务器本客户端的身份（token 在连接时已持久化）
    var token := NetworkManager._load_pref("reconnect_token", "")
    rpc_id(1, "on_player_join",
        multiplayer.get_unique_id(), token)

func _init_local_mode() -> void:
    # 原有单机初始化逻辑，保持不变
    var config: Dictionary = SceneManager.last_game_config
    GameManager.setup_game(config)
```

---

## 第十二章：UI 延迟指示器

在 `ui/game_ui.gd` 的 `_ready()` 中：

```gdscript
func _ready() -> void:
    # ... 原有连接 ...
    LatencyMonitor.latency_updated.connect(_on_latency_update)
    LatencyMonitor.high_latency_warning.connect(_on_high_latency)

func _on_latency_update(ms: float) -> void:
    $PingLabel.text = "%d ms" % int(ms)
    $PingLabel.modulate = Color.GREEN if ms < 100 else \
                          Color.YELLOW if ms < 200 else Color.RED

func _on_high_latency(ms: float) -> void:
    $LatencyWarning.text = "网络延迟较高 (%d ms)" % int(ms)
    $LatencyWarning.visible = true
    get_tree().create_timer(3.0).timeout.connect(
        func(): $LatencyWarning.visible = false)
```

---

## 第十三章：服务器部署

### 13.1 导出 Godot 无头服务器

1. **项目 → 导出 → 添加** `Linux/X11`
2. 勾选 `Export With Debug = OFF`
3. 自定义特性标签填写：`dedicated_server`
4. 主场景改为 `server/server_main.tscn`
5. 导出文件名：`game_server`

本地测试：

```bash
./game_server --headless
```

### 13.2 Hetzner VPS 初始化

```bash
# 以 Ubuntu 22.04 为例
apt update && apt install -y docker.io docker-compose-plugin

# 上传文件
scp game_server root@YOUR_VPS:/opt/gameserver/
scp -r tools/nakama root@YOUR_VPS:/opt/nakama/

chmod +x /opt/gameserver/game_server
```

### 13.3 Nakama 生产 docker-compose

修改 `tools/nakama/docker-compose.yml` 中环境变量：

```yaml
environment:
  - NAKAMA_RUNTIME_JS_ENTRYPOINT=/nakama/data/modules/index.js
  - GAME_SERVER_ADDR=127.0.0.1:7777
```

### 13.4 Systemd 服务配置

创建 `/etc/systemd/system/game-server.service`：

```ini
[Unit]
Description=Joke Game Server
After=network.target docker.service

[Service]
Type=simple
WorkingDirectory=/opt/gameserver
ExecStart=/opt/gameserver/game_server --headless
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable game-server
systemctl start game-server

# Nakama
cd /opt/nakama && docker compose up -d
```

### 13.5 防火墙规则

```bash
ufw allow 7350/tcp   # Nakama HTTP
ufw allow 7351/tcp   # Nakama gRPC（可选）
ufw allow 7777/udp   # ENet 游戏服务器
ufw enable
```

### 13.6 客户端配置切换

在 `NetworkManager.gd` 顶部修改为生产地址：

```gdscript
const NAKAMA_HOST    := "YOUR_VPS_IP"
const GAME_SERVER_IP := "YOUR_VPS_IP"
```

或从 `user://config.cfg` 读取，方便热切换开发/生产环境。

---

## 实施优先级建议

| 优先级 | 章节 | 预估工时 |
|--------|------|----------|
| P0（核心）| 第1、2、3章：Nakama搭建 + SDK + NetworkManager | 1天 |
| P0 | 第6章：PlayerState/GameManager改造 | 半天 |
| P0 | 第7章：NetworkGameHost（服务器逻辑） | 2天 |
| P0 | 第7章：NetworkGameClient + 第11章：场景接入 | 1天 |
| P1（重要）| 第5章：武将选择同步 | 1天 |
| P1 | 第4章：NetworkManager 匹配队列 | 1天 |
| P1 | 第10章：断线重连 + AI托管 | 1天 |
| P2（完善）| 第8章：延迟监控 UI | 半天 |
| P2 | 第9章：观战系统 | 半天 |
| P3（上线）| 第13章：服务器部署 | 1天 |

**总计约 10 个工作日可完成 MVP 联机版本。**
