// Nakama 服务端模块 — 匹配器 + 房间列表
// Fixed: updateTime is a number (seconds since epoch), convert to ms for correct TTL

function InitModule(ctx, logger, nk, initializer) {
  initializer.registerMatchmakerMatched(matchmakerMatched);
  initializer.registerRpc("list_rooms", rpcListRooms);
}

var matchmakerMatched = function(ctx, logger, nk, matches) {
  var env = nk.environmentsGet();
  var gameServerAddr = env["GAME_SERVER_ADDR"] || "127.0.0.1:7777";
  var matchId = nk.matchCreate("lobby_match", { gameServerAddr: gameServerAddr });
  return matchId;
};

var ROOM_STALE_MS = 600000; // 10 分钟无心跳视为死房间

var rpcListRooms = function(ctx, logger, nk, _payload) {
  var result = nk.storageList(null, "rooms", 100);
  var now = Date.now();
  var live = [];
  var stale = [];

  result.objects.forEach(function(obj) {
    var updateTimeMs = obj.updateTime ? obj.updateTime * 1000 : 0;
    if ((now - updateTimeMs) < ROOM_STALE_MS) {
      var val = obj.value;
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
