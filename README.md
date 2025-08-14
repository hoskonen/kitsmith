# KitSmith

KitSmith is a **Kingdom Come: Deliverance II** quality-of-life mod that automatically consolidates your repair kits so your inventory stays clean and organized.

## 📜 Overview

The idea originated from discussions in the community (credit to **jigsawpizzle** and **Actalo**).  
In vanilla gameplay, repairing your gear often leaves you with **half-used kits** that clutter your inventory.  
KitSmith automatically scans your inventory and **merges them whenever possible**.

> For hardcore immersion, consider pairing this mod with **Veteran Repair Kits**.

---

## ⚙ How It Works

### Consolidation Logic
1. **Trigger**  
   - **Sleep Mode** *(default)*: Consolidation happens when you wake from sleep.  
   - **Live Mode** *(optional)*: Consolidation runs every X seconds (default: 20s).
   
2. **Grouping**  
   Kits of the same type (blacksmith, cobbler, tailor, weapon, etc.) are grouped together.

3. **Pooling**  
   The total durability (`health`) of each kit type is summed.

4. **Redistribution**  
   - Every **1.0 health** → 1 full kit.  
   - Remaining fraction → 1 partial kit (if any).  

**Result:** Neat stacks of full kits with at most one partial kit per type. **No durability is lost**.

---

## 📂 File Structure

