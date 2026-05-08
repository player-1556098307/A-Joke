// Nakama 服务端模块 — 匹配器规则
// 编译：npx tsc --outDir . index.ts  → 生成 index.js

function InitModule(ctx: nkruntime.Context, logger: nkruntime.Logger,
                   nk: nkruntime.Nakama, initializer: nkruntime.Initializer): void {

  initializer.registerMatchmakerMatched(matchmakerMatched);
  initializer.registerRpc("list_rooms", rpcListRooms);
}

// 列出所有用户的房间（服务端上下文可跨用户查询 storage）
const rpcListRooms: nkruntime.RpcFunction =
  (ctx, logger, nk, _payload) => {
    const result = nk.storageList(null as unknown as string, "rooms", 100);
    const now = Date.now();
    const TWO_HOURS = 7200000;
    const rooms = result.objects
      .filter(obj => {
        const updateTime = obj.updateTime
          ? new Date(obj.updateTime).getTime()
          : 0;
        return (now - updateTime) < TWO_HOURS;
      })
      .map(obj => {
        const val: Record<string, unknown> = obj.value as unknown as Record<string, unknown>;
        val["room_code"] = obj.key;
        val["host_user_id"] = obj.userId;
        return val;
      });
    return JSON.stringify(rooms);
  };

// 匹配完成后：创建一个关联的 Nakama match，把游戏服务器地址写入 match metadata
const matchmakerMatched: nkruntime.MatchmakerMatchedFunction =
  (ctx, logger, nk, matches) => {
    // 从环境变量读取游戏服务器地址
    const gameServerAddr = nk.environmentsGet()["GAME_SERVER_ADDR"] ?? "127.0.0.1:7777";
    const matchId = nk.matchCreate("lobby_match", { gameServerAddr });
    return matchId;
  };
