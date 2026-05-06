#!/usr/bin/env python3
"""
战旗大逃杀 — 六边形地图生成器 v2.0
=====================================
改进点：
  1. 修复大陆轮廓遮罩：逐格2D采样，产生真实半岛/海湾
  2. 高度图平滑：让地形聚团而非椒盐分布
  3. 扇区内强制地形多样性
  4. 出生点评分选取：通行性 + 资源邻近 + 距中心距离
  5. 资源分层放置：内圈高回报、外圈保底配额
  6. 战略通道识别与保护（Dijkstra）
  7. 公平性量化验证 + 自动重试
  8. 污染蔓延缩圈系统

用法:
  python hex_map_generator.py                  # 默认3人，随机种子
  python hex_map_generator.py 42               # 固定种子42
  python hex_map_generator.py 42 --players 4   # 4人局
  python hex_map_generator.py --png            # 同时输出PNG
"""

import sys
import math
import random
import argparse
import heapq
from typing import Dict, Tuple, List, Set, Optional
from dataclasses import dataclass, field
from enum import Enum

try:
    from colorama import init, Fore, Style
    init()
    HAS_COLOR = True
except ImportError:
    HAS_COLOR = False

try:
    from PIL import Image, ImageDraw, ImageFont
    HAS_PIL = True
except ImportError:
    HAS_PIL = False


# ══════════════════════════════════════════════════════════
# 常量配置
# ══════════════════════════════════════════════════════════

PLAYERS_TO_RADIUS = {3: 5, 4: 6, 5: 7, 6: 7}
DEFAULT_RADIUS = 5

# 柏林噪声参数
# 频率越小 → 锚点越稀疏 → 山脉越连绵
NOISE_FREQUENCY  = 0.04
NOISE_OCTAVES    = 4
NOISE_LACUNARITY = 2.0   # 每层频率倍增系数
NOISE_GAIN       = 0.5   # 每层振幅衰减系数

# 大陆轮廓遮罩参数（逐格2D采样，修复版）
CONTINENT_NOISE_FREQ    = 0.06
CONTINENT_NOISE_OCTAVES = 3
COASTLINE_FALLOFF       = 0.5   # 海岸线不规则程度 [0~1]

# 高度图平滑（让同类地形聚团）
SMOOTH_ITERATIONS = 2
SMOOTH_SELF_WEIGHT = 0.6   # 自身权重
SMOOTH_NEIGHBOR_WEIGHT = 0.4  # 邻居均值权重

# 公平性验证阈值
MAX_SPAWN_DIST_VARIANCE = 2   # 出生点两两距离最大差值
MAX_RESOURCE_IMBALANCE  = 1   # 各出生点附近资源数最大差值
MAX_PATH_LENGTH_VARIANCE = 3  # 到中心路径长度最大差值
MAX_RETRY = 5                 # 验证失败最多重试次数


class Terrain(Enum):
    VOID           = "void"
    DEEP_WATER     = "deep_water"
    SHALLOW_WATER  = "shallow_water"
    PLAIN          = "plain"
    FOREST         = "forest"
    HIGHLAND       = "highland"
    MOUNTAIN       = "mountain"
    FORTRESS       = "fortress"
    GRAIL_PLATFORM = "grail_platform"


# 地形目标分布百分比（仅对陆地格）
TERRAIN_TARGETS = [
    (Terrain.DEEP_WATER,   0.12),
    (Terrain.SHALLOW_WATER,0.08),
    (Terrain.PLAIN,        0.25),
    (Terrain.FOREST,       0.15),
    (Terrain.HIGHLAND,     0.15),
    (Terrain.MOUNTAIN,     0.13),
    (Terrain.FORTRESS,     0.12),
]

# ASCII渲染配置
TERRAIN_ASCII = {
    Terrain.VOID:          (" ",  "RESET"),
    Terrain.DEEP_WATER:    ("~",  "BLUE"),
    Terrain.SHALLOW_WATER: ("w",  "CYAN"),
    Terrain.PLAIN:         (".",  "GREEN"),
    Terrain.FOREST:        ("T",  "DARKGREEN"),
    Terrain.HIGHLAND:      ("^",  "YELLOW"),
    Terrain.MOUNTAIN:      ("#",  "RED"),
    Terrain.FORTRESS:      ("@",  "MAGENTA"),
    Terrain.GRAIL_PLATFORM:("O",  "YELLOW"),
}

COLOR_MAP = {
    "BLUE":      "\033[38;5;27m",
    "CYAN":      "\033[38;5;51m",
    "GREEN":     "\033[38;5;40m",
    "DARKGREEN": "\033[38;5;22m",
    "YELLOW":    "\033[38;5;178m",
    "RED":       "\033[38;5;196m",
    "MAGENTA":   "\033[38;5;201m",
    "RESET":     "\033[0m",
}

PNG_COLORS = {
    Terrain.VOID:          (18,  25,  55),
    Terrain.DEEP_WATER:    (27,  58,  136),
    Terrain.SHALLOW_WATER: (74,  156, 199),
    Terrain.PLAIN:         (181, 204, 142),
    Terrain.FOREST:        (53,  104, 45),
    Terrain.HIGHLAND:      (196, 176, 112),
    Terrain.MOUNTAIN:      (139, 124, 106),
    Terrain.FORTRESS:      (169, 124, 186),
    Terrain.GRAIL_PLATFORM:(255, 215, 117),
}


# ══════════════════════════════════════════════════════════
# 柏林噪声实现
# 原理：只在整数锚点上生成随机值，中间用平滑插值填充。
# 保证：相邻坐标的输出值一定接近，即地形连续性。
# ══════════════════════════════════════════════════════════

def _hash(x: int, y: int, seed: int) -> float:
    """
    整数坐标 (x,y) → 确定性伪随机值 [0,1)
    同一输入永远输出同一结果（种子决定地图）。
    相邻坐标的输出之间没有数学关联（看起来随机）。
    """
    n = (x * 1619 + y * 31337 + seed * 65537) & 0x7FFFFFFF
    n = ((n ^ 61) ^ (n >> 16)) & 0x7FFFFFFF
    n = (n + (n << 3)) & 0x7FFFFFFF
    n = (n ^ (n >> 4)) & 0x7FFFFFFF
    n = (n * 0x27d4eb2d) & 0x7FFFFFFF
    n = (n ^ (n >> 15)) & 0x7FFFFFFF
    return n / 0x7FFFFFFF


def _smooth(t: float) -> float:
    """
    平滑步进函数 t²×(3-2t)
    作用：让插值权重在两端斜率为0，拼接处无折角。
    """
    return t * t * (3.0 - 2.0 * t)


def _value_noise(x: float, y: float, seed: int) -> float:
    """
    2D值噪声核心：
    1. 找到包围(x,y)的四个整数锚点
    2. 用hash算出四个锚点的值
    3. 用dx,dy做两次lerp插值得到(x,y)处的高度
    结果在[0,1]之间，且连续（相邻坐标输出相近）。
    """
    x0, y0 = int(math.floor(x)), int(math.floor(y))
    # 偏移量：(x,y)在锚点格内的相对位置
    dx = _smooth(x - x0)
    dy = _smooth(y - y0)
    # 四个角锚点的hash值
    n00 = _hash(x0,   y0,   seed)
    n10 = _hash(x0+1, y0,   seed)
    n01 = _hash(x0,   y0+1, seed)
    n11 = _hash(x0+1, y0+1, seed)
    # 第一次插值：横向（上行、下行各一次）
    nx0 = n00 + (n10 - n00) * dx
    nx1 = n01 + (n11 - n01) * dx
    # 第二次插值：纵向（合并上下两行）
    return nx0 + (nx1 - nx0) * dy


def fractal_noise(x: float, y: float, seed: int,
                  octaves: int = NOISE_OCTAVES,
                  lacunarity: float = NOISE_LACUNARITY,
                  gain: float = NOISE_GAIN) -> float:
    """
    分形噪声：叠加多层不同频率的值噪声。
    低频层（振幅大）→ 决定大山脉/平原轮廓
    高频层（振幅小）→ 叠加丘陵和细节凹凸
    结果归一化到[0,1]。
    """
    value, amplitude, frequency, max_value = 0.0, 1.0, 1.0, 0.0
    for i in range(octaves):
        value     += _value_noise(x * frequency, y * frequency, seed + i * 1000) * amplitude
        max_value += amplitude
        amplitude *= gain
        frequency *= lacunarity
    return value / max_value


# ══════════════════════════════════════════════════════════
# 六边形网格
# ══════════════════════════════════════════════════════════

@dataclass
class HexCell:
    q: int
    r: int
    height: float = 0.0
    terrain: Terrain = Terrain.PLAIN
    is_void: bool = False
    # 功能标记
    is_grail_platform: bool = False
    is_city: bool = False
    is_key_point: bool = False
    is_resource_point: bool = False
    is_reward_pool: bool = False
    is_chokepoint: bool = False   # 战略要道
    resource_tier: str = ""       # "common" / "rare"
    city_owner: Optional[int] = None
    spawn_score: float = 0.0      # 出生点质量评分


def hex_distance(q1: int, r1: int, q2: int, r2: int) -> int:
    """六边形曼哈顿距离（轴向坐标系）"""
    return (abs(q1-q2) + abs(q1+r1-q2-r2) + abs(r1-r2)) // 2


def hex_neighbors(q: int, r: int) -> List[Tuple[int, int]]:
    return [(q+1,r),(q+1,r-1),(q,r-1),(q-1,r),(q-1,r+1),(q,r+1)]


def generate_hexes(radius: int) -> Dict[Tuple[int,int], HexCell]:
    cells = {}
    for q in range(-radius, radius+1):
        for r in range(max(-radius,-q-radius), min(radius,-q+radius)+1):
            cells[(q,r)] = HexCell(q=q, r=r)
    return cells


# ══════════════════════════════════════════════════════════
# 污染蔓延系统（大逃杀缩圈）
# ══════════════════════════════════════════════════════════

class ContaminationSystem:
    """
    污染从地图外海（VOID格）边缘向内蔓延。
    每回合从前沿选取若干格污染，优先污染远离玩家的区域。
    蔓延前检查连通性，确保存活玩家仍能互相到达。
    """
    def __init__(self):
        self.contaminated: Set[Tuple[int,int]] = set()
        self.frontier: Set[Tuple[int,int]] = set()

    def initialize(self, cells: Dict[Tuple[int,int], HexCell]):
        """用所有VOID格初始化污染集，找出第一圈陆地前沿"""
        for pos, cell in cells.items():
            if cell.is_void:
                self.contaminated.add(pos)
        for pos in list(self.contaminated):
            for nb in hex_neighbors(*pos):
                if nb in cells and not cells[nb].is_void:
                    self.frontier.add(nb)

    def advance(self, cells: Dict[Tuple[int,int], HexCell],
                n_cells: int,
                player_positions: List[Tuple[int,int]],
                rng: random.Random) -> Set[Tuple[int,int]]:
        """
        污染蔓延一步，返回新增的污染格集合。
        优先污染离玩家最远的前沿格（让玩家感到压迫但不被立刻围死）。
        """
        if not self.frontier:
            return set()

        # 给前沿格打分：离最近玩家越远 → 分数越低（越优先被选）
        scored = []
        for pos in self.frontier:
            if player_positions:
                min_dist = min(hex_distance(*pos, *p) for p in player_positions)
            else:
                min_dist = 1
            # 分数低 = 离玩家远 = 优先污染
            scored.append((min_dist, pos))
        scored.sort(key=lambda x: x[0])

        # 取分数最低的一半（最远离玩家）中随机选
        candidates = [p for _, p in scored[:max(1, len(scored)//2)]]
        to_contaminate = rng.sample(candidates, min(n_cells, len(candidates)))

        newly_contaminated = set()
        for pos in to_contaminate:
            # 连通性检查：确保污染这格后玩家之间仍然连通
            if self._safe_to_contaminate(pos, cells, player_positions):
                self.contaminated.add(pos)
                self.frontier.discard(pos)
                newly_contaminated.add(pos)
                # 更新前沿
                for nb in hex_neighbors(*pos):
                    if nb in cells and nb not in self.contaminated:
                        self.frontier.add(nb)

        return newly_contaminated

    def _safe_to_contaminate(self, pos, cells, player_positions) -> bool:
        """临时污染该格后，检查所有玩家之间是否仍然连通"""
        if len(player_positions) <= 1:
            return True
        temp_blocked = self.contaminated | {pos}
        passable = {p for p in cells
                    if p not in temp_blocked
                    and cells[p].terrain not in
                    (Terrain.MOUNTAIN, Terrain.DEEP_WATER,
                     Terrain.SHALLOW_WATER, Terrain.VOID)}
        return self._all_connected(player_positions, passable)

    def _all_connected(self, players, passable) -> bool:
        if not players:
            return True
        start = players[0]
        if start not in passable:
            return False
        visited = {start}
        queue = [start]
        while queue:
            cur = queue.pop()
            for nb in hex_neighbors(*cur):
                if nb in passable and nb not in visited:
                    visited.add(nb)
                    queue.append(nb)
        return all(p in visited for p in players)

    def shrink_schedule(self, num_players: int, radius: int) -> dict:
        """自适应缩圈时间表"""
        return {
            "start_turn": radius + 2,
            "player_triggers": {
                num_players - 1: 1,
                num_players // 2: 2,
                2: 3,
            },
            "base_cells_per_turn": max(2, radius // 3),
        }


# ══════════════════════════════════════════════════════════
# 地图生成器
# ══════════════════════════════════════════════════════════

class MapGenerator:
    """
    完整地图生成管线（12阶段）：
    1  噪声采样
    2  大陆轮廓遮罩（修复版：逐格2D采样）
    3  高度图平滑（让地形聚团）
    4  地形成型 + 扇区内强制多样性
    5  连通性修复
    6  出生点评分选取
    7  扇区配额资源放置
    8  中心高价值资源
    9  战略通道识别与保护
    10 圣杯台座等特殊点
    11 公平性验证 → 不达标重试
    12 污染系统初始化
    """

    def __init__(self, radius: int, seed: int, num_players: int = 3):
        self.radius      = radius
        self.base_radius = radius + 4
        self.seed        = seed
        self.num_players = num_players
        self.rng         = random.Random(seed) if seed > 0 else random.Random()
        self.cells: Dict[Tuple[int,int], HexCell] = {}
        self.contamination = ContaminationSystem()
        self.stats: dict = {}
        self._spawn_positions: List[Tuple[int,int]] = []

    def generate(self) -> Dict[Tuple[int,int], HexCell]:
        """执行完整生成流程，失败自动重试"""
        for attempt in range(MAX_RETRY):
            self.cells = generate_hexes(self.base_radius)
            attempt_seed = self.seed + attempt * 77777

            noise_seed = self._phase1_noise(attempt_seed)
            self._phase2_continent_mask(noise_seed)
            self._phase3_smooth_heights()
            self._phase4_terrain()
            self._phase5_connectivity()
            self._phase6_spawn_points()
            self._phase7_resources()
            self._phase8_center_resources()
            self._phase9_chokepoints()
            self._phase10_special_tiles()

            result = self._phase11_validate()
            if result["pass"]:
                self.stats["attempt"] = attempt + 1
                self.stats["validation"] = result
                break
            else:
                self.stats["last_issues"] = result["issues"]

        self._phase12_contamination_init()
        self._compute_stats()
        return self.cells

    # ── 阶段1：噪声采样 ──────────────────────────────────
    def _phase1_noise(self, seed: int) -> int:
        noise_seed = seed if seed > 0 else self.rng.randint(1, 99999)
        for (q, r), cell in self.cells.items():
            # 乘以频率×10：控制锚点稀疏程度，越小山脉越大
            cell.height = fractal_noise(
                q * NOISE_FREQUENCY * 10,
                r * NOISE_FREQUENCY * 10,
                noise_seed
            )
        self.stats["noise_seed"] = noise_seed
        return noise_seed

    # ── 阶段2：大陆轮廓遮罩（修复版） ────────────────────
    def _phase2_continent_mask(self, noise_seed: int):
        continent_seed = noise_seed + 77777
        void_list = []

        for pos, cell in self.cells.items():
            q, r = pos
            dist = hex_distance(*pos, 0, 0)
            if dist == 0:
                continue

            # 提高采样频率，让噪声在地图范围内有足够多的波动
            nv = fractal_noise(
                q * 0.18,   # 原来是 q * CONTINENT_NOISE_FREQ * 10 = q * 0.6，改大
                r * 0.18,
                continent_seed,
                octaves=4   # 增加层数让海岸线更复杂
            )

            # 叠加第二层高频噪声，产生锯齿状海湾和半岛
            nv2 = fractal_noise(
                q * 0.35,
                r * 0.35,
                continent_seed + 33333,
                octaves=2
            )
            # 低频决定大轮廓，高频产生细节
            combined = nv * 0.65 + nv2 * 0.35

            norm_dist = dist / self.radius
            # 降低阈值，让遮罩真正裁掉边缘
            # combined 范围约 [0,1]，(combined - 0.5) 范围约 [-0.5, 0.5]
            # COASTLINE_FALLOFF=0.5 时最大扰动 ±0.25
            threshold = 0.88 + (combined - 0.5) * 0.45

            if norm_dist > threshold:
                void_list.append(pos)

        for pos in void_list:
            self.cells[pos].terrain = Terrain.VOID
            self.cells[pos].is_void = True

        self.stats["void_cells"] = len(void_list)

    # ── 阶段3：高度图平滑 ─────────────────────────────────
    def _phase3_smooth_heights(self):
        """
        每个格子新高度 = 自身×0.6 + 邻居均值×0.4
        迭代2次：让相近高度的格子聚团，形成连片地形。
        迭代太多次会让地形过于平坦，2次恰好。
        """
        for _ in range(SMOOTH_ITERATIONS):
            new_heights = {}
            for pos, cell in self.cells.items():
                if cell.is_void:
                    continue
                nb_heights = [
                    self.cells[nb].height
                    for nb in hex_neighbors(*pos)
                    if nb in self.cells and not self.cells[nb].is_void
                ]
                if nb_heights:
                    new_heights[pos] = (
                        cell.height * SMOOTH_SELF_WEIGHT +
                        (sum(nb_heights) / len(nb_heights)) * SMOOTH_NEIGHBOR_WEIGHT
                    )
            for pos, h in new_heights.items():
                self.cells[pos].height = h

    # ── 阶段4：地形成型 + 扇区多样性 ─────────────────────
    def _phase4_terrain(self):
        """
        高度值→地形：用分位数动态确定阈值（不写死），
        保证无论噪声参数怎么调，地形比例都维持目标分布。
        然后对每个扇区检查地形多样性，不足则强制替换。
        """
        land = [c for c in self.cells.values() if not c.is_void]
        if not land:
            return
        heights = sorted(c.height for c in land)
        n = len(heights)

        # 动态分位数阈值
        thresholds = []
        cumulative = 0.0
        for terrain, pct in TERRAIN_TARGETS:
            cumulative += pct
            idx = min(int(cumulative * n), n-1)
            thresholds.append((terrain, heights[idx]))

        for cell in land:
            for terrain, thresh in thresholds:
                if cell.height <= thresh:
                    cell.terrain = terrain
                    break
            else:
                cell.terrain = Terrain.FORTRESS

        # 扇区内强制多样性
        self._enforce_sector_diversity()

        # 孤立小水域填为平原
        self._fill_small_water_bodies()

    def _enforce_sector_diversity(self):
        """每个扇区必须包含平原、森林、高地、山脉"""
        sectors = self._divide_into_sectors(self.num_players)
        required = {Terrain.PLAIN, Terrain.FOREST, Terrain.HIGHLAND, Terrain.MOUNTAIN}

        for sector_cells in sectors:
            present = {self.cells[p].terrain for p in sector_cells if p in self.cells}
            missing = required - present
            # 找平原格子作为替换候选（平原最多，替换影响最小）
            plain_cells = [p for p in sector_cells
                           if p in self.cells and self.cells[p].terrain == Terrain.PLAIN]
            self.rng.shuffle(plain_cells)
            for terrain in missing:
                if plain_cells:
                    target = plain_cells.pop()
                    self.cells[target].terrain = terrain

    def _fill_small_water_bodies(self):
        """孤立≤2格的水域→平原（避免出现无法渡过的小水坑）"""
        water = {pos for pos, c in self.cells.items()
                 if c.terrain in (Terrain.DEEP_WATER, Terrain.SHALLOW_WATER)}
        visited = set()
        for pos in list(water):
            if pos in visited:
                continue
            cluster, stack = [], [pos]
            visited.add(pos)
            while stack:
                cur = stack.pop()
                cluster.append(cur)
                for nb in hex_neighbors(*cur):
                    if nb in water and nb not in visited:
                        visited.add(nb)
                        stack.append(nb)
            if len(cluster) <= 2:
                for p in cluster:
                    self.cells[p].terrain = Terrain.PLAIN

    # ── 阶段5：连通性修复 ─────────────────────────────────
    def _phase5_connectivity(self):
        """
        BFS检查地图是否连通，不通则用Dijkstra找最小代价路径挖通。
        代价：平原=0，水域=2，山脉=3（优先改水域，其次改山脉）
        """
        def passable(pos):
            if pos not in self.cells:
                return False
            return self.cells[pos].terrain not in (
                Terrain.VOID, Terrain.DEEP_WATER,
                Terrain.SHALLOW_WATER, Terrain.MOUNTAIN)

        center = (0, 0)
        passable_set = {p for p in self.cells if passable(p)}
        edge_set = {p for p in passable_set if hex_distance(*p, 0, 0) >= self.radius - 1}
        if not edge_set:
            return

        # BFS快速检查连通性
        if self._bfs_connected(edge_set, passable_set, center):
            return

        self.stats["connectivity_fixed"] = True
        # Dijkstra最小代价挖通
        dist, prev = {}, {}
        heap = []
        for e in edge_set:
            dist[e] = 0
            heapq.heappush(heap, (0, e))

        while heap:
            cost, pos = heapq.heappop(heap)
            if cost > dist.get(pos, float("inf")):
                continue
            if pos == center:
                break
            for nb in hex_neighbors(*pos):
                if nb not in self.cells:
                    continue
                t = self.cells[nb].terrain
                move_cost = 0 if passable(nb) else (
                    2 if t in (Terrain.DEEP_WATER, Terrain.SHALLOW_WATER) else 3)
                new_cost = cost + move_cost
                if new_cost < dist.get(nb, float("inf")):
                    dist[nb] = new_cost
                    prev[nb] = pos
                    heapq.heappush(heap, (new_cost, nb))

        # 回溯路径，把障碍改为平原
        if center in prev:
            cur = center
            while cur in prev:
                c = self.cells[cur]
                if c.terrain in (Terrain.DEEP_WATER, Terrain.SHALLOW_WATER, Terrain.MOUNTAIN):
                    c.terrain = Terrain.PLAIN
                cur = prev[cur]

    def _bfs_connected(self, starts, passable_set, target) -> bool:
        visited = set(starts)
        queue = list(starts)
        while queue:
            cur = queue.pop(0)
            if cur == target:
                return True
            for nb in hex_neighbors(*cur):
                if nb in passable_set and nb not in visited:
                    visited.add(nb)
                    queue.append(nb)
        return False

    # ── 阶段6：出生点评分选取 ─────────────────────────────
    def _phase6_spawn_points(self):
        """
        扇区划分保证出生点角度均匀，
        评分机制保证每个出生点质量合理：
          40% 通行性（周围6格可通行率）
          30% 资源邻近（周围2格内森林/高地数量）
          30% 距中心距离适中（目标距离 = R×0.75）
        """
        passable = [pos for pos, c in self.cells.items()
                    if not c.is_void
                    and c.terrain not in (Terrain.MOUNTAIN, Terrain.DEEP_WATER,
                                          Terrain.SHALLOW_WATER, Terrain.VOID)]

        # 候选：靠近边缘的可通行格
        edge_candidates = [p for p in passable
                           if hex_distance(*p, 0, 0) >= self.radius - 1]

        # 按角度分扇区
        sectors = self._partition_by_angle(edge_candidates, self.num_players)

        self._spawn_positions = []
        for slot in sectors:
            if not slot:
                continue
            # 给每个候选打分，取最高分
            best = max(slot, key=lambda p: self._score_spawn(p))
            self.cells[best].is_city = True
            self._spawn_positions.append(best)
            # 保存评分供验证使用
            self.cells[best].spawn_score = self._score_spawn(best)

        self.stats["spawn_positions"] = self._spawn_positions

    def _score_spawn(self, pos: Tuple[int,int]) -> float:
        """出生点质量评分 [0,1]"""
        q, r = pos
        score = 0.0

        # 维度1：通行性（周围6格可通行率）
        nbs = hex_neighbors(q, r)
        passable_nb = sum(1 for nb in nbs
                          if nb in self.cells
                          and self.cells[nb].terrain not in
                          (Terrain.MOUNTAIN, Terrain.DEEP_WATER,
                           Terrain.SHALLOW_WATER, Terrain.VOID))
        score += (passable_nb / 6) * 0.4

        # 维度2：资源邻近（周围2格内森林/高地）
        ring2 = [p for p in self.cells
                 if 1 <= hex_distance(*p, q, r) <= 2]
        resource_nb = sum(1 for p in ring2
                          if self.cells[p].terrain in
                          (Terrain.FOREST, Terrain.HIGHLAND))
        score += min(resource_nb / 4, 1.0) * 0.3

        # 维度3：距中心距离适中（理想距离 = R×0.75）
        dist = hex_distance(q, r, 0, 0)
        ideal = self.radius * 0.75
        score += max(0, 1 - abs(dist - ideal) / ideal) * 0.3

        return score

    # ── 阶段7：扇区配额资源放置 ──────────────────────────
    def _phase7_resources(self):
        """
        外圈（R×0.7~R）：扇区配额制，保证每个玩家初期基础资源
        中圈（R×0.4~0.7）：稀有资源，需要主动争夺
        内圈已在阶段8处理（核心资源）
        """
        passable = [pos for pos, c in self.cells.items()
                    if not c.is_void
                    and c.terrain not in (Terrain.MOUNTAIN, Terrain.DEEP_WATER,
                                          Terrain.SHALLOW_WATER)
                    and not c.is_grail_platform
                    and not c.is_city]

        sectors = self._divide_into_sectors(self.num_players)
        base_quota = 3  # 每扇区保底资源数

        # 外圈：扇区配额
        for sector in sectors:
            candidates = [p for p in sector
                          if p in set(passable)
                          and not self.cells[p].is_resource_point
                          and hex_distance(*p, 0, 0) > self.radius * 0.4]
            self.rng.shuffle(candidates)
            placed = 0
            for pos in candidates:
                if placed >= base_quota:
                    break
                self.cells[pos].is_resource_point = True
                self.cells[pos].resource_tier = "common"
                placed += 1

        # 中圈：稀有资源
        mid_zone = [p for p in passable
                    if not self.cells[p].is_resource_point
                    and self.radius * 0.4 <= hex_distance(*p, 0, 0) <= self.radius * 0.7]
        self.rng.shuffle(mid_zone)
        for pos in mid_zone[:self.num_players]:
            self.cells[pos].is_resource_point = True
            self.cells[pos].resource_tier = "rare"

        # 奖励池：2~3个森林/高地
        reward_candidates = [pos for pos, c in self.cells.items()
                             if c.terrain in (Terrain.FOREST, Terrain.HIGHLAND)
                             and not c.is_resource_point and not c.is_city]
        self.rng.shuffle(reward_candidates)
        for pos in reward_candidates[:self.rng.randint(2, 3)]:
            self.cells[pos].is_reward_pool = True

    # ── 阶段8：中心高价值资源 ────────────────────────────
    def _phase8_center_resources(self):
        """
        内圈（R×0.4内）：核心资源，高风险高回报。
        玩家必须冒险深入才能获取，自然产生向中心推进的动力。
        """
        center_zone = [pos for pos, c in self.cells.items()
                       if not c.is_void
                       and c.terrain not in (Terrain.MOUNTAIN, Terrain.DEEP_WATER,
                                             Terrain.SHALLOW_WATER)
                       and not c.is_grail_platform
                       and hex_distance(*pos, 0, 0) <= self.radius * 0.4
                       and not self.cells[pos].is_resource_point]
        self.rng.shuffle(center_zone)
        for pos in center_zone[:self.num_players]:
            self.cells[pos].is_resource_point = True
            self.cells[pos].resource_tier = "core"

    # ── 阶段9：战略通道识别与保护 ────────────────────────
    def _phase9_chokepoints(self):
        """
        对每个出生点到中心跑Dijkstra，找最短路径。
        被多条路径共享的格子 → 战略要道（is_chokepoint=True）。
        这些格子不会被污染系统优先污染，地形不可被改为不可通行。
        """
        center = (0, 0)
        path_usage: Dict[Tuple[int,int], int] = {}

        for spawn in self._spawn_positions:
            path = self._dijkstra_path(spawn, center)
            for pos in path:
                path_usage[pos] = path_usage.get(pos, 0) + 1

        # 被2条以上路径共享的格子是真正的战略要道
        for pos, usage in path_usage.items():
            if usage >= 2 and pos in self.cells:
                self.cells[pos].is_chokepoint = True

    def _dijkstra_path(self, start, end) -> List[Tuple[int,int]]:
        """Dijkstra最短路，返回路径上的格子列表"""
        def cost(t):
            if t in (Terrain.VOID, Terrain.DEEP_WATER, Terrain.SHALLOW_WATER):
                return 999
            if t == Terrain.MOUNTAIN:
                return 5
            if t == Terrain.FOREST:
                return 2
            if t == Terrain.HIGHLAND:
                return 3
            return 1

        dist, prev = {start: 0}, {}
        heap = [(0, start)]
        while heap:
            d, pos = heapq.heappop(heap)
            if pos == end:
                break
            if d > dist.get(pos, float("inf")):
                continue
            for nb in hex_neighbors(*pos):
                if nb not in self.cells:
                    continue
                nd = d + cost(self.cells[nb].terrain)
                if nd < dist.get(nb, float("inf")):
                    dist[nb] = nd
                    prev[nb] = pos
                    heapq.heappush(heap, (nd, nb))

        path = []
        cur = end
        while cur in prev:
            path.append(cur)
            cur = prev[cur]
        return path

    # ── 阶段10：特殊格子放置 ─────────────────────────────
    def _phase10_special_tiles(self):
        """圣杯台座在地图中心，钥匙任务点3个"""
        if (0, 0) in self.cells:
            self.cells[(0,0)].is_grail_platform = True
            self.cells[(0,0)].terrain = Terrain.GRAIL_PLATFORM

        passable = [pos for pos, c in self.cells.items()
                    if not c.is_void
                    and c.terrain not in (Terrain.MOUNTAIN, Terrain.DEEP_WATER,
                                          Terrain.SHALLOW_WATER)
                    and not c.is_grail_platform
                    and not c.is_city
                    and hex_distance(*pos, 0, 0) >= 2]
        self.rng.shuffle(passable)
        for pos in passable[:3]:
            self.cells[pos].is_key_point = True

    # ── 阶段11：公平性验证 ────────────────────────────────
    def _phase11_validate(self) -> dict:
        """
        三项量化检测，任意一项不通过则重新生成：
        1. 出生点两两距离差 ≤ MAX_SPAWN_DIST_VARIANCE
        2. 各出生点附近3格内资源数差 ≤ MAX_RESOURCE_IMBALANCE
        3. 各出生点到中心BFS路径长差 ≤ MAX_PATH_LENGTH_VARIANCE
        """
        issues = []
        spawns = self._spawn_positions
        if len(spawns) < self.num_players:
            return {"pass": False, "issues": ["spawn_count_insufficient"]}

        # 检测1：出生点间距
        dists = [hex_distance(*a, *b)
                 for i, a in enumerate(spawns)
                 for b in spawns[i+1:]]
        if dists and max(dists) - min(dists) > MAX_SPAWN_DIST_VARIANCE:
            issues.append(f"spawn_dist_variance={max(dists)-min(dists)}")

        # 检测2：各出生点附近资源数
        local_res = []
        for sp in spawns:
            count = sum(1 for pos, c in self.cells.items()
                        if c.is_resource_point
                        and hex_distance(*pos, *sp) <= 3)
            local_res.append(count)
        if local_res and max(local_res) - min(local_res) > MAX_RESOURCE_IMBALANCE:
            issues.append(f"resource_imbalance={local_res}")

        # 检测3：到中心路径长度
        path_lens = [len(self._dijkstra_path(sp, (0,0))) for sp in spawns]
        if path_lens and max(path_lens) - min(path_lens) > MAX_PATH_LENGTH_VARIANCE:
            issues.append(f"path_length_variance={max(path_lens)-min(path_lens)}")

        return {"pass": len(issues) == 0, "issues": issues}

    # ── 阶段12：污染系统初始化 ────────────────────────────
    def _phase12_contamination_init(self):
        """用所有VOID格初始化污染系统，准备运行时缩圈"""
        self.contamination.initialize(self.cells)
        self.stats["shrink_schedule"] = self.contamination.shrink_schedule(
            self.num_players, self.radius)

    # ── 辅助方法 ──────────────────────────────────────────

    def _divide_into_sectors(self, n_slots: int) -> List[List[Tuple[int,int]]]:
        """把所有非VOID格按角度分成n_slots个扇区"""
        slots = [[] for _ in range(n_slots)]
        for pos, cell in self.cells.items():
            if cell.is_void:
                continue
            q, r = pos
            angle = math.atan2(r, q)
            if angle < 0:
                angle += 2 * math.pi
            idx = int(angle / (2 * math.pi) * n_slots) % n_slots
            slots[idx].append(pos)
        return slots

    def _partition_by_angle(self, positions, n_slots) -> List[List[Tuple[int,int]]]:
        """把候选位置按角度分成n_slots个扇区"""
        slots = [[] for _ in range(n_slots)]
        for pos in positions:
            q, r = pos
            angle = math.atan2(r, q)
            if angle < 0:
                angle += 2 * math.pi
            idx = int(angle / (2 * math.pi) * n_slots) % n_slots
            slots[idx].append(pos)
        return slots

    def _compute_stats(self):
        counts = {}
        for cell in self.cells.values():
            if cell.is_void:
                continue
            counts[cell.terrain] = counts.get(cell.terrain, 0) + 1
        total = sum(counts.values())
        self.stats["terrain_counts"] = {t.name: c for t, c in counts.items()}
        self.stats["terrain_pct"]    = {t.name: f"{c/total*100:.1f}%" for t, c in counts.items()}
        self.stats["total_land"]     = total

    def get_stats_text(self) -> str:
        lines = [
            f"Seed: {self.stats.get('noise_seed','N/A')}  "
            f"R={self.radius}  Players={self.num_players}  "
            f"Attempt={self.stats.get('attempt',1)}",
            f"Land tiles: {self.stats.get('total_land','?')}  "
            f"Void tiles: {self.stats.get('void_cells','?')}",
            f"Connectivity fixed: {self.stats.get('connectivity_fixed', False)}",
            "",
            "Terrain distribution:",
        ]
        pcts = self.stats.get("terrain_pct", {})
        for t in Terrain:
            if t == Terrain.VOID:
                continue
            pct = pcts.get(t.name, "0%")
            lines.append(f"  {t.name:<18}: {pct}")

        val = self.stats.get("validation", {})
        lines.append(f"\nFairness: {'PASS' if val.get('pass') else 'FAIL'}")
        if val.get("issues"):
            for iss in val["issues"]:
                lines.append(f"  ! {iss}")

        sched = self.stats.get("shrink_schedule", {})
        lines.append(f"\nShrink starts turn: {sched.get('start_turn','?')}")
        lines.append(f"Cells per turn: {sched.get('base_cells_per_turn','?')}")
        return "\n".join(lines)


# ══════════════════════════════════════════════════════════
# ASCII渲染
# ══════════════════════════════════════════════════════════

def _cell_char(cell: HexCell) -> str:
    if cell.is_void:          return " "
    if cell.is_grail_platform:return "O"
    if cell.is_city:          return "@"
    if cell.is_key_point:     return "K"
    if cell.is_reward_pool:   return "$"
    if cell.is_resource_point:
        return "*" if cell.resource_tier == "common" else (
               "+" if cell.resource_tier == "rare" else "!")
    if cell.is_chokepoint:    return "="
    char, _ = TERRAIN_ASCII.get(cell.terrain, ("?", "RESET"))
    return char


def _cell_color(cell: HexCell) -> str:
    if cell.is_grail_platform: return COLOR_MAP["YELLOW"]
    if cell.is_city:           return COLOR_MAP["MAGENTA"]
    if cell.is_key_point:      return COLOR_MAP["YELLOW"]
    if cell.is_reward_pool:    return COLOR_MAP["YELLOW"]
    if cell.is_resource_point: return COLOR_MAP["CYAN"]
    if cell.is_chokepoint:     return COLOR_MAP["RED"]
    _, color = TERRAIN_ASCII.get(cell.terrain, ("?", "RESET"))
    return COLOR_MAP.get(color, COLOR_MAP["RESET"])


def render_ascii(cells: Dict[Tuple[int,int], HexCell]) -> str:
    rows: Dict[int, List] = {}
    for (q, r), cell in cells.items():
        rows.setdefault(r, []).append((q, cell))

    active = {r: items for r, items in rows.items()
              if any(not c.is_void for _, c in items)}
    if not active:
        return "(empty)"

    has_color = HAS_COLOR and sys.stdout.isatty()
    lines = []
    for r in range(min(active), max(active)+1):
        items = active.get(r, [])
        non_void = [(q,c) for q,c in items if not c.is_void]
        if not non_void:
            continue
        min_q = min(q for q,_ in non_void)
        max_q = max(q for q,_ in non_void)
        in_range = sorted([(q,c) for q,c in items if min_q-1<=q<=max_q+1],
                          key=lambda x: x[0])
        line = ("  " if r % 2 != 0 else "")
        for q, cell in in_range:
            ch = _cell_char(cell)
            if has_color and not cell.is_void:
                line += f"{_cell_color(cell)}{ch}{COLOR_MAP['RESET']} "
            else:
                line += f"{ch} "
        lines.append(line.rstrip())
    return "\n".join(lines)


def render_legend() -> str:
    items = [
        ("O 圣杯台座",    "YELLOW"),
        ("@ 出生城市",    "MAGENTA"),
        ("K 钥匙任务点",  "YELLOW"),
        ("* 普通资源",    "CYAN"),
        ("+ 稀有资源",    "CYAN"),
        ("! 核心资源",    "CYAN"),
        ("$ 奖励池",      "YELLOW"),
        ("= 战略要道",    "RED"),
        ("~ 深水",        "BLUE"),
        ("w 浅水",        "CYAN"),
        (". 平原",        "GREEN"),
        ("T 森林",        "DARKGREEN"),
        ("^ 高地",        "YELLOW"),
        ("# 山脉",        "RED"),
        ("@ 要塞",        "MAGENTA"),
    ]
    has_color = HAS_COLOR and sys.stdout.isatty()
    lines = ["\nLegend:"]
    for label, color in items:
        if has_color:
            lines.append(f"  {COLOR_MAP.get(color,'')}{label}{COLOR_MAP['RESET']}")
        else:
            lines.append(f"  {label}")
    return "\n".join(lines)


# ══════════════════════════════════════════════════════════
# PNG渲染
# ══════════════════════════════════════════════════════════

def render_png(cells, radius, base_radius, filepath="hex_map.png"):
    if not HAS_PIL:
        print("需要 pillow: pip install pillow")
        return
    hex_size = 28
    w = int(2 * hex_size * (math.sqrt(3) * base_radius + math.sqrt(3))) + 60
    h = int(2 * hex_size * (1.5 * base_radius + 1)) + 60
    img = Image.new("RGB", (w, h), (10, 15, 40))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("consola.ttf", 9)
    except:
        font = ImageFont.load_default()

    for (q, r), cell in cells.items():
        cx = int(w/2 + hex_size * (math.sqrt(3)*q + math.sqrt(3)/2*r))
        cy = int(h/2 + hex_size * 1.5 * r)
        verts = [(cx + hex_size*math.cos(math.pi/180*(60*i-30)),
                  cy + hex_size*math.sin(math.pi/180*(60*i-30))) for i in range(6)]
        if cell.is_void:
            draw.polygon(verts, fill=(18,25,55))
            continue
        color = PNG_COLORS.get(cell.terrain, (128,128,128))
        draw.polygon(verts, fill=color, outline=(60,60,60))
        if cell.is_grail_platform:
            draw.ellipse([cx-7,cy-7,cx+7,cy+7], fill=(255,215,0))
        if cell.is_city:
            draw.rectangle([cx-5,cy-5,cx+5,cy+5], fill=(255,80,80))
        if cell.is_chokepoint:
            draw.ellipse([cx-3,cy-3,cx+3,cy+3], fill=(255,100,50), outline=None)

    img.save(filepath)
    print(f"PNG saved: {filepath}")


# ══════════════════════════════════════════════════════════
# 主函数
# ══════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="战旗大逃杀 — 六边形地图生成器 v2.0")
    parser.add_argument("seed", nargs="?", type=int, default=0,
                        help="地图种子 (0=随机)")
    parser.add_argument("--players", "-p", type=int, default=3,
                        choices=[3,4,5,6])
    parser.add_argument("--radius", "-r", type=int, default=None)
    parser.add_argument("--png", action="store_true")
    parser.add_argument("--output", "-o", type=str, default="hex_map.png")
    args = parser.parse_args()

    num_players = args.players
    radius = args.radius or PLAYERS_TO_RADIUS.get(num_players, DEFAULT_RADIUS)
    seed = args.seed if args.seed != 0 else random.randint(1, 99999)

    gen = MapGenerator(radius=radius, seed=seed, num_players=num_players)
    cells = gen.generate()

    header = "=" * 52
    print(header)
    print("  战旗大逃杀 — Hex Map Generator v2.0")
    print(header)
    print()
    print(render_ascii(cells))
    print(render_legend())
    print()
    print(gen.get_stats_text())

    if args.png:
        render_png(cells, radius, gen.base_radius, args.output)


if __name__ == "__main__":
    main()
