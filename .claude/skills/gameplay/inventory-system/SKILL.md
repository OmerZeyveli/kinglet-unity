---
name: inventory-system
description: "Inventory, equipment, and crafting patterns — ScriptableObject item definitions, slot-based inventory, equipment system, crafting recipes, UI binding. Load when implementing item management."
globs: ["**/Inventory*.cs", "**/Item*.cs", "**/Equipment*.cs", "**/Craft*.cs"]
---

# Inventory, Equipment, and Crafting System

Patterns for building a complete item management pipeline: define items as ScriptableObjects, store them in a slot-based inventory, equip gear, craft new items, and bind everything to UI.

## Item Definition (ScriptableObject)

Every item in the game is defined as a ScriptableObject asset. This keeps data out of code, lets designers create items in the editor, and makes save/load straightforward (reference by ID, not by full object).

```csharp
using UnityEngine;

public enum ItemType
{
    Consumable,
    Equipment,
    Material,
    QuestItem,
    Currency
}

public enum EquipmentSlotType
{
    None,
    Head,
    Body,
    Weapon,
    Shield,
    Accessory
}

[CreateAssetMenu(fileName = "New Item", menuName = "Inventory/Item Definition")]
public class ItemDefinition : ScriptableObject
{
    [Header("Identity")]
    public string itemId;           // Unique ID for save/load: "sword_iron_01"
    public string displayName;
    [TextArea(2, 4)]
    public string description;
    public Sprite icon;

    [Header("Stacking")]
    public bool isStackable = true;
    public int maxStackSize = 99;

    [Header("Type")]
    public ItemType itemType;
    public EquipmentSlotType equipSlot = EquipmentSlotType.None;

    [Header("Stats (for equipment)")]
    public int attackBonus;
    public int defenseBonus;
    public int healthBonus;
    public int speedBonus;

    [Header("Usage (for consumables)")]
    public int healAmount;
    public int manaRestoreAmount;

    [Header("Economy")]
    public int buyPrice;
    public int sellPrice;
}
```

**Naming convention for itemId:** Use snake_case with category prefix. Examples: `sword_iron_01`, `potion_health_small`, `mat_wood_plank`. This makes save files human-readable and debugging easier.

### Item Registry

Maintain a central registry so you can look up an `ItemDefinition` by its `itemId`. This is essential for save/load (you save the ID string, then reconstruct the reference on load).

```csharp
using System.Collections.Generic;
using UnityEngine;

[CreateAssetMenu(fileName = "ItemRegistry", menuName = "Inventory/Item Registry")]
public class ItemRegistry : ScriptableObject
{
    [SerializeField] private List<ItemDefinition> allItems;

    private Dictionary<string, ItemDefinition> _lookup;

    public void Initialize()
    {
        _lookup = new Dictionary<string, ItemDefinition>();
        foreach (var item in allItems)
        {
            if (_lookup.ContainsKey(item.itemId))
            {
                Debug.LogWarning($"Duplicate item ID: {item.itemId}");
                continue;
            }
            _lookup[item.itemId] = item;
        }
    }

    public ItemDefinition GetById(string itemId)
    {
        if (_lookup == null) Initialize();
        _lookup.TryGetValue(itemId, out var item);
        return item;
    }
}
```

Load all items into the registry at startup or use `Resources.LoadAll<ItemDefinition>("Items/")` if you prefer automatic discovery over an explicit list.

---

## Inventory Slot

Each slot holds a reference to an item definition and a stack count. Null item means the slot is empty.

```csharp
using System;

[Serializable]
public class InventorySlot
{
    public ItemDefinition item;
    public int count;

    public bool IsEmpty => item == null || count <= 0;

    public InventorySlot()
    {
        item = null;
        count = 0;
    }

    public InventorySlot(ItemDefinition item, int count)
    {
        this.item = item;
        this.count = count;
    }

    public void Clear()
    {
        item = null;
        count = 0;
    }
}
```

---

## Inventory Class

The core inventory: a fixed-size array of slots with add, remove, and query methods. Raises an event whenever contents change so UI can react.

```csharp
using System;
using System.Collections.Generic;
using UnityEngine;

[Serializable]
public class Inventory
{
    [SerializeField] private int maxSlots = 20;
    [SerializeField] private List<InventorySlot> slots;

    public int MaxSlots => maxSlots;
    public IReadOnlyList<InventorySlot> Slots => slots;

    /// <summary>
    /// Fired whenever the inventory contents change.
    /// The int parameter is the slot index that changed (-1 for bulk operations).
    /// </summary>
    public event Action<int> OnChanged;

    public Inventory(int maxSlots)
    {
        this.maxSlots = maxSlots;
        slots = new List<InventorySlot>(maxSlots);
        for (int i = 0; i < maxSlots; i++)
            slots.Add(new InventorySlot());
    }

    /// <summary>
    /// Add an item. Returns the number of items that could NOT be added (overflow).
    /// </summary>
    public int Add(ItemDefinition item, int amount = 1)
    {
        if (item == null || amount <= 0) return amount;

        int remaining = amount;

        // First pass: stack onto existing slots with the same item
        if (item.isStackable)
        {
            for (int i = 0; i < slots.Count && remaining > 0; i++)
            {
                if (slots[i].item == item && slots[i].count < item.maxStackSize)
                {
                    int spaceInSlot = item.maxStackSize - slots[i].count;
                    int toAdd = Mathf.Min(remaining, spaceInSlot);
                    slots[i].count += toAdd;
                    remaining -= toAdd;
                    OnChanged?.Invoke(i);
                }
            }
        }

        // Second pass: place into empty slots
        for (int i = 0; i < slots.Count && remaining > 0; i++)
        {
            if (slots[i].IsEmpty)
            {
                int toAdd = item.isStackable
                    ? Mathf.Min(remaining, item.maxStackSize)
                    : 1;
                slots[i].item = item;
                slots[i].count = toAdd;
                remaining -= toAdd;
                OnChanged?.Invoke(i);
            }
        }

        return remaining; // 0 means everything fit
    }

    /// <summary>
    /// Remove a quantity of an item. Returns the number actually removed.
    /// </summary>
    public int Remove(ItemDefinition item, int amount = 1)
    {
        if (item == null || amount <= 0) return 0;

        int toRemove = amount;

        for (int i = 0; i < slots.Count && toRemove > 0; i++)
        {
            if (slots[i].item == item)
            {
                int removeFromSlot = Mathf.Min(toRemove, slots[i].count);
                slots[i].count -= removeFromSlot;
                toRemove -= removeFromSlot;

                if (slots[i].count <= 0)
                    slots[i].Clear();

                OnChanged?.Invoke(i);
            }
        }

        return amount - toRemove;
    }

    public bool HasItem(ItemDefinition item, int amount = 1)
    {
        return GetCount(item) >= amount;
    }

    public int GetCount(ItemDefinition item)
    {
        int total = 0;
        foreach (var slot in slots)
        {
            if (slot.item == item)
                total += slot.count;
        }
        return total;
    }

    /// <summary>
    /// Swap the contents of two slots (for drag-and-drop rearranging).
    /// </summary>
    public void SwapSlots(int indexA, int indexB)
    {
        if (indexA < 0 || indexA >= slots.Count || indexB < 0 || indexB >= slots.Count) return;

        var temp = new InventorySlot(slots[indexA].item, slots[indexA].count);
        slots[indexA].item = slots[indexB].item;
        slots[indexA].count = slots[indexB].count;
        slots[indexB].item = temp.item;
        slots[indexB].count = temp.count;

        OnChanged?.Invoke(indexA);
        OnChanged?.Invoke(indexB);
    }
}
```

---

## Equipment System

Equipment slots accept only items of the matching `EquipmentSlotType`. Equipping an item removes it from inventory and places it in the equipment slot; unequipping does the reverse.

```csharp
using System;
using System.Collections.Generic;
using UnityEngine;

[Serializable]
public class EquipmentSystem
{
    private Dictionary<EquipmentSlotType, ItemDefinition> _equipped = new();

    public event Action<EquipmentSlotType> OnEquipmentChanged;

    public ItemDefinition GetEquipped(EquipmentSlotType slot)
    {
        _equipped.TryGetValue(slot, out var item);
        return item;
    }

    /// <summary>
    /// Equip an item. Returns the previously equipped item (or null).
    /// Caller is responsible for moving items to/from inventory.
    /// </summary>
    public ItemDefinition Equip(ItemDefinition item)
    {
        if (item == null || item.equipSlot == EquipmentSlotType.None)
            return null;

        _equipped.TryGetValue(item.equipSlot, out var previous);
        _equipped[item.equipSlot] = item;

        OnEquipmentChanged?.Invoke(item.equipSlot);
        return previous;
    }

    public ItemDefinition Unequip(EquipmentSlotType slot)
    {
        if (!_equipped.TryGetValue(slot, out var item)) return null;

        _equipped.Remove(slot);
        OnEquipmentChanged?.Invoke(slot);
        return item;
    }

    /// <summary>
    /// Sum up all stat bonuses from equipped items.
    /// </summary>
    public (int attack, int defense, int health, int speed) GetTotalBonuses()
    {
        int atk = 0, def = 0, hp = 0, spd = 0;
        foreach (var kvp in _equipped)
        {
            if (kvp.Value == null) continue;
            atk += kvp.Value.attackBonus;
            def += kvp.Value.defenseBonus;
            hp += kvp.Value.healthBonus;
            spd += kvp.Value.speedBonus;
        }
        return (atk, def, hp, spd);
    }
}
```

---

## Crafting System

Crafting recipes are ScriptableObjects that list required ingredients and the resulting item.

```csharp
using UnityEngine;

[System.Serializable]
public struct CraftingIngredient
{
    public ItemDefinition item;
    public int count;
}

[CreateAssetMenu(fileName = "New Recipe", menuName = "Inventory/Crafting Recipe")]
public class CraftingRecipe : ScriptableObject
{
    public string recipeName;
    public CraftingIngredient[] ingredients;
    public ItemDefinition result;
    public int resultCount = 1;

    public bool CanCraft(Inventory inventory)
    {
        foreach (var ingredient in ingredients)
        {
            if (!inventory.HasItem(ingredient.item, ingredient.count))
                return false;
        }
        return true;
    }

    /// <summary>
    /// Attempt to craft. Returns true if successful.
    /// </summary>
    public bool Craft(Inventory inventory)
    {
        if (!CanCraft(inventory)) return false;

        // Check if result would fit
        // (simplified: in production, you would do a dry-run add check)

        // Remove ingredients
        foreach (var ingredient in ingredients)
        {
            inventory.Remove(ingredient.item, ingredient.count);
        }

        // Add result
        int overflow = inventory.Add(result, resultCount);
        if (overflow > 0)
        {
            Debug.LogWarning($"Crafting overflow: {overflow} x {result.displayName} did not fit.");
            // In production, drop overflow items on the ground or revert the craft
        }

        return true;
    }
}
```

---

## UI Binding

Use the observer pattern: inventory raises `OnChanged`, UI subscribes and refreshes the affected slot.

```csharp
using UnityEngine;
using UnityEngine.UI;
using TMPro;

public class InventoryUI : MonoBehaviour
{
    [SerializeField] private Transform slotContainer;
    [SerializeField] private GameObject slotPrefab;

    private Inventory _inventory;
    private InventorySlotUI[] _slotUIs;

    public void Bind(Inventory inventory)
    {
        // Unsubscribe from previous
        if (_inventory != null)
            _inventory.OnChanged -= RefreshSlot;

        _inventory = inventory;
        _inventory.OnChanged += RefreshSlot;

        RebuildAllSlots();
    }

    private void OnDestroy()
    {
        if (_inventory != null)
            _inventory.OnChanged -= RefreshSlot;
    }

    private void RebuildAllSlots()
    {
        // Clear existing
        foreach (Transform child in slotContainer)
            Destroy(child.gameObject);

        _slotUIs = new InventorySlotUI[_inventory.MaxSlots];

        for (int i = 0; i < _inventory.MaxSlots; i++)
        {
            var go = Instantiate(slotPrefab, slotContainer);
            _slotUIs[i] = go.GetComponent<InventorySlotUI>();
            _slotUIs[i].SetSlotIndex(i);
            RefreshSlot(i);
        }
    }

    private void RefreshSlot(int index)
    {
        if (index < 0 || index >= _slotUIs.Length) return;

        var slot = _inventory.Slots[index];
        _slotUIs[index].UpdateDisplay(slot.item, slot.count);
    }
}
```

### Slot UI Component

```csharp
using UnityEngine;
using UnityEngine.UI;
using TMPro;

public class InventorySlotUI : MonoBehaviour
{
    [SerializeField] private Image iconImage;
    [SerializeField] private TextMeshProUGUI countText;
    [SerializeField] private GameObject countBackground;

    private int _slotIndex;

    public void SetSlotIndex(int index) => _slotIndex = index;

    public void UpdateDisplay(ItemDefinition item, int count)
    {
        if (item == null)
        {
            iconImage.enabled = false;
            countBackground.SetActive(false);
            return;
        }

        iconImage.enabled = true;
        iconImage.sprite = item.icon;

        bool showCount = item.isStackable && count > 1;
        countBackground.SetActive(showCount);
        if (showCount)
            countText.text = count.ToString();
    }
}
```

---

## Drag and Drop

For UGUI-based drag and drop, implement the drag handler interfaces on the slot UI.

```csharp
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

public class InventorySlotDragHandler : MonoBehaviour,
    IBeginDragHandler, IDragHandler, IEndDragHandler, IDropHandler
{
    private Canvas _canvas;
    private RectTransform _rectTransform;
    private CanvasGroup _canvasGroup;
    private Transform _originalParent;
    private int _slotIndex;

    private static InventorySlotDragHandler _draggingSlot;

    private void Awake()
    {
        _rectTransform = GetComponent<RectTransform>();
        _canvasGroup = GetComponent<CanvasGroup>();
        _canvas = GetComponentInParent<Canvas>();
    }

    public void OnBeginDrag(PointerEventData eventData)
    {
        _draggingSlot = this;
        _canvasGroup.blocksRaycasts = false; // Allow drop targets to receive events
        _canvasGroup.alpha = 0.6f;
        _originalParent = transform.parent;
        transform.SetParent(_canvas.transform); // Move to top of canvas
    }

    public void OnDrag(PointerEventData eventData)
    {
        _rectTransform.anchoredPosition += eventData.delta / _canvas.scaleFactor;
    }

    public void OnEndDrag(PointerEventData eventData)
    {
        _canvasGroup.blocksRaycasts = true;
        _canvasGroup.alpha = 1f;
        transform.SetParent(_originalParent);
        transform.localPosition = Vector3.zero;
        _draggingSlot = null;
    }

    public void OnDrop(PointerEventData eventData)
    {
        if (_draggingSlot == null || _draggingSlot == this) return;

        // Tell the inventory to swap the two slots
        // (access the inventory through a manager or event)
        InventoryManager.Instance.SwapSlots(_draggingSlot._slotIndex, _slotIndex);
    }
}
```

---

## Item Pickup

Place pickup objects in the world with a trigger collider. When the player enters, add the item to their inventory and destroy the pickup.

```csharp
using UnityEngine;

[RequireComponent(typeof(Collider2D))]
public class ItemPickup : MonoBehaviour
{
    [SerializeField] private ItemDefinition item;
    [SerializeField] private int amount = 1;
    [SerializeField] private bool destroyOnPickup = true;

    private void OnTriggerEnter2D(Collider2D other)
    {
        if (!other.CompareTag("Player")) return;

        var playerInventory = other.GetComponent<PlayerInventoryHolder>();
        if (playerInventory == null) return;

        int overflow = playerInventory.Inventory.Add(item, amount);

        if (overflow == 0 && destroyOnPickup)
        {
            Destroy(gameObject);
        }
        else if (overflow > 0 && overflow < amount)
        {
            // Partially picked up
            amount = overflow;
        }
        // If overflow == amount, inventory was full; do nothing
    }
}
```

---

## Save/Load Integration

Serialize inventory as a list of (itemId, count) pairs. On load, look up each ID in the ItemRegistry to reconstruct the ScriptableObject references.

```csharp
[System.Serializable]
public struct InventorySaveData
{
    public string[] itemIds;
    public int[] counts;
}

// In your save logic:
public InventorySaveData CaptureInventory(Inventory inventory)
{
    var data = new InventorySaveData
    {
        itemIds = new string[inventory.MaxSlots],
        counts = new int[inventory.MaxSlots]
    };

    for (int i = 0; i < inventory.MaxSlots; i++)
    {
        var slot = inventory.Slots[i];
        data.itemIds[i] = slot.IsEmpty ? "" : slot.item.itemId;
        data.counts[i] = slot.count;
    }

    return data;
}

// In your load logic:
public void RestoreInventory(Inventory inventory, InventorySaveData data, ItemRegistry registry)
{
    for (int i = 0; i < data.itemIds.Length; i++)
    {
        if (string.IsNullOrEmpty(data.itemIds[i])) continue;

        var item = registry.GetById(data.itemIds[i]);
        if (item == null)
        {
            Debug.LogWarning($"Item ID not found in registry: {data.itemIds[i]}");
            continue;
        }

        inventory.Add(item, data.counts[i]);
    }
}
```

---

## Practical Tips

- **Keep ItemDefinition lightweight.** Put runtime-only state (durability, enchantments) in a separate `ItemInstance` wrapper class, not on the SO itself. SOs are shared assets; modifying them at runtime changes every reference.
- **Use enums sparingly for item types.** If your game has many item categories, consider a tag-based system (List<string> tags) instead of a rigid enum.
- **Tooltip system:** Create a generic tooltip that reads `displayName` and `description` from any `ItemDefinition` on hover. Use `IPointerEnterHandler` / `IPointerExitHandler`.
- **Sort inventory** by type, then by name: `slots.OrderBy(s => s.item?.itemType).ThenBy(s => s.item?.displayName)`.
- **Inventory full feedback:** Play a sound or flash the UI when the player tries to pick up an item but the inventory is full. Silent failure feels like a bug.
- **Item rarity:** Add a `Rarity` enum (Common, Uncommon, Rare, Epic, Legendary) and a color mapping. Tint the slot border or item name in UI.
