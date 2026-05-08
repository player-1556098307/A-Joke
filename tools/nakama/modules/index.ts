// Nakama 服务端模块 — 匹配器 + 房间列表
// 编译：npx tsc --outDir . index.ts  → 生成 index.js
// Fixed: updateTime is a Unix epoch seconds number, multiply by 1000 for ms comparison

function InitModule(ctx: nkruntime.Context, logger: nkruntime.Logger,
                   nk: nkruntime.Nakama, initializer: nkruntime.Initializer): void {

  initializer.registerMatchmakerMatched(matchmakerMatched);
  initializer.registerRpc("list_rooms", rpcListRooms);
}

var ROOM_STALE_MS = 600000; // 10 分钟无心跳视为死房间

// 列出所有用户的房间（服务端上下文可跨用户查询 storage）
const rpcListRooms: nkruntime.RpcFunction =
  (ctx, logger, nk, _payload) => {
    const result = nk.storageList(null as unknown as string, "rooms", 100);
    const now = Date.now();
    const live: Record<string, unknown>[] = [];
    const stale: { collection: string; key: string; userId: string }[] = [];

    result.objects.forEach(obj => {
      const updateTimeMs: number = obj.updateTime
        ? (obj.updateTime as unknown as number) * 1000
        : 0;
      if ((now - updateTimeMs) < ROOM_STALE_MS) {
        const val: Record<string, unknown> = obj.value as unknown as Record<string, unknown>;
        val["room_code"] = obj.key;
        val["host_user_id"] = obj.userId;
        live.push(val);
      } else {
        stale.push({ collection: "rooms", key: obj.key, userId: obj.userId });
      }
    });

    if (stale.length > 0) {
      try {
        nk.storageDelete(stale);
        logger.info("Cleaned up %d stale rooms", stale.length);
      } catch (e) {
        logger.error("Failed to clean stale rooms: %s", e);
      }
    }

    return JSON.stringify(live);
  };

// 匹配完成后：创建一个关联的 Nakama match，把游戏服务器地址写入 match metadata
const matchmakerMatched: nkruntime.MatchmakerMatchedFunction =
  (ctx, logger, nk, matches) => {
    // 从环境变量读取游戏服务器地址
    const gameServerAddr = nk.environmentsGet()["GAME_SERVER_ADDR"] ?? "127.0.0.1:7777";
    const matchId = nk.matchCreate("lobby_match", { gameServerAddr });
    return matchId;
  };
