---
name: procedural-generation
description: "Procedural generation patterns — Perlin/Simplex noise, BSP dungeon generation, random walk, loot tables with weighted random, wave function collapse basics, seed-based reproducibility."
globs: ["**/Procedural*.cs", "**/Generate*.cs", "**/Dungeon*.cs", "**/Noise*.cs", "**/Loot*.cs"]
---

# Procedural Generation Patterns

Patterns for generating content at runtime: terrain with noise, dungeons with BSP, caves with random walk, loot with weighted tables, and tile layouts with wave function collapse. All patterns support seed-based reproducibility.

## Seed-Based Reproducibility

Every generation algorithm should accept a seed. Given the same seed, the output is identical. This enables shareable worlds, bug reproduction, and daily challenge modes.

**Critical rule:** Use `System.Random` (not `UnityEngine.Random`) for deterministic generation. `UnityEngine.Random` is a global singleton; any other code calling it between your generation steps will change the sequence.

```csharp
public class SeededRandom
{
    private System.Random _rng;
    public int Seed { get; }

    public SeededRandom(int seed)
    {
        Seed = seed;
        _rng = new System.Random(seed);
    }

    public int Next(int min, int max) => _rng.Next(min, max);
    public float NextFloat() => (float)_rng.NextDouble();
    public float Range(float min, float max) => min + (max - min) * NextFloat();
    public bool Chance(float probability) => NextFloat() < probability;

    /// <summary>Shuffle a list in place using Fisher-Yates.</summary>
    public void Shuffle<T>(IList<T> list)
    {
        for (int i = list.Count - 1; i > 0; i--)
        {
            int j = _rng.Next(0, i + 1);
            (list[i], list[j]) = (list[j], list[i]);
        }
    }
}
```

For world generation, derive sub-seeds from the master seed so different systems (terrain, dungeons, loot) do not interfere:

```csharp
int masterSeed = 12345;
var terrainRng = new SeededRandom(masterSeed);
var dungeonRng = new SeededRandom(masterSeed + 1);
var lootRng = new SeededRandom(masterSeed + 2);
```

---

## Noise-Based Terrain Generation

Use Perlin noise to generate height maps for terrain, biome maps, moisture maps, and other continuous fields.

### Basic Height Map

```csharp
using UnityEngine;

public static class NoiseGenerator
{
    /// <summary>
    /// Generate a 2D noise map. Values range from 0 to 1.
    /// </summary>
    public static float[,] GenerateNoiseMap(
        int width, int height, int seed,
        float scale, int octaves, float persistence, float lacunarity,
        Vector2 offset)
    {
        var map = new float[width, height];

        // Use seed to generate random octave offsets
        var rng = new System.Random(seed);
        var octaveOffsets = new Vector2[octaves];
        for (int i = 0; i < octaves; i++)
        {
            float ox = rng.Next(-100000, 100000) + offset.x;
            float oy = rng.Next(-100000, 100000) + offset.y;
            octaveOffsets[i] = new Vector2(ox, oy);
        }

        if (scale <= 0f) scale = 0.001f;

        float maxNoise = float.MinValue;
        float minNoise = float.MaxValue;

        float halfW = width / 2f;
        float halfH = height / 2f;

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                float amplitude = 1f;
                float frequency = 1f;
                float noiseHeight = 0f;

                for (int o = 0; o < octaves; o++)
                {
                    float sampleX = (x - halfW + octaveOffsets[o].x) / scale * frequency;
                    float sampleY = (y - halfH + octaveOffsets[o].y) / scale * frequency;

                    // Mathf.PerlinNoise returns 0-1; remap to -1 to 1
                    float perlin = Mathf.PerlinNoise(sampleX, sampleY) * 2f - 1f;
                    noiseHeight += perlin * amplitude;

                    amplitude *= persistence;  // Each octave contributes less
                    frequency *= lacunarity;    // Each octave has finer detail
                }

                map[x, y] = noiseHeight;

                if (noiseHeight > maxNoise) maxNoise = noiseHeight;
                if (noiseHeight < minNoise) minNoise = noiseHeight;
            }
        }

        // Normalize to 0-1
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++)
                map[x, y] = Mathf.InverseLerp(minNoise, maxNoise, map[x, y]);

        return map;
    }
}
```

**Parameter guide:**
| Parameter   | Effect                          | Typical Value |
|-------------|--------------------------------|---------------|
| scale       | Zoom level (higher = smoother) | 20-100        |
| octaves     | Layers of detail               | 4-6           |
| persistence | Amplitude decay per octave     | 0.4-0.6       |
| lacunarity  | Frequency increase per octave  | 1.8-2.2       |

### Applying Noise to a Tilemap

```csharp
using UnityEngine;
using UnityEngine.Tilemaps;

public class TerrainGenerator : MonoBehaviour
{
    [SerializeField] private Tilemap tilemap;
    [SerializeField] private TileBase waterTile;
    [SerializeField] private TileBase sandTile;
    [SerializeField] private TileBase grassTile;
    [SerializeField] private TileBase stoneTile;
    [SerializeField] private TileBase snowTile;

    [Header("Generation Settings")]
    [SerializeField] private int width = 100;
    [SerializeField] private int height = 100;
    [SerializeField] private int seed = 42;
    [SerializeField] private float scale = 30f;
    [SerializeField] private int octaves = 4;
    [SerializeField] private float persistence = 0.5f;
    [SerializeField] private float lacunarity = 2f;

    [Header("Height Thresholds")]
    [SerializeField] private float waterLevel = 0.3f;
    [SerializeField] private float sandLevel = 0.4f;
    [SerializeField] private float grassLevel = 0.7f;
    [SerializeField] private float stoneLevel = 0.85f;

    public void Generate()
    {
        tilemap.ClearAllTiles();

        var noiseMap = NoiseGenerator.GenerateNoiseMap(
            width, height, seed, scale, octaves, persistence, lacunarity, Vector2.zero);

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                float value = noiseMap[x, y];
                TileBase tile = GetTileForHeight(value);
                tilemap.SetTile(new Vector3Int(x - width / 2, y - height / 2, 0), tile);
            }
        }
    }

    private TileBase GetTileForHeight(float height)
    {
        if (height < waterLevel) return waterTile;
        if (height < sandLevel) return sandTile;
        if (height < grassLevel) return grassTile;
        if (height < stoneLevel) return stoneTile;
        return snowTile;
    }
}
```

---

## BSP Dungeon Generation

Binary Space Partition creates rectangular rooms connected by corridors. It produces clean, grid-aligned dungeons suitable for roguelikes and RPGs.

### Algorithm Overview

1. Start with a large rectangle (the entire dungeon area).
2. Recursively split it in half (horizontally or vertically) until pieces reach minimum size.
3. Place a room inside each leaf partition (with random padding).
4. Connect sibling rooms with corridors.

### Implementation

```csharp
using System.Collections.Generic;
using UnityEngine;

public class BSPDungeon
{
    public class BSPNode
    {
        public RectInt Area;
        public BSPNode Left;
        public BSPNode Right;
        public RectInt? Room;

        public bool IsLeaf => Left == null && Right == null;
    }

    private int _minPartitionSize;
    private int _minRoomSize;
    private int _roomPadding;
    private SeededRandom _rng;

    private List<RectInt> _rooms = new();
    private HashSet<Vector2Int> _corridors = new();

    public IReadOnlyList<RectInt> Rooms => _rooms;
    public IReadOnlyCollection<Vector2Int> Corridors => _corridors;

    public BSPDungeon(int minPartitionSize = 10, int minRoomSize = 4, int roomPadding = 2)
    {
        _minPartitionSize = minPartitionSize;
        _minRoomSize = minRoomSize;
        _roomPadding = roomPadding;
    }

    public int[,] Generate(int width, int height, int seed)
    {
        _rng = new SeededRandom(seed);
        _rooms.Clear();
        _corridors.Clear();

        // 0 = wall, 1 = floor
        var grid = new int[width, height];

        // Build BSP tree
        var root = new BSPNode { Area = new RectInt(0, 0, width, height) };
        Split(root);

        // Place rooms in leaves
        PlaceRooms(root);

        // Connect rooms
        ConnectRooms(root);

        // Write rooms to grid
        foreach (var room in _rooms)
        {
            for (int x = room.x; x < room.x + room.width; x++)
                for (int y = room.y; y < room.y + room.height; y++)
                    grid[x, y] = 1;
        }

        // Write corridors to grid
        foreach (var pos in _corridors)
        {
            if (pos.x >= 0 && pos.x < width && pos.y >= 0 && pos.y < height)
                grid[pos.x, pos.y] = 1;
        }

        return grid;
    }

    private void Split(BSPNode node)
    {
        // Stop if too small to split
        if (node.Area.width < _minPartitionSize * 2 &&
            node.Area.height < _minPartitionSize * 2)
            return;

        // Choose split direction
        bool splitHorizontal;
        if (node.Area.width < _minPartitionSize * 2)
            splitHorizontal = true;
        else if (node.Area.height < _minPartitionSize * 2)
            splitHorizontal = false;
        else
            splitHorizontal = _rng.Chance(0.5f);

        if (splitHorizontal)
        {
            int splitY = _rng.Next(
                node.Area.y + _minPartitionSize,
                node.Area.y + node.Area.height - _minPartitionSize);

            node.Left = new BSPNode
            {
                Area = new RectInt(node.Area.x, node.Area.y,
                    node.Area.width, splitY - node.Area.y)
            };
            node.Right = new BSPNode
            {
                Area = new RectInt(node.Area.x, splitY,
                    node.Area.width, node.Area.y + node.Area.height - splitY)
            };
        }
        else
        {
            int splitX = _rng.Next(
                node.Area.x + _minPartitionSize,
                node.Area.x + node.Area.width - _minPartitionSize);

            node.Left = new BSPNode
            {
                Area = new RectInt(node.Area.x, node.Area.y,
                    splitX - node.Area.x, node.Area.height)
            };
            node.Right = new BSPNode
            {
                Area = new RectInt(splitX, node.Area.y,
                    node.Area.x + node.Area.width - splitX, node.Area.height)
            };
        }

        Split(node.Left);
        Split(node.Right);
    }

    private void PlaceRooms(BSPNode node)
    {
        if (node.IsLeaf)
        {
            int roomW = _rng.Next(_minRoomSize, node.Area.width - _roomPadding * 2);
            int roomH = _rng.Next(_minRoomSize, node.Area.height - _roomPadding * 2);
            int roomX = _rng.Next(node.Area.x + _roomPadding,
                node.Area.x + node.Area.width - roomW - _roomPadding);
            int roomY = _rng.Next(node.Area.y + _roomPadding,
                node.Area.y + node.Area.height - roomH - _roomPadding);

            var room = new RectInt(roomX, roomY, roomW, roomH);
            node.Room = room;
            _rooms.Add(room);
            return;
        }

        if (node.Left != null) PlaceRooms(node.Left);
        if (node.Right != null) PlaceRooms(node.Right);
    }

    private void ConnectRooms(BSPNode node)
    {
        if (node.IsLeaf) return;

        ConnectRooms(node.Left);
        ConnectRooms(node.Right);

        // Connect a room from left subtree to a room from right subtree
        var leftRoom = GetRoomFromSubtree(node.Left);
        var rightRoom = GetRoomFromSubtree(node.Right);

        if (leftRoom.HasValue && rightRoom.HasValue)
        {
            Vector2Int centerA = new Vector2Int(
                leftRoom.Value.x + leftRoom.Value.width / 2,
                leftRoom.Value.y + leftRoom.Value.height / 2);
            Vector2Int centerB = new Vector2Int(
                rightRoom.Value.x + rightRoom.Value.width / 2,
                rightRoom.Value.y + rightRoom.Value.height / 2);

            CreateCorridor(centerA, centerB);
        }
    }

    private RectInt? GetRoomFromSubtree(BSPNode node)
    {
        if (node.Room.HasValue) return node.Room;
        if (node.Left != null)
        {
            var r = GetRoomFromSubtree(node.Left);
            if (r.HasValue) return r;
        }
        if (node.Right != null) return GetRoomFromSubtree(node.Right);
        return null;
    }

    private void CreateCorridor(Vector2Int from, Vector2Int to)
    {
        // L-shaped corridor: horizontal then vertical (or vice versa)
        Vector2Int current = from;

        // Horizontal segment
        while (current.x != to.x)
        {
            _corridors.Add(current);
            // Add width to corridor
            _corridors.Add(current + Vector2Int.up);
            current.x += current.x < to.x ? 1 : -1;
        }

        // Vertical segment
        while (current.y != to.y)
        {
            _corridors.Add(current);
            _corridors.Add(current + Vector2Int.right);
            current.y += current.y < to.y ? 1 : -1;
        }
    }
}
```

---

## Random Walk (Cave Generation)

A drunk walk algorithm for organic, cave-like spaces.

```csharp
using System.Collections.Generic;
using UnityEngine;

public static class RandomWalkGenerator
{
    /// <summary>
    /// Generate cave-like floor positions using a random walk.
    /// </summary>
    public static HashSet<Vector2Int> DrunkWalk(
        Vector2Int startPos, int steps, int seed)
    {
        var rng = new SeededRandom(seed);
        var floorPositions = new HashSet<Vector2Int> { startPos };
        var current = startPos;

        Vector2Int[] directions = {
            Vector2Int.up, Vector2Int.down, Vector2Int.left, Vector2Int.right
        };

        for (int i = 0; i < steps; i++)
        {
            current += directions[rng.Next(0, 4)];
            floorPositions.Add(current);
        }

        return floorPositions;
    }

    /// <summary>
    /// Multiple random walks from the same origin for wider caves.
    /// </summary>
    public static HashSet<Vector2Int> MultiWalk(
        Vector2Int startPos, int walks, int stepsPerWalk, int seed)
    {
        var rng = new SeededRandom(seed);
        var allFloors = new HashSet<Vector2Int>();

        for (int w = 0; w < walks; w++)
        {
            var floors = DrunkWalk(startPos, stepsPerWalk, rng.Next(0, int.MaxValue));
            allFloors.UnionWith(floors);
        }

        return allFloors;
    }

    /// <summary>
    /// Corridor-constrained walk: bias in one direction for path-like caves.
    /// </summary>
    public static HashSet<Vector2Int> CorridorWalk(
        Vector2Int startPos, int length, Vector2Int primaryDirection, int seed,
        float straightChance = 0.7f)
    {
        var rng = new SeededRandom(seed);
        var positions = new HashSet<Vector2Int> { startPos };
        var current = startPos;

        Vector2Int[] perpendicular = primaryDirection.x != 0
            ? new[] { Vector2Int.up, Vector2Int.down }
            : new[] { Vector2Int.left, Vector2Int.right };

        for (int i = 0; i < length; i++)
        {
            if (rng.Chance(straightChance))
            {
                current += primaryDirection;
            }
            else
            {
                current += perpendicular[rng.Next(0, 2)];
            }
            positions.Add(current);
        }

        return positions;
    }
}
```

---

## Weighted Random (Loot Tables)

A generic weighted random selection system. Essential for loot drops, enemy spawns, and any "pick one from a pool with different probabilities" scenario.

```csharp
using System;
using System.Collections.Generic;

[Serializable]
public struct WeightedItem<T>
{
    public T item;
    public float weight;
}

public class WeightedRandom<T>
{
    private List<WeightedItem<T>> _items = new();
    private float _totalWeight;

    public void Add(T item, float weight)
    {
        _items.Add(new WeightedItem<T> { item = item, weight = weight });
        _totalWeight += weight;
    }

    public void AddRange(IEnumerable<WeightedItem<T>> items)
    {
        foreach (var item in items)
            Add(item.item, item.weight);
    }

    /// <summary>
    /// Pick one item based on weights. Uses System.Random for determinism.
    /// </summary>
    public T Pick(System.Random rng)
    {
        float roll = (float)rng.NextDouble() * _totalWeight;
        float cumulative = 0f;

        foreach (var entry in _items)
        {
            cumulative += entry.weight;
            if (roll <= cumulative)
                return entry.item;
        }

        // Fallback (floating point edge case)
        return _items[_items.Count - 1].item;
    }

    /// <summary>
    /// Pick N unique items (no repeats). For loot tables that drop multiple items.
    /// </summary>
    public List<T> PickMultipleUnique(int count, System.Random rng)
    {
        var result = new List<T>();
        var remaining = new List<WeightedItem<T>>(_items);
        float remainingWeight = _totalWeight;

        for (int i = 0; i < count && remaining.Count > 0; i++)
        {
            float roll = (float)rng.NextDouble() * remainingWeight;
            float cumulative = 0f;

            for (int j = 0; j < remaining.Count; j++)
            {
                cumulative += remaining[j].weight;
                if (roll <= cumulative)
                {
                    result.Add(remaining[j].item);
                    remainingWeight -= remaining[j].weight;
                    remaining.RemoveAt(j);
                    break;
                }
            }
        }

        return result;
    }
}
```

### Loot Table ScriptableObject

```csharp
using System;
using UnityEngine;

[Serializable]
public struct LootEntry
{
    public ItemDefinition item;
    public float weight;
    public int minCount;
    public int maxCount;
}

[CreateAssetMenu(fileName = "New Loot Table", menuName = "Loot/Loot Table")]
public class LootTable : ScriptableObject
{
    public LootEntry[] entries;
    public int minDrops = 1;
    public int maxDrops = 3;

    [Header("Guaranteed Drops")]
    public ItemDefinition[] guaranteedDrops;

    [Header("Pity System")]
    [Tooltip("After this many rolls without a rare drop, force one.")]
    public int pityThreshold = 20;
    public float rareWeightThreshold = 5f; // Items with weight below this are 'rare'

    public List<(ItemDefinition item, int count)> Roll(System.Random rng, int pityCounter = 0)
    {
        var result = new List<(ItemDefinition, int)>();

        // Guaranteed drops first
        foreach (var guaranteed in guaranteedDrops)
        {
            if (guaranteed != null)
                result.Add((guaranteed, 1));
        }

        // Random drops
        int dropCount = rng.Next(minDrops, maxDrops + 1);
        var table = new WeightedRandom<LootEntry>();

        foreach (var entry in entries)
        {
            float weight = entry.weight;

            // Pity system: boost rare item weights when pity counter is high
            if (pityCounter >= pityThreshold && weight <= rareWeightThreshold)
            {
                weight *= 3f; // Triple the chance of rare items
            }

            table.Add(entry, weight);
        }

        for (int i = 0; i < dropCount; i++)
        {
            var drop = table.Pick(rng);
            int count = rng.Next(drop.minCount, drop.maxCount + 1);
            result.Add((drop.item, count));
        }

        return result;
    }
}
```

---

## Wave Function Collapse (Basics)

WFC generates tile layouts where every tile respects adjacency rules with its neighbors. It produces surprisingly coherent results for maps, buildings, and patterns.

### Core Concept

1. Start with a grid where each cell can be any tile (all possibilities).
2. Find the cell with the fewest remaining possibilities (lowest entropy).
3. Collapse it: randomly pick one tile from its possibilities.
4. Propagate: remove impossible tiles from neighbors based on adjacency rules.
5. Repeat until all cells are collapsed (or a contradiction is hit).

### Simplified Implementation

```csharp
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

[System.Serializable]
public class WFCTile
{
    public string tileId;
    public TileBase unityTile;
    public float weight = 1f;

    // Which tiles can be adjacent in each direction
    public string[] allowedUp;
    public string[] allowedDown;
    public string[] allowedLeft;
    public string[] allowedRight;

    public string[] GetAllowed(int direction)
    {
        return direction switch
        {
            0 => allowedUp,
            1 => allowedRight,
            2 => allowedDown,
            3 => allowedLeft,
            _ => null
        };
    }
}

public class WFCGenerator
{
    private int _width, _height;
    private List<WFCTile> _allTiles;
    private HashSet<string>[,] _possibilities;
    private string[,] _result;
    private System.Random _rng;

    private static readonly Vector2Int[] Directions = {
        Vector2Int.up, Vector2Int.right, Vector2Int.down, Vector2Int.left
    };

    private static readonly int[] Opposite = { 2, 3, 0, 1 };

    public string[,] Generate(int width, int height, List<WFCTile> tiles, int seed)
    {
        _width = width;
        _height = height;
        _allTiles = tiles;
        _rng = new System.Random(seed);
        _result = new string[width, height];
        _possibilities = new HashSet<string>[width, height];

        // Initialize: every cell can be any tile
        var allIds = tiles.Select(t => t.tileId).ToHashSet();
        for (int x = 0; x < width; x++)
            for (int y = 0; y < height; y++)
                _possibilities[x, y] = new HashSet<string>(allIds);

        // Iterate until fully collapsed
        while (true)
        {
            var cell = FindLowestEntropyCell();
            if (cell == null) break; // All collapsed

            Collapse(cell.Value);
            Propagate(cell.Value);
        }

        return _result;
    }

    private Vector2Int? FindLowestEntropyCell()
    {
        int minEntropy = int.MaxValue;
        Vector2Int? best = null;

        for (int x = 0; x < _width; x++)
        {
            for (int y = 0; y < _height; y++)
            {
                int count = _possibilities[x, y].Count;
                if (count <= 1) continue; // Already collapsed
                if (count < minEntropy)
                {
                    minEntropy = count;
                    best = new Vector2Int(x, y);
                }
            }
        }

        return best;
    }

    private void Collapse(Vector2Int pos)
    {
        // Weighted random selection from remaining possibilities
        var possible = _possibilities[pos.x, pos.y].ToList();
        var table = new WeightedRandom<string>();
        foreach (var id in possible)
        {
            var tile = _allTiles.First(t => t.tileId == id);
            table.Add(id, tile.weight);
        }

        string chosen = table.Pick(_rng);
        _possibilities[pos.x, pos.y] = new HashSet<string> { chosen };
        _result[pos.x, pos.y] = chosen;
    }

    private void Propagate(Vector2Int start)
    {
        var stack = new Stack<Vector2Int>();
        stack.Push(start);

        while (stack.Count > 0)
        {
            var current = stack.Pop();

            for (int d = 0; d < 4; d++)
            {
                var neighbor = current + Directions[d];
                if (neighbor.x < 0 || neighbor.x >= _width ||
                    neighbor.y < 0 || neighbor.y >= _height)
                    continue;

                // Compute which tiles the neighbor can be, given current cell's possibilities
                var allowedAtNeighbor = new HashSet<string>();
                foreach (var tileId in _possibilities[current.x, current.y])
                {
                    var tile = _allTiles.First(t => t.tileId == tileId);
                    foreach (var allowed in tile.GetAllowed(d))
                        allowedAtNeighbor.Add(allowed);
                }

                int before = _possibilities[neighbor.x, neighbor.y].Count;
                _possibilities[neighbor.x, neighbor.y].IntersectWith(allowedAtNeighbor);
                int after = _possibilities[neighbor.x, neighbor.y].Count;

                // If we reduced possibilities, propagate further
                if (after < before)
                {
                    if (after == 1)
                    {
                        _result[neighbor.x, neighbor.y] =
                            _possibilities[neighbor.x, neighbor.y].First();
                    }
                    if (after == 0)
                    {
                        Debug.LogWarning($"WFC contradiction at ({neighbor.x}, {neighbor.y})");
                        // Handle contradiction: restart or backtrack
                    }
                    stack.Push(neighbor);
                }
            }
        }
    }
}
```

WFC is powerful but the adjacency rules definition is the hard part. For simple projects, define rules manually. For complex tilesets, auto-derive rules from a sample image.

---

## Object Placement: Poisson Disk Sampling

Place objects (trees, rocks, items) with natural-looking spacing. Unlike pure random placement, Poisson disk sampling guarantees a minimum distance between points.

```csharp
using System.Collections.Generic;
using UnityEngine;

public static class PoissonDiskSampling
{
    public static List<Vector2> Generate(
        float width, float height, float minDistance, int seed, int maxAttempts = 30)
    {
        var rng = new System.Random(seed);
        float cellSize = minDistance / Mathf.Sqrt(2f);
        int gridW = Mathf.CeilToInt(width / cellSize);
        int gridH = Mathf.CeilToInt(height / cellSize);
        var grid = new int[gridW, gridH];
        for (int x = 0; x < gridW; x++)
            for (int y = 0; y < gridH; y++)
                grid[x, y] = -1;

        var points = new List<Vector2>();
        var activeList = new List<int>();

        // Start with a random point
        var initial = new Vector2(
            (float)rng.NextDouble() * width,
            (float)rng.NextDouble() * height);
        points.Add(initial);
        activeList.Add(0);
        grid[(int)(initial.x / cellSize), (int)(initial.y / cellSize)] = 0;

        while (activeList.Count > 0)
        {
            int activeIdx = rng.Next(0, activeList.Count);
            var point = points[activeList[activeIdx]];
            bool found = false;

            for (int attempt = 0; attempt < maxAttempts; attempt++)
            {
                float angle = (float)rng.NextDouble() * Mathf.PI * 2f;
                float dist = minDistance + (float)rng.NextDouble() * minDistance;
                var candidate = point + new Vector2(
                    Mathf.Cos(angle) * dist,
                    Mathf.Sin(angle) * dist);

                if (candidate.x < 0 || candidate.x >= width ||
                    candidate.y < 0 || candidate.y >= height)
                    continue;

                int cx = (int)(candidate.x / cellSize);
                int cy = (int)(candidate.y / cellSize);

                if (IsValid(candidate, grid, points, cellSize, minDistance, gridW, gridH))
                {
                    points.Add(candidate);
                    activeList.Add(points.Count - 1);
                    grid[cx, cy] = points.Count - 1;
                    found = true;
                    break;
                }
            }

            if (!found)
                activeList.RemoveAt(activeIdx);
        }

        return points;
    }

    private static bool IsValid(Vector2 candidate, int[,] grid, List<Vector2> points,
        float cellSize, float minDist, int gridW, int gridH)
    {
        int cx = (int)(candidate.x / cellSize);
        int cy = (int)(candidate.y / cellSize);

        for (int x = Mathf.Max(0, cx - 2); x <= Mathf.Min(gridW - 1, cx + 2); x++)
        {
            for (int y = Mathf.Max(0, cy - 2); y <= Mathf.Min(gridH - 1, cy + 2); y++)
            {
                int idx = grid[x, y];
                if (idx >= 0)
                {
                    if (Vector2.Distance(candidate, points[idx]) < minDist)
                        return false;
                }
            }
        }
        return true;
    }
}
```

---

## Difficulty Scaling

Parameterize generation functions so difficulty ramps as the player progresses.

```csharp
[System.Serializable]
public class DungeonDifficultyProfile
{
    public int floorNumber;
    public int minRooms;
    public int maxRooms;
    public float enemyDensity;       // Enemies per room
    public float eliteChance;         // Chance of elite enemy per spawn
    public float trapDensity;
    public LootTable lootTable;       // Better loot tables at higher floors
    public int minRoomSize;
    public int maxRoomSize;
}

public class DungeonGenerator : MonoBehaviour
{
    [SerializeField] private DungeonDifficultyProfile[] difficultyProfiles;

    public DungeonDifficultyProfile GetProfileForFloor(int floor)
    {
        // Find the profile that matches or interpolate between two
        for (int i = difficultyProfiles.Length - 1; i >= 0; i--)
        {
            if (floor >= difficultyProfiles[i].floorNumber)
                return difficultyProfiles[i];
        }
        return difficultyProfiles[0];
    }
}
```

---

## Practical Tips

- **Generate data, then render.** Always separate generation logic (produces an int grid or list of positions) from rendering (applies tiles, spawns prefabs). This makes generation testable without Unity.
- **Validate output.** After generating a dungeon, flood-fill from the entrance to verify all rooms are reachable. If not, regenerate with a different seed.
- **Generation budget.** Complex generation can freeze the game. Run it in a coroutine (yield every N iterations) or on a background thread (for pure math, no Unity API calls).
- **Preview in editor.** Add `[ContextMenu("Generate")]` or a custom editor button to regenerate in edit mode. Fast iteration on generation parameters is essential.
- **Combine techniques.** Use BSP for room layout, random walk for cave-like connectors, noise for decorative detail within rooms, and Poisson disk for object placement.
- **Save the seed, not the map.** If generation is deterministic, you only need to save the seed and floor number to reconstruct the entire level. This keeps save files small.
