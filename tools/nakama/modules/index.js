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

var rpcListRooms = function(ctx, logger, nk, _payload) {
  var result = nk.storageList(null, "rooms", 100);
  var now = Date.now();
  var TWO_HOURS = 7200000;
  var rooms = result.objects
    .filter(function(obj) {
      var updateTimeMs = obj.updateTime ? obj.updateTime * 1000 : 0;
      return (now - updateTimeMs) < TWO_HOURS;
    })
    .map(function(obj) {
      var val = obj.value;
      val["room_code"] = obj.key;
      val["host_user_id"] = obj.userId;
      return val;
    });
  return JSON.stringify(rooms);
};
