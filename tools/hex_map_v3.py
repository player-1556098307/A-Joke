#!/usr/bin/env python3
"""
战旗大逃杀 — 六边形地图生成器 v3.0
=====================================
核心思路重写：
  放弃"距离+阈值"裁剪大陆的方法（那会产生圆形）。
  改用两张独立噪声图叠加：
    第一张（低频）：决定大陆整体形状，值高=陆地，值低=海洋
    第二张（高频）：在边缘产生锯齿和半岛细节
  只要噪声值 > 固定阈值就是陆地，否则是外海。
  中心区域额外加权保证中心是陆地。

用法:
  python hex_map_v3.py              # 随机种子
  python hex_map_v3.py 42           # 固定种子
  python hex_map_v3.py 42 -p 4      # 4人局
  python hex_map_v3.py --png        # 输出PNG
"""

import sys, math, random, argparse, heapq
from typing import Dict, Tuple, List, Set, Optional
from dataclasses import dataclass
from enum import Enum

try:
    from colorama import init; init(); HAS_COLOR = True
except ImportError:
    HAS_COLOR = False

try:
    from PIL import Image, ImageDraw, ImageFont; HAS_PIL = True
except ImportError:
    HAS_PIL = False


# ══════════════════════════════════════════════════════════
# 参数
# ══════════════════════════════════════════════════════════

PLAYERS_TO_RADIUS = {3: 5, 4: 6, 5: 7, 6: 8}

# 大陆生成参数
LAND_THRESHOLD   = 0.42   # 噪声值 > 此值 → 陆地（调小=更多陆地）
CENTER_BONUS     = 0.35   # 中心附近额外加的权重（保证中心是陆地）
CENTER_BONUS_RADIUS = 0.4 # 中心加权影响范围（占地图半径的比例）

# 噪声频率（决定地形粗细）
SHAPE_FREQ_LOW  = 0.11   # 低频：大陆轮廓
SHAPE_FREQ_HIGH = 0.28   # 高频：海岸线锯齿

# 地形高度噪声
HEIGHT_FREQ = 0.13

# 公平性验证
MAX_RETRY = 8


# ══════════════════════════════════════════════════════════
# 噪声
# ══════════════════════════════════════════════════════════

def _hash(x: int, y: int, seed: int) -> float:
    n = (x * 1619 + y * 31337 + seed * 65537) & 0x7FFFFFFF
    n = ((n ^ 61) ^ (n >> 16)) & 0x7FFFFFFF
    n = (n + (n << 3)) & 0x7FFFFFFF
    n = (n ^ (n >> 4)) & 0x7FFFFFFF
    n = (n * 0x27d4eb2d) & 0x7FFFFFFF
    n = (n ^ (n >> 15)) & 0x7FFFFFFF
    return n / 0x7FFFFFFF

def _smooth(t): return t * t * (3 - 2 * t)

def _vnoise(x: float, y: float, seed: int) -> float:
    x0, y0 = int(math.floor(x)), int(math.floor(y))
    sx, sy = _smooth(x - x0), _smooth(y - y0)
    n00 = _hash(x0,   y0,   seed)
    n10 = _hash(x0+1, y0,   seed)
    n01 = _hash(x0,   y0+1, seed)
    n11 = _hash(x0+1, y0+1, seed)
    return (n00+(n10-n00)*sx) + ((n01+(n11-n01)*sx)-(n00+(n10-n00)*sx))*sy

def noise(x, y, seed, octaves=4, lac=2.0, gain=0.5):
    v, amp, freq, mx = 0.0, 1.0, 1.0, 0.0
    for i in range(octaves):
        v  += _vnoise(x*freq, y*freq, seed+i*1000) * amp
        mx += amp; amp *= gain; freq *= lac
    return v / mx


# ══════════════════════════════════════════════════════════
# 六边形网格
# ══════════════════════════════════════════════════════════

class Terrain(Enum):
    VOID=0; DEEP_WATER=1; SHALLOW_WATER=2; PLAIN=3
    FOREST=4; HIGHLAND=5; MOUNTAIN=6; FORTRESS=7; GRAIL=8

@dataclass
class Cell:
    q: int; r: int
    land_val: float = 0.0   # 大陆噪声值（决定是否是陆地）
    height: float = 0.0     # 地形高度值（决定地形类型）
    terrain: Terrain = Terrain.PLAIN
    is_void: bool = False
    is_grail: bool = False
    is_city: bool = False
    is_key: bool = False
    is_resource: bool = False
    is_reward: bool = False
    is_choke: bool = False
    res_tier: str = ""

def hd(q1,r1,q2,r2): return (abs(q1-q2)+abs(q1+r1-q2-r2)+abs(r1-r2))//2
def neighbors(q,r): return [(q+1,r),(q+1,r-1),(q,r-1),(q-1,r),(q-1,r+1),(q,r+1)]

def make_grid(radius):
    g = {}
    for q in range(-radius, radius+1):
        for r in range(max(-radius,-q-radius), min(radius,-q+radius)+1):
            g[(q,r)] = Cell(q=q, r=r)
    return g


# ══════════════════════════════════════════════════════════
# 大陆形状生成（核心新逻辑）
# ══════════════════════════════════════════════════════════

def generate_land_shape(cells, radius, seed):
    """
    每个格子的land_val由三部分叠加：
      1. 低频噪声（大轮廓）× 0.6
      2. 高频噪声（锯齿细节）× 0.4
      3. 中心加权：距中心越近，额外+CENTER_BONUS

    land_val > LAND_THRESHOLD → 陆地
    land_val ≤ LAND_THRESHOLD → 外海

    这样大陆形状完全由噪声决定，不依赖任何圆形距离判断，
    所以轮廓可以是任意不规则形状。
    """
    seed_lo = seed
    seed_hi = seed + 11111

    for pos, cell in cells.items():
        q, r = pos

        # 低频噪声：决定大陆整体走向
        lo = noise(q * SHAPE_FREQ_LOW,  r * SHAPE_FREQ_LOW,  seed_lo, octaves=3)
        # 高频噪声：在边界产生锯齿、半岛、海湾
        hi = noise(q * SHAPE_FREQ_HIGH, r * SHAPE_FREQ_HIGH, seed_hi, octaves=2)

        # 两层叠加
        val = lo * 0.6 + hi * 0.4

        # 中心加权：让中心区域更倾向于是陆地
        # 用平滑衰减函数，不是硬截断，避免产生圆形边界
        dist_norm = hd(q, r, 0, 0) / radius
        center_weight = CENTER_BONUS * max(0, 1 - dist_norm / CENTER_BONUS_RADIUS) ** 2
        val += center_weight

        cell.land_val = val

    # 以中心格子的val为基准，确保中心一定是陆地
    center_val = cells[(0,0)].land_val
    # 如果中心val不够高，整体上移
    if center_val < LAND_THRESHOLD + 0.1:
        shift = LAND_THRESHOLD + 0.1 - center_val
        for cell in cells.values():
            cell.land_val += shift

    # 标记外海
    for pos, cell in cells.items():
        if cell.land_val <= LAND_THRESHOLD:
            cell.terrain = Terrain.VOID
            cell.is_void = True

    # 去掉孤立的单格陆地（四面都是外海的陆地格）
    for pos, cell in list(cells.items()):
        if cell.is_void:
            continue
        land_nbs = [nb for nb in neighbors(*pos)
                    if nb in cells and not cells[nb].is_void]
        if len(land_nbs) == 0:
            cell.terrain = Terrain.VOID
            cell.is_void = True


# ══════════════════════════════════════════════════════════
# 地形成型
# ══════════════════════════════════════════════════════════

TERRAIN_TARGETS = [
    (Terrain.DEEP_WATER,   0.10),
    (Terrain.SHALLOW_WATER,0.08),
    (Terrain.PLAIN,        0.27),
    (Terrain.FOREST,       0.16),
    (Terrain.HIGHLAND,     0.15),
    (Terrain.MOUNTAIN,     0.12),
    (Terrain.FORTRESS,     0.12),
]

def assign_terrain(cells, seed):
    """用独立的高度噪声决定地形类型，与大陆形状噪声完全独立"""
    land = [c for c in cells.values() if not c.is_void]
    if not land:
        return

    # 采样高度噪声
    for cell in land:
        cell.height = noise(cell.q * HEIGHT_FREQ, cell.r * HEIGHT_FREQ,
                            seed + 55555, octaves=4)

    # 平滑两次（让地形聚团）
    for _ in range(2):
        new_h = {}
        for pos, cell in cells.items():
            if cell.is_void: continue
            nbs = [cells[nb].height for nb in neighbors(*pos)
                   if nb in cells and not cells[nb].is_void]
            new_h[pos] = cell.height*0.6 + (sum(nbs)/len(nbs))*0.4 if nbs else cell.height
        for pos, h in new_h.items():
            cells[pos].height = h

    # 分位数阈值动态分配
    heights = sorted(c.height for c in land)
    n = len(heights)
    thresholds, cum = [], 0.0
    for terrain, pct in TERRAIN_TARGETS:
        cum += pct
        thresholds.append((terrain, heights[min(int(cum*n), n-1)]))

    for cell in land:
        for terrain, thresh in thresholds:
            if cell.height <= thresh:
                cell.terrain = terrain; break
        else:
            cell.terrain = Terrain.FORTRESS

    # 孤立小水域填为平原
    water = {pos for pos,c in cells.items()
             if c.terrain in (Terrain.DEEP_WATER, Terrain.SHALLOW_WATER)}
    visited = set()
    for pos in list(water):
        if pos in visited: continue
        cluster, stack = [], [pos]
        visited.add(pos)
        while stack:
            cur = stack.pop(); cluster.append(cur)
            for nb in neighbors(*cur):
                if nb in water and nb not in visited:
                    visited.add(nb); stack.append(nb)
        if len(cluster) <= 2:
            for p in cluster: cells[p].terrain = Terrain.PLAIN


# ══════════════════════════════════════════════════════════
# 连通性修复
# ══════════════════════════════════════════════════════════

def fix_connectivity(cells, radius):
    def passable(pos):
        if pos not in cells: return False
        return cells[pos].terrain not in (
            Terrain.VOID, Terrain.DEEP_WATER, Terrain.SHALLOW_WATER, Terrain.MOUNTAIN)

    center = (0,0)
    ps = {p for p in cells if passable(p)}
    edges = {p for p in ps if hd(*p,0,0) >= radius-1}
    if not edges: return False

    # BFS检查连通
    visited = set(edges); queue = list(edges)
    while queue:
        cur = queue.pop(0)
        if cur == center: return True  # 已连通
        for nb in neighbors(*cur):
            if nb in ps and nb not in visited:
                visited.add(nb); queue.append(nb)

    # Dijkstra挖通
    dist, prev = {}, {}
    heap = [(0,e) for e in edges]
    for e in edges: dist[e] = 0
    heapq.heapify(heap)
    while heap:
        cost, pos = heapq.heappop(heap)
        if cost > dist.get(pos, 1e9): continue
        if pos == center: break
        for nb in neighbors(*pos):
            if nb not in cells: continue
            t = cells[nb].terrain
            mc = 0 if passable(nb) else (2 if t in (Terrain.DEEP_WATER,Terrain.SHALLOW_WATER) else 3)
            nc = cost + mc
            if nc < dist.get(nb, 1e9):
                dist[nb]=nc; prev[nb]=pos; heapq.heappush(heap,(nc,nb))

    cur = center
    while cur in prev:
        c = cells[cur]
        if c.terrain in (Terrain.DEEP_WATER,Terrain.SHALLOW_WATER,Terrain.MOUNTAIN):
            c.terrain = Terrain.PLAIN
        cur = prev[cur]
    return False


# ══════════════════════════════════════════════════════════
# 出生点
# ══════════════════════════════════════════════════════════

def place_spawns(cells, radius, num_players, rng):
    def passable(pos):
        return not cells[pos].is_void and cells[pos].terrain not in (
            Terrain.MOUNTAIN, Terrain.DEEP_WATER, Terrain.SHALLOW_WATER)

    candidates = [pos for pos in cells if passable(pos)
                  and hd(*pos,0,0) >= max(2, radius-2)]

    # 按角度分扇区
    sectors = [[] for _ in range(num_players)]
    for pos in candidates:
        q, r = pos
        angle = math.atan2(r, q)
        if angle < 0: angle += 2*math.pi
        sectors[int(angle/(2*math.pi)*num_players)%num_players].append(pos)

    def score(pos):
        q, r = pos
        nbs = neighbors(q,r)
        pass_nb = sum(1 for nb in nbs if nb in cells and passable(nb))
        res_nb  = sum(1 for nb in [p for p in cells if 1<=hd(*p,q,r)<=2]
                      if cells[nb].terrain in (Terrain.FOREST,Terrain.HIGHLAND))
        ideal = radius * 0.75
        d = hd(q,r,0,0)
        return (pass_nb/6)*0.4 + min(res_nb/4,1)*0.3 + max(0,1-abs(d-ideal)/ideal)*0.3

    spawns = []
    for slot in sectors:
        if slot:
            best = max(slot, key=score)
            cells[best].is_city = True
            spawns.append(best)
    return spawns


# ══════════════════════════════════════════════════════════
# 资源放置
# ══════════════════════════════════════════════════════════

def place_resources(cells, radius, num_players, spawns, rng):
    def passable(pos):
        return not cells[pos].is_void and cells[pos].terrain not in (
            Terrain.MOUNTAIN,Terrain.DEEP_WATER,Terrain.SHALLOW_WATER)

    all_pass = [p for p in cells if passable(p)
                and not cells[p].is_grail and not cells[p].is_city]

    # 按角度分扇区（外圈保底资源）
    sectors = [[] for _ in range(num_players)]
    for pos in all_pass:
        q,r = pos
        angle = math.atan2(r,q)
        if angle < 0: angle += 2*math.pi
        sectors[int(angle/(2*math.pi)*num_players)%num_players].append(pos)

    for sector in sectors:
        outer = [p for p in sector if hd(*p,0,0) > radius*0.4
                 and not cells[p].is_resource]
        rng.shuffle(outer)
        for pos in outer[:3]:
            cells[pos].is_resource = True; cells[pos].res_tier = "common"

    # 中圈稀有
    mid = [p for p in all_pass if not cells[p].is_resource
           and radius*0.3 <= hd(*p,0,0) <= radius*0.65]
    rng.shuffle(mid)
    for pos in mid[:num_players]:
        cells[pos].is_resource = True; cells[pos].res_tier = "rare"

    # 内圈核心
    inner = [p for p in all_pass if not cells[p].is_resource
             and hd(*p,0,0) <= radius*0.3]
    rng.shuffle(inner)
    for pos in inner[:num_players]:
        cells[pos].is_resource = True; cells[pos].res_tier = "core"

    # 奖励池
    reward = [p for p in cells if cells[p].terrain in (Terrain.FOREST,Terrain.HIGHLAND)
              and not cells[p].is_resource and not cells[p].is_city]
    rng.shuffle(reward)
    for pos in reward[:rng.randint(2,3)]:
        cells[pos].is_reward = True

    # 钥匙点
    keys = [p for p in all_pass if not cells[p].is_resource
            and not cells[p].is_city and hd(*p,0,0)>=2]
    rng.shuffle(keys)
    for pos in keys[:3]:
        cells[pos].is_key = True


# ══════════════════════════════════════════════════════════
# 战略要道
# ══════════════════════════════════════════════════════════

def find_chokepoints(cells, spawns):
    def cost(t):
        if t in (Terrain.VOID,Terrain.DEEP_WATER,Terrain.SHALLOW_WATER): return 999
        return {Terrain.MOUNTAIN:5,Terrain.FOREST:2,Terrain.HIGHLAND:3}.get(t,1)

    usage = {}
    for spawn in spawns:
        dist,prev = {spawn:0},{}
        heap = [(0,spawn)]
        while heap:
            d,pos = heapq.heappop(heap)
            if pos==(0,0): break
            if d>dist.get(pos,1e9): continue
            for nb in neighbors(*pos):
                if nb not in cells: continue
                nd = d+cost(cells[nb].terrain)
                if nd<dist.get(nb,1e9):
                    dist[nb]=nd; prev[nb]=pos; heapq.heappush(heap,(nd,nb))
        cur=(0,0)
        while cur in prev:
            usage[cur]=usage.get(cur,0)+1; cur=prev[cur]

    for pos,u in usage.items():
        if u>=2 and pos in cells:
            cells[pos].is_choke=True


# ══════════════════════════════════════════════════════════
# 公平性验证
# ══════════════════════════════════════════════════════════

def validate(cells, spawns, num_players):
    if len(spawns) < num_players:
        return False, ["spawn_count<num_players"]
    issues = []

    dists = [hd(*a,*b) for i,a in enumerate(spawns) for b in spawns[i+1:]]
    if dists and max(dists)-min(dists) > 3:
        issues.append(f"spawn_dist_var={max(dists)-min(dists)}")

    local = [sum(1 for p,c in cells.items()
                 if c.is_resource and hd(*p,*sp)<=3) for sp in spawns]
    if local and max(local)-min(local) > 2:
        issues.append(f"resource_imbalance={local}")

    return len(issues)==0, issues


# ══════════════════════════════════════════════════════════
# 主生成器
# ══════════════════════════════════════════════════════════

class MapGenerator:
    def __init__(self, radius, seed, num_players=3):
        self.radius = radius
        self.seed = seed
        self.num_players = num_players
        self.rng = random.Random(seed)
        self.cells = {}
        self.spawns = []
        self.stats = {}

    def generate(self):
        for attempt in range(MAX_RETRY):
            s = self.seed + attempt * 13337
            # 用比 radius 大2格的网格生成，给海岸线留空间
            R = self.radius + 2
            self.cells = make_grid(R)

            generate_land_shape(self.cells, self.radius, s)
            assign_terrain(self.cells, s)
            fix_connectivity(self.cells, self.radius)

            # 圣杯台座
            if (0,0) in self.cells:
                self.cells[(0,0)].is_grail = True
                self.cells[(0,0)].terrain = Terrain.GRAIL

            self.spawns = place_spawns(self.cells, self.radius,
                                       self.num_players, self.rng)
            place_resources(self.cells, self.radius,
                            self.num_players, self.spawns, self.rng)
            find_chokepoints(self.cells, self.spawns)

            ok, issues = validate(self.cells, self.spawns, self.num_players)
            self.stats = {
                "seed": s, "attempt": attempt+1,
                "radius": self.radius,
                "land": sum(1 for c in self.cells.values() if not c.is_void),
                "void": sum(1 for c in self.cells.values() if c.is_void),
                "fair": ok, "issues": issues,
                "spawns": self.spawns,
            }
            if ok:
                break

        return self.cells

    def stats_text(self):
        s = self.stats
        lines = [
            f"Seed={s['seed']}  R={s['radius']}  Players={self.num_players}"
            f"  Attempt={s['attempt']}",
            f"Land={s['land']}  Void={s['void']}",
            f"Spawns={s['spawns']}",
            f"Fairness={'PASS' if s['fair'] else 'FAIL'}",
        ]
        for iss in s.get("issues",[]):
            lines.append(f"  ! {iss}")

        counts = {}
        for c in self.cells.values():
            if not c.is_void:
                counts[c.terrain.name] = counts.get(c.terrain.name,0)+1
        total = sum(counts.values()) or 1
        lines.append("\nTerrain:")
        for t,n in sorted(counts.items()):
            lines.append(f"  {t:<16} {n:3d}  {n/total*100:5.1f}%")
        return "\n".join(lines)


# ══════════════════════════════════════════════════════════
# 渲染
# ══════════════════════════════════════════════════════════

PNG_COLORS = {
    Terrain.VOID:         (12, 20, 50),
    Terrain.DEEP_WATER:   (30, 60, 140),
    Terrain.SHALLOW_WATER:(74,156,199),
    Terrain.PLAIN:        (181,204,142),
    Terrain.FOREST:       (53,104, 45),
    Terrain.HIGHLAND:     (196,176,112),
    Terrain.MOUNTAIN:     (139,124,106),
    Terrain.FORTRESS:     (169,124,186),
    Terrain.GRAIL:        (255,215,117),
}

CMAP = {
    "B":"\033[38;5;27m","C":"\033[38;5;51m","G":"\033[38;5;40m",
    "DG":"\033[38;5;22m","Y":"\033[38;5;178m","R":"\033[38;5;196m",
    "M":"\033[38;5;201m","W":"\033[38;5;255m","X":"\033[0m",
}

def cell_char(c):
    if c.is_void: return " "
    if c.is_grail: return "O"
    if c.is_city:  return "@"
    if c.is_key:   return "K"
    if c.is_reward:return "$"
    if c.is_resource:
        return {"common":"*","rare":"+","core":"!"}.get(c.res_tier,"*")
    if c.is_choke: return "="
    return {Terrain.DEEP_WATER:"~",Terrain.SHALLOW_WATER:"w",Terrain.PLAIN:".",
            Terrain.FOREST:"T",Terrain.HIGHLAND:"^",Terrain.MOUNTAIN:"#",
            Terrain.FORTRESS:"F",Terrain.GRAIL:"O"}.get(c.terrain,"?")

def cell_color(c):
    if c.is_grail or c.is_key or c.is_reward: return CMAP["Y"]
    if c.is_city:     return CMAP["M"]
    if c.is_resource: return CMAP["C"]
    if c.is_choke:    return CMAP["R"]
    return {Terrain.DEEP_WATER:CMAP["B"],Terrain.SHALLOW_WATER:CMAP["C"],
            Terrain.PLAIN:CMAP["G"],Terrain.FOREST:CMAP["DG"],
            Terrain.HIGHLAND:CMAP["Y"],Terrain.MOUNTAIN:CMAP["R"],
            Terrain.FORTRESS:CMAP["M"],Terrain.GRAIL:CMAP["Y"]}.get(c.terrain,CMAP["X"])

def render_ascii(cells):
    rows = {}
    for (q,r),c in cells.items():
        rows.setdefault(r,[]).append((q,c))
    active = {r:items for r,items in rows.items()
              if any(not c.is_void for _,c in items)}
    if not active: return "(empty)"
    has_color = HAS_COLOR and sys.stdout.isatty()
    lines = []
    for r in range(min(active),max(active)+1):
        items = active.get(r,[])
        nv = [(q,c) for q,c in items if not c.is_void]
        if not nv: continue
        mq,xq = min(q for q,_ in nv), max(q for q,_ in nv)
        row = sorted([(q,c) for q,c in items if mq-1<=q<=xq+1],key=lambda x:x[0])
        line = "  " if r%2!=0 else ""
        for q,c in row:
            ch = cell_char(c)
            if has_color and not c.is_void:
                line += f"{cell_color(c)}{ch}{CMAP['X']} "
            else:
                line += f"{ch} "
        lines.append(line.rstrip())
    return "\n".join(lines)

def render_png(cells, radius, filepath="hex_map.png"):
    if not HAS_PIL:
        print("pip install pillow"); return
    R = radius + 2
    hs = 30
    W = int(2*hs*(math.sqrt(3)*R+math.sqrt(3)))+80
    H = int(2*hs*(1.5*R+1))+80
    img = Image.new("RGB",(W,H),(8,12,35))
    draw = ImageDraw.Draw(img)
    try: font = ImageFont.truetype("consola.ttf",9)
    except: font = ImageFont.load_default()

    for (q,r),c in cells.items():
        cx = int(W/2 + hs*(math.sqrt(3)*q + math.sqrt(3)/2*r))
        cy = int(H/2 + hs*1.5*r)
        verts = [(cx+hs*math.cos(math.pi/180*(60*i-30)),
                  cy+hs*math.sin(math.pi/180*(60*i-30))) for i in range(6)]
        col = PNG_COLORS.get(c.terrain,(100,100,100))
        outline = None if c.is_void else (50,50,50)
        draw.polygon(verts, fill=col, outline=outline)

        if c.is_grail:
            draw.ellipse([cx-9,cy-9,cx+9,cy+9],fill=(255,215,0))
        if c.is_city:
            draw.rectangle([cx-7,cy-7,cx+7,cy+7],fill=(220,60,60))
        if c.is_choke:
            draw.ellipse([cx-4,cy-4,cx+4,cy+4],fill=(255,120,40))
        if c.is_key:
            draw.polygon([(cx,cy-8),(cx+7,cy+5),(cx-7,cy+5)],fill=(255,220,0))
        if c.is_resource:
            col2 = {"common":(80,180,255),"rare":(180,80,255),"core":(255,80,80)}.get(c.res_tier,(200,200,200))
            draw.ellipse([cx-4,cy-4,cx+4,cy+4],fill=col2)

    img.save(filepath)
    print(f"PNG saved: {filepath}")


# ══════════════════════════════════════════════════════════
# 入口
# ══════════════════════════════════════════════════════════

def main():
    p = argparse.ArgumentParser()
    p.add_argument("seed",nargs="?",type=int,default=0)
    p.add_argument("--players","-p",type=int,default=3,choices=[3,4,5,6])
    p.add_argument("--radius","-r",type=int,default=None)
    p.add_argument("--png",action="store_true")
    p.add_argument("--output","-o",default="hex_map.png")
    args = p.parse_args()

    seed = args.seed if args.seed!=0 else random.randint(1,99999)
    radius = args.radius or PLAYERS_TO_RADIUS.get(args.players,5)

    gen = MapGenerator(radius=radius,seed=seed,num_players=args.players)
    cells = gen.generate()

    print("="*50)
    print("  战旗大逃杀 — Hex Map Generator v3.0")
    print("="*50)
    print(render_ascii(cells))
    print("""
Legend: O=圣杯  @=出生点  K=钥匙  *=普通资源  +=稀有  !=核心
        $=奖励池  ==要道  ~=深水  w=浅水  .=平原
        T=森林  ^=高地  #=山脉  F=要塞""")
    print()
    print(gen.stats_text())

    if args.png:
        render_png(cells, radius, args.output)

if __name__=="__main__":
    main()
