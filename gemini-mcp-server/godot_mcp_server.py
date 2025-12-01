#!/usr/bin/env python3
"""
Godot MCP Server v5 - Complete Suite (Nodes, Scenes, Filesystem, Terrain3D)
Umožňuje komplexní ovládání Godot Editoru přes Model Context Protocol.
"""

import asyncio
import json
import logging
import os
from typing import Any
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

# Nastavení logování
log_file_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'server_debug.log')
logging.basicConfig(level=logging.INFO, filename=log_file_path, filemode='w', encoding='utf-8')
logger = logging.getLogger("godot-mcp")

# Konfigurace Godot připojení
GODOT_HOST = "localhost"
GODOT_PORT = 4242
# Zvýšený timeout pro operace jako 'bake_mesh' nebo načítání velkých scén
TIMEOUT = 15.0  

# Vytvoření MCP serveru
app = Server("godot-editor")


async def send_godot_command(command: dict) -> dict:
    """
    Asynchronně odešle příkaz na Godot TCP server a čeká na odpověď.
    """
    try:
        # Připojení k socketu
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(GODOT_HOST, GODOT_PORT),
            timeout=TIMEOUT
        )
        
        # Odeslání příkazu
        json_data = json.dumps(command)
        writer.write(json_data.encode('utf-8'))
        await writer.drain()
        
        # Příjem odpovědi
        response_data = b""
        try:
            while True:
                # Čteme po větších částech (4KB) kvůli potenciálně dlouhým výpisům souborů
                chunk = await asyncio.wait_for(reader.read(4096), timeout=5.0)
                if not chunk:
                    break
                response_data += chunk
                
                # Pokusíme se parsovat JSON průběžně (pokud přijde v jednom chunku)
                try:
                    json.loads(response_data.decode('utf-8'))
                    break
                except json.JSONDecodeError:
                    continue
        except asyncio.TimeoutError:
            pass # Pokud vyprší čas na čtení chunku, předpokládáme, že máme vše
        
        writer.close()
        await writer.wait_closed()
        
        if response_data:
            try:
                return json.loads(response_data.decode('utf-8'))
            except json.JSONDecodeError:
                return {"status": "error", "message": "Neplatná odpověď od Godot serveru (JSON Error)"}
        else:
            return {"status": "error", "message": "Žádná odpověď od serveru"}
            
    except asyncio.TimeoutError:
        return {"status": "error", "message": "Timeout - Godot server neodpovídá"}
    except ConnectionRefusedError:
        return {"status": "error", "message": "Nelze se připojit - je Godot plugin aktivní a naslouchá na portu 4242?"}
    except Exception as e:
        logger.error(f"Chyba komunikace: {e}")
        return {"status": "error", "message": f"Chyba komunikace: {str(e)}"}


@app.list_tools()
async def list_tools() -> list[Tool]:
    """
    Definuje seznam všech dostupných nástrojů pro Gemini CLI.
    """
    return [
        # ====================================================================
        # ZÁKLADNÍ PRÁCE S UZLY (NODE OPERATIONS)
        # ====================================================================
        Tool(
            name="godot_search_files",
            description="Vyhledá soubory v projektu podle názvu nebo přípony. POUŽIJTE PŘED VYTVÁŘENÍM NOVÝCH SOUBORŮ pro ověření existence nebo pro nalezení assets (textury, modely, skripty).",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Hledaný text v názvu souboru (např. 'player', 'grass'). Prázdné = vše."},
                    "extensions": {"type": "array", "items": {"type": "string"}, "description": "Filtr přípon (např. ['.gd', '.tscn', '.png'])"},
                    "root": {"type": "string", "default": "res://", "description": "Kde začít hledat"}
                }
            }
        ),
        Tool(
            name="godot_create_node",
            description="Vytvoří nový node v aktivní scéně Godot Editoru.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_type": {
                        "type": "string",
                        "description": "Typ node (např. 'Node3D', 'MeshInstance3D', 'Camera3D', 'DirectionalLight3D')"
                    },
                    "name": {
                        "type": "string",
                        "description": "Název nového node"
                    },
                    "parent_path": {
                        "type": "string",
                        "description": "Cesta k parent node (prázdné = root scény)",
                        "default": ""
                    }
                },
                "required": ["node_type", "name"]
            }
        ),
        Tool(
            name="godot_set_property",
            description="Nastaví vlastnost existujícího node.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Cesta k node (např. 'Player/Camera')"
                    },
                    "property_name": {
                        "type": "string",
                        "description": "Název vlastnosti (position, rotation, scale, visible, mesh...)"
                    },
                    "value": {
                        "description": "Hodnota - číslo, seznam [x,y,z], boolean, string"
                    }
                },
                "required": ["node_path", "property_name", "value"]
            }
        ),
        Tool(
            name="godot_reparent_node",
            description="Přesune node pod jiného rodiče (Reparent).",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k node, který se má přesunout"},
                    "new_parent_path": {"type": "string", "description": "Cesta k novému rodiči"},
                    "keep_global_transform": {"type": "boolean", "description": "Zachovat globální pozici?", "default": True}
                },
                "required": ["node_path", "new_parent_path"]
            }
        ),
        Tool(
            name="godot_duplicate_node",
            description="Duplikuje existující node.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k originálnímu node"},
                    "new_name": {"type": "string", "description": "Název pro kopii (volitelné)"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="godot_delete_node",
            description="Smaže node ze scény.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k node"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="godot_rename_node",
            description="Přejmenuje node.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Stará cesta/název"},
                    "new_name": {"type": "string", "description": "Nový název"}
                },
                "required": ["node_path", "new_name"]
            }
        ),
        Tool(
            name="godot_get_node_info",
            description="Získá detailní informace o konkrétním node (pozice, děti, skupiny, připojený skript).",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k node"}
                },
                "required": ["node_path"]
            }
        ),

        # ====================================================================
        # PRÁCE SE SCÉNAMI (SCENE MANAGEMENT)
        # ====================================================================
        Tool(
            name="godot_get_scene_tree",
            description="Získá kompletní strukturu aktuální scény jako JSON strom.",
            inputSchema={"type": "object", "properties": {}}
        ),
        Tool(
            name="godot_save_scene",
            description="Uloží aktuální scénu. BEZPEČNOSTNÍ FUNKCE: Pokud zadáte 'save_path' a soubor již existuje, systém ho nepřepíše, ale automaticky vytvoří kopii s číselným suffixem (např. level_1.tscn).",
            inputSchema={
                "type": "object",
                "properties": {
                    "save_path": {
                        "type": "string", 
                        "description": "Cesta pro uložení (res://scenes/level.tscn). Pokud necháte prázdné, přepíše se aktuálně otevřený soubor bez změny názvu.", 
                        "default": ""
                    }
                }
            }
        ),
        Tool(
            name="godot_create_scene",
            description="Vytvoří zcela novou scénu a otevře ji v editoru.",
            inputSchema={
                "type": "object",
                "properties": {
                    "save_path": {"type": "string", "description": "Cesta pro uložení (např. res://scenes/NewLevel.tscn)"},
                    "root_type": {"type": "string", "description": "Typ root node", "default": "Node3D"},
                    "name": {"type": "string", "description": "Název root node", "default": "SceneRoot"}
                },
                "required": ["save_path"]
            }
        ),
        Tool(
            name="godot_load_scene",
            description="Otevře existující scénu v editoru.",
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Cesta k souboru .tscn"}
                },
                "required": ["path"]
            }
        ),
        Tool(
            name="godot_add_child_scene",
            description="Instanciuje jinou scénu (.tscn) jako potomka do aktuální scény.",
            inputSchema={
                "type": "object",
                "properties": {
                    "scene_path": {"type": "string", "description": "Cesta k souboru scény (res://...)"},
                    "parent_path": {"type": "string", "description": "Kam přidat (prázdné = root scény)"},
                    "name": {"type": "string", "description": "Název instance (volitelné)"}
                },
                "required": ["scene_path"]
            }
        ),
        Tool(
            name="godot_fix_ownership",
            description="Opraví vlastnictví node (Owner) rekurzivně. DŮLEŽITÉ volat před uložením scény, pokud jste vytvářeli složitější strukturu skriptem.",
            inputSchema={
                "type": "object",
                "properties": {
                    "root_path": {"type": "string", "description": "Cesta k uzlu, od kterého se má opravit vlastnictví"}
                },
                "required": ["root_path"]
            }
        ),

        Tool(
            name="godot_env_create",
            description="Vytvoří WorldEnvironment (pokud neexistuje) a inicializuje v něm Environment a CameraAttributesPractical.",
            inputSchema={"type": "object", "properties": {}}
        ),
        Tool(
            name="godot_env_set_background",
            description="Nastaví pozadí scény (Obloha, Barva).",
            inputSchema={
                "type": "object",
                "properties": {
                    "mode": {"type": "string", "enum": ["clear_color", "custom_color", "sky", "canvas"], "description": "Typ pozadí."},
                    "color": {"type": "array", "items": {"type": "number"}, "description": "[r, g, b] pro custom_color"},
                    "energy": {"type": "number", "description": "Multiplikátor energie (jasu). Default: 1.0"}
                },
                "required": ["mode"]
            }
        ),
        Tool(
            name="godot_env_set_effect",
            description="Pokročilá konfigurace efektů Environment.",
            inputSchema={
                "type": "object",
                "properties": {
                    "effect_type": {
                        "type": "string",
                        "enum": ["tonemap", "glow", "fog", "volumetric_fog", "ssao", "ssil", "sdfgi", "adjustment"],
                        "description": "Kterou sekci Environmentu upravit."
                    },
                    "enabled": {"type": "boolean", "description": "Zapnout/Vypnout efekt (netýká se tonemap)."},
                    "params": {
                        "type": "object",
                        "description": "Klíč-hodnota dle dokumentace Godot.\nGlow: intensity, strength, bloom, blend_mode (0-4)\nFog: density, light_color, sun_scatter, height_density\nVolumetricFog: density, albedo, emission, length\nSSAO: radius, intensity, power, detail\nSDFGI: bounce_feedback, cascades, min_cell_size\nAdjustment: brightness, contrast, saturation\nTonemap: mode (0=Linear, 2=Filmic, 3=ACES), exposure, white"
                    }
                },
                "required": ["effect_type"]
            }
        ),
        Tool(
            name="godot_env_camera_attributes",
            description="Nastaví CameraAttributes (Expozice, Auto-Exposure).",
            inputSchema={
                "type": "object",
                "properties": {
                    "auto_exposure": {"type": "boolean", "description": "Zapnout automatickou expozici?"},
                    "exposure_multiplier": {"type": "number", "description": "Základní jas (Default 1.0)"},
                    "exposure_sensitivity": {"type": "number", "description": "ISO citlivost (Default 100.0)"},
                    "auto_exposure_speed": {"type": "number", "description": "Rychlost adaptace oka (Default 0.5)"},
                    "auto_exposure_scale": {"type": "number", "description": "Škála efektu (Default 0.4)"}
                }
            }
        ),

        # ====================================================================
        # MESH A FYZIKA (MESH & PHYSICS)
        # ====================================================================
        Tool(
            name="godot_set_mesh",
            description="Vytvoří a nastaví Mesh (tvar) pro MeshInstance3D.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k MeshInstance3D"},
                    "mesh_type": {"type": "string", "description": "BoxMesh, SphereMesh, CapsuleMesh, CylinderMesh, PlaneMesh, PrismMesh, TorusMesh"},
                    "params": {
                        "type": "object",
                        "description": "Parametry meshe (např. size=[1,1,1], radius=1.0, height=2.0...)"
                    }
                },
                "required": ["node_path", "mesh_type"]
            }
        ),
        Tool(
            name="godot_add_collision_shape",
            description="Přidá CollisionShape a nastaví mu tvar. Automaticky vytvoří node i shape.",
            inputSchema={
                "type": "object",
                "properties": {
                    "parent_path": {"type": "string", "description": "Rodič (např. RigidBody3D, StaticBody3D, Area3D)"},
                    "shape_type": {"type": "string", "description": "BoxShape3D, SphereShape3D, CapsuleShape3D, CylinderShape3D, RectangleShape2D..."},
                    "params": {"type": "object", "description": "Parametry (size, radius, height)"},
                    "name": {"type": "string", "default": "CollisionShape"}
                },
                "required": ["parent_path", "shape_type"]
            }
        ),
        Tool(
            name="godot_get_collision_layers",
            description="Vrátí mapu nastavených fyzikálních vrstev (Physics Layers).",
            inputSchema={
                "type": "object",
                "properties": {
                    "type": {"type": "string", "enum": ["2D", "3D"], "default": "3D", "description": "Typ fyziky (2D nebo 3D)."}
                }
            }
        ),
        Tool(
            name="godot_set_collision_layer_name",
            description="Přejmenuje, vytvoří nebo smaže název fyzikální vrstvy v Project Settings.",
            inputSchema={
                "type": "object",
                "properties": {
                    "index": {"type": "integer", "minimum": 1, "maximum": 32, "description": "Číslo vrstvy (1-32)."},
                    "name": {"type": "string", "description": "Nový název vrstvy. Pro smazání/resetování nechte prázdné."},
                    "type": {"type": "string", "enum": ["2D", "3D"], "default": "3D"}
                },
                "required": ["index", "name"]
            }
        ),
        Tool(
            name="godot_set_physics_layer",
            description="Nastaví Collision Layer nebo Mask na konkrétním node.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k node"},
                    "type": {"type": "string", "description": "'layer' (objekt je v této vrstvě) nebo 'mask' (objekt skenuje tuto vrstvu)"},
                    "layer_index": {"type": "integer", "description": "Číslo vrstvy (1-32)"},
                    "enabled": {"type": "boolean", "description": "Zapnout (True) nebo vypnout (False)", "default": True}
                },
                "required": ["node_path", "type", "layer_index"]
            }
        ),

# ====================================================================
        # SOUBOROVÝ SYSTÉM (FILESYSTEM)
        # ====================================================================
        Tool(
            name="godot_list_files",
            description="Vypíše soubory a složky v zadané cestě. Užitečné pro nalezení assets (.obj, .png, .tscn) nebo kontrolu struktury projektu.",
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Cesta (res://...)", "default": "res://"},
                    "recursive": {"type": "boolean", "description": "Prohledat i podsložky?", "default": False},
                    "extensions": {"type": "array", "items": {"type": "string"}, "description": "Filtr přípon (např. ['.tscn', '.gd', '.tres'])"}
                }
            }
        ),
        Tool(
            name="godot_make_directory",
            description="Vytvoří novou složku (vytváří i chybějící rodičovské složky).",
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Cesta nové složky (res://assets/models)"}
                },
                "required": ["path"]
            }
        ),
        Tool(
            name="godot_manage_file",
            description="Přejmenuje, přesune nebo smaže soubor či složku.",
            inputSchema={
                "type": "object",
                "properties": {
                    "action": {"type": "string", "enum": ["rename", "move", "delete"], "description": "Akce, kterou chcete provést"},
                    "path": {"type": "string", "description": "Cesta k souboru/složce"},
                    "new_path": {"type": "string", "description": "Nová cesta (pouze pro rename/move)"}
                },
                "required": ["action", "path"]
            }
        ),

        # ====================================================================
        # TERRAIN 3D (PLUGIN INTEGRATION)
        # ====================================================================
        Tool(
            name="godot_terrain_create",
            description="Vytvoří Terrain3D (v1.0+). POZOR: Parametr 'storage_path' je povinný pro správné ukládání dat.",
            inputSchema={
                "type": "object",
                "properties": {
                    "name": {"type": "string", "default": "Terrain3D"},
                    "parent_path": {"type": "string"},
                    "storage_path": {
                        "type": "string",
                        "description": "Cesta k ADRESÁŘI pro data (např. res://terrain_data). MUSÍ BÝT VYPLNĚNO.",
                        "default": "res://terrain_data"
                    }
                },
                "required": ["storage_path"]
            }
        ),
	Tool(
            name="godot_terrain_import_heightmap",
            description="Importuje obrázek (PNG/EXR/RAW) jako heightmapu do Terrain3D. Modifikuje výšku terénu na dané pozici.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k Terrain3D uzlu"},
                    "file_path": {"type": "string", "description": "Absolutní cesta k obrázku (res://...)"},
                    "min_height": {"type": "number", "description": "Nejnižší bod (černá barva). Default: 0.0", "default": 0.0},
                    "max_height": {"type": "number", "description": "Nejvyšší bod (bílá barva). Default: 100.0", "default": 100.0},
                    "position": {
                        "type": "array", 
                        "items": {"type": "number"},
                        "description": "Pozice [x, y, z] kde se má heightmapa aplikovat. Default: [0,0,0]",
                        "default": [0, 0, 0]
                    }
                },
                "required": ["node_path", "file_path"]
            }
        ),
        Tool(
            name="godot_terrain_configure",
            description="Konfiguruje hlavní parametry terénu (velikost, LOD, mezery mezi vertexy).",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k Terrain3D"},
                    "vertex_spacing": {"type": "number", "description": "Vzdálenost mezi vrcholy (škálování terénu). Default: 1.0"},
                    "mesh_size": {"type": "integer", "description": "Velikost meshe (kvalita). Default: 48"},
                    "mesh_lods": {"type": "integer", "description": "Počet LOD úrovní. Default: 7"},
                    "region_size": {"type": "integer", "description": "Velikost regionu (64, 128, 256, 512, 1024). Default: 256"},
                    "cull_margin": {"type": "number", "description": "Extra margin pro vykreslování"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="godot_terrain_physics",
            description="Nastavuje kolize a fyziku pro Terrain3D.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k Terrain3D"},
                    "collision_enabled": {"type": "boolean", "description": "Zapnout/vypnout kolize"},
                    "layer": {"type": "integer", "description": "Collision Layer (bitmask hodnota)"},
                    "mask": {"type": "integer", "description": "Collision Mask (bitmask hodnota)"},
                    "priority": {"type": "number", "description": "Priorita kolize. Default: 1.0"},
                    "radius": {"type": "integer", "description": "Collision Radius. Default: 64"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="godot_terrain_rendering",
            description="Nastavuje renderovací vlastnosti terénu (stíny, GI).",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k Terrain3D"},
                    "cast_shadows": {"type": "integer", "description": "0=Off, 1=On, 2=DoubleSided, 3=ShadowsOnly. Default: 1"},
                    "gi_mode": {"type": "integer", "description": "0=Disabled, 1=Static, 2=Dynamic. Default: 1"},
                    "render_layers": {"type": "integer", "description": "Visual Layers (bitmask). Default: 1"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="godot_terrain_task",
            description="Spustí pokročilý Import/Export úkol pro Terrain3D (Heightmapy, ColorMapy, RAW/R16).",
            inputSchema={
                "type": "object",
                "properties": {
                    "task_type": {"type": "string", "enum": ["import", "export"]},
                    "map_type": {"type": "string", "enum": ["height", "color", "control"], "description": "Typ mapy."},
                    "file_path": {"type": "string", "description": "Cesta k souboru (res://... nebo absolutní C:/...)"},
                    "data_dir": {"type": "string", "description": "Složka s daty terénu (res://terrain_data)."},
                    "params": {
                        "type": "object",
                        "description": "Parametry pro import/export.\nImport: position [x,y,z], scale, offset, min_height, max_height, r16_dim [w,h]\nExport: (žádné speciální parametry)"
                    }
                },
                "required": ["task_type", "map_type", "file_path", "data_dir"]
            }
        ),
        Tool(
            name="godot_terrain_add_texture",
            description="Přidá sadu textur (Albedo + Normal) do palety terénu.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string"},
                    "name": {"type": "string", "description": "Název pro identifikaci (např. 'Grass_Green')"},
                    "albedo_path": {"type": "string", "description": "Cesta k albedo textuře"},
                    "normal_path": {"type": "string", "description": "Cesta k normal mapě (volitelné)"},
                    "uv_scale": {"type": "number", "default": 1.0}
                },
                "required": ["node_path", "albedo_path"]
            }
        ),
        Tool(
            name="godot_terrain_add_mesh",
            description="Registruje 3D model (strom, kámen, tráva) do systému terénu pro pozdější instancování.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string"},
                    "mesh_path": {"type": "string", "description": "Cesta k .obj, .glb, .tscn souboru"},
                    "name": {"type": "string", "description": "Název (např. 'PineTree')"},
                    "scale_variance": {"type": "number", "default": 0.2, "description": "Náhodná variace velikosti"}
                },
                "required": ["node_path", "mesh_path"]
            }
        ),
        Tool(
            name="godot_terrain_place_instances",
            description="Rozmístí instance (stromy/trávu) na terén na zadané souřadnice.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string"},
                    "mesh_id": {"type": "integer", "description": "ID meshu (vráceno z add_mesh, startuje od 0)"},
                    "positions": {
                        "type": "array",
                        "items": {"type": "array", "items": {"type": "number"}},
                        "description": "Seznam pozic [[x,y,z], [x,y,z], ...]"
                    },
                    "auto_height": {"type": "boolean", "default": True, "description": "Automaticky přichytit k zemi (ignoruje Y v pozici)"}
                },
                "required": ["node_path", "mesh_id", "positions"]
            }
        ),
        Tool(
            name="godot_terrain_bake_navmesh",
            description="Vypeče Navigační Mesh pro terén (umožní AI agentům chodit).",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="godot_terrain_raycast",
            description="Zjistí výšku a pozici na terénu (Physics-free raycast).",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string"},
                    "x": {"type": "number"},
                    "z": {"type": "number"}
                },
                "required": ["node_path", "x", "z"]
            }
        ),
        Tool(
            name="godot_2d_create",
            description="Vytvoří 2D uzel (Sprite2D, Node2D, Label, Control).",
            inputSchema={
                "type": "object",
                "properties": {
                    "type": {"type": "string", "description": "Typ uzlu (např. Sprite2D, Label, Node2D)"},
                    "name": {"type": "string"},
                    "parent_path": {"type": "string"},
                    "position": {"type": "array", "items": {"type": "number"}, "description": "[x, y]"},
                    "texture_path": {"type": "string", "description": "Pouze pro Sprite2D: cesta k obrázku"},
                    "text": {"type": "string", "description": "Pouze pro Label/Button: text"}
                },
                "required": ["type", "name"]
            }
        ),
        Tool(
            name="godot_2d_transform",
            description="Nastaví pozici, rotaci a měřítko pro 2D uzel.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string"},
                    "position": {"type": "array", "items": {"type": "number"}, "description": "[x, y]"},
                    "rotation": {"type": "number", "description": "Úhel ve stupních"},
                    "scale": {"type": "array", "items": {"type": "number"}, "description": "[x, y]"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="godot_terrain_visuals",
            description="Ovládá vizuální debugování terénu (mřížky, wireframe, heightmapy).",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k Terrain3D"},
                    "show_grid": {"type": "boolean", "description": "Zobrazit mřížku regionů"},
                    "show_instances": {"type": "boolean", "description": "Zobrazit instancované meshe"},
                    "show_heightmap": {"type": "boolean", "description": "Debug zobrazení heightmapy"},
                    "show_colormap": {"type": "boolean", "description": "Debug zobrazení colormapy"},
                    "debug_level": {"type": "integer", "description": "0=Errors, 1=Info, 2=Debug, 3=Extreme"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="godot_terrain_bake_mesh",
            description="Vypeče terén do statického ArrayMesh (pro navmesh nebo export).",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k Terrain3D"},
                    "lod": {"type": "integer", "description": "Úroveň detailu (0-8). Default: 4"},
                    "save_path": {"type": "string", "description": "Cesta pro uložení .res souboru (např. res://terrain_mesh.res)"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="godot_terrain_get_height",
            description="Získá výšku terénu na dané pozici (X, Z).",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k Terrain3D"},
                    "x": {"type": "number", "description": "Souřadnice X"},
                    "z": {"type": "number", "description": "Souřadnice Z"}
                },
                "required": ["node_path", "x", "z"]
            }
        ),

        # ====================================================================
        # PRÁCE SE SKRIPTY (SCRIPTING)
        # ====================================================================
        Tool(
            name="godot_create_script",
            description="Vytvoří nový skript. POZOR: Pokud soubor existuje, systém automaticky vytvoří unikátní název (např. script_1.gd), pokud není nastaveno overwrite=True.",
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "content": {"type": "string"},
                    "overwrite": {"type": "boolean", "description": "Pokud True, přepíše existující soubor. Pokud False (default), vytvoří nový název.", "default": False}
                },
                "required": ["path", "content"]
            }
        ),
        Tool(
            name="godot_read_script",
            description="Přečte obsah existujícího skriptu.",
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Cesta k souboru (res://...)"}
                },
                "required": ["path"]
            }
        ),
        Tool(
            name="godot_attach_script",
            description="Připojí existující skript k nodu.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k node"},
                    "script_path": {"type": "string", "description": "Cesta ke skriptu (res://...)"}
                },
                "required": ["node_path", "script_path"]
            }
        ),
        Tool(
            name="godot_detach_script",
            description="Odpojí skript od nodu.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Cesta k node"}
                },
                "required": ["node_path"]
            }
        )
    ]


@app.call_tool()
async def call_tool(name: str, arguments: Any) -> list[TextContent]:
    """
    Zpracovává volání nástrojů z Gemini a převádí je na příkazy pro Godot TCP server.
    """
    try:
        logger.info(f"Volání nástroje: {name} | Argumenty: {arguments}")
        
        command = {}

        # --- NODE OPS ---
        if name == "godot_create_node":
            command = {"cmd": "create_node", "type": arguments.get("node_type"), "name": arguments.get("name"), "parent": arguments.get("parent_path", "")}
        elif name == "godot_set_property":
            command = {"cmd": "set_prop", "path": arguments.get("node_path"), "prop": arguments.get("property_name"), "val": arguments.get("value")}
        elif name == "godot_reparent_node":
            command = {"cmd": "reparent_node", "path": arguments.get("node_path"), "new_parent": arguments.get("new_parent_path"), "keep_global_transform": arguments.get("keep_global_transform", True)}
        elif name == "godot_duplicate_node":
            command = {"cmd": "duplicate_node", "path": arguments.get("node_path"), "name": arguments.get("new_name", "")}
        elif name == "godot_rename_node":
            command = {"cmd": "rename_node", "path": arguments.get("node_path"), "new_name": arguments.get("new_name")}
        elif name == "godot_delete_node":
            command = {"cmd": "delete_node", "path": arguments.get("node_path")}
        elif name == "godot_get_node_info":
            command = {"cmd": "get_node_info", "path": arguments.get("node_path")}

        # --- SCENE OPS ---
        elif name == "godot_get_scene_tree":
            command = {"cmd": "get_scene_tree"}
        elif name == "godot_save_scene":
            command = {"cmd": "save_scene", "path": arguments.get("save_path", "")}
        elif name == "godot_create_scene":
            command = {"cmd": "create_scene", "save_path": arguments.get("save_path"), "root_type": arguments.get("root_type", "Node3D"), "name": arguments.get("name", "SceneRoot")}
        elif name == "godot_load_scene":
            command = {"cmd": "load_scene", "path": arguments.get("path")}
        elif name == "godot_add_child_scene":
            command = {"cmd": "add_child_scene", "scene_path": arguments.get("scene_path"), "parent": arguments.get("parent_path", ""), "name": arguments.get("name", "")}
        elif name == "godot_fix_ownership":
            command = {"cmd": "set_owner_recursive", "path": arguments.get("root_path")}

        elif name == "godot_env_create":
            command = {"cmd": "env_create"}
        elif name == "godot_env_set_background":
            command = {
                "cmd": "env_set_background",
                "mode": arguments.get("mode"),
                "color": arguments.get("color", [0, 0, 0]),
                "energy": arguments.get("energy", 1.0)
            }
        elif name == "godot_env_set_effect":
            command = {
                "cmd": "env_set_effect",
                "type": arguments.get("effect_type"),
                "enabled": arguments.get("enabled", True),
                "params": arguments.get("params", {})
            }
        elif name == "godot_env_camera_attributes":
            command = arguments.copy()
            command["cmd"] = "env_set_camera_attributes"

        # --- FILESYSTEM OPS ---
        elif name == "godot_search_files":
            command = {
                "cmd": "search_files",
                "query": arguments.get("query", ""),
                "extensions": arguments.get("extensions", []),
                "root": arguments.get("root", "res://")
            }
        elif name == "godot_list_files":
            command = {"cmd": "list_dir", "path": arguments.get("path", "res://"), "recursive": arguments.get("recursive", False), "extensions": arguments.get("extensions", [])}
        elif name == "godot_make_directory":
            command = {"cmd": "make_dir", "path": arguments.get("path")}
        elif name == "godot_manage_file":
            action = arguments.get("action")
            if action == "delete":
                command = {"cmd": "remove_file", "path": arguments.get("path")}
            else:
                command = {"cmd": "rename_file", "from_path": arguments.get("path"), "to_path": arguments.get("new_path")}

        # --- MESH & PHYSICS OPS ---
        elif name == "godot_set_mesh":
            command = {"cmd": "set_mesh", "path": arguments.get("node_path"), "mesh_type": arguments.get("mesh_type"), "params": arguments.get("params", {})}
        elif name == "godot_add_collision_shape":
            command = {"cmd": "add_collision_shape", "parent": arguments.get("parent_path"), "shape_type": arguments.get("shape_type"), "params": arguments.get("params", {}), "name": arguments.get("name", "CollisionShape")}
        elif name == "godot_get_collision_layers":
            command = {"cmd": "get_collision_layers", "type": arguments.get("type", "3D")}
        elif name == "godot_set_physics_layer":
            cmd_type = "set_collision_layer" if arguments.get("type") == "layer" else "set_collision_mask"
            command = {"cmd": cmd_type, "path": arguments.get("node_path"), "layer": arguments.get("layer_index"), "enabled": arguments.get("enabled", True)}
        elif name == "godot_set_collision_layer_name":
            command = {"cmd": "set_collision_layer_name", "index": arguments.get("index"), "name": arguments.get("name"), "type": arguments.get("type", "3D")}

        # --- TERRAIN 3D OPS ---
        elif name == "godot_terrain_create":
            command = {"cmd": "create_terrain", "name": arguments.get("name"), "parent_path": arguments.get("parent_path"), "storage_path": arguments.get("storage_path", "")}
        elif name == "godot_terrain_configure":
            command = arguments.copy()
            command["cmd"] = "terrain_configure"
        elif name == "godot_terrain_physics":
            command = arguments.copy()
            command["cmd"] = "terrain_physics"
        elif name == "godot_terrain_rendering":
            command = arguments.copy()
            command["cmd"] = "terrain_rendering"
        elif name == "godot_terrain_visuals":
            command = arguments.copy()
            command["cmd"] = "terrain_visuals"
        elif name == "godot_terrain_bake_mesh":
            command = {"cmd": "terrain_bake_mesh", "node_path": arguments.get("node_path"), "lod": arguments.get("lod", 4), "save_path": arguments.get("save_path", "")}
        elif name == "godot_terrain_get_height":
            command = {"cmd": "terrain_get_height", "node_path": arguments.get("node_path"), "x": arguments.get("x"), "z": arguments.get("z")}
        elif name == "godot_terrain_import_heightmap":
            command = {
                "cmd": "terrain_import_heightmap",
                "node_path": arguments.get("node_path"),
                "file_path": arguments.get("file_path"),
                "min_height": arguments.get("min_height", 0.0),
                "max_height": arguments.get("max_height", 100.0),
                "position": arguments.get("position", [0, 0, 0])
            }
        elif name == "godot_terrain_task":
            command = {
                "cmd": "terrain_task",
                "task_type": arguments.get("task_type"),
                "map_type": arguments.get("map_type"),
                "file_path": arguments.get("file_path"),
                "data_dir": arguments.get("data_dir"),
                "params": arguments.get("params", {})
            }
        elif name == "godot_terrain_add_texture":
            command = arguments.copy()
            command["cmd"] = "terrain_add_texture"
        elif name == "godot_terrain_add_mesh":
            command = arguments.copy()
            command["cmd"] = "terrain_add_mesh"
        elif name == "godot_terrain_place_instances":
            command = arguments.copy()
            command["cmd"] = "terrain_place_instances"
        elif name == "godot_terrain_bake_navmesh":
            command = arguments.copy()
            command["cmd"] = "terrain_bake_navmesh"
        elif name == "godot_terrain_raycast":
            command = arguments.copy()
            command["cmd"] = "terrain_raycast"
        elif name == "godot_2d_create":
            command = arguments.copy()
            command["cmd"] = "create_node_2d"
        elif name == "godot_2d_transform":
            command = arguments.copy()
            command["cmd"] = "set_transform_2d"


        # --- SCRIPT OPS ---
        elif name == "godot_create_script": # Aktualizace pro overwrite parametr
             command = {
                "cmd": "create_script", 
                "path": arguments.get("path"), 
                "content": arguments.get("content"),
                "overwrite": arguments.get("overwrite", False)
            }
        elif name == "godot_read_script":
            command = {"cmd": "get_script_content", "path": arguments.get("path")}
        elif name == "godot_attach_script":
            command = {"cmd": "attach_script", "path": arguments.get("node_path"), "script_path": arguments.get("script_path")}
        elif name == "godot_detach_script":
            command = {"cmd": "detach_script", "path": arguments.get("node_path")}

        else:
            return [TextContent(type="text", text=f"✗ Neznámý nástroj: {name}")]

        # Odeslání příkazu
        response = await send_godot_command(command)
        
        # Formátování výsledku
        if response.get("status") == "ok":
            if "tree" in response:
                result = f"✓ Strom scény:\n{json.dumps(response['tree'], indent=2, ensure_ascii=False)}"
            elif "files" in response:
                result = f"✓ Soubory v {response.get('base_path', '')}:\n{json.dumps(response['files'], indent=2, ensure_ascii=False)}"
            elif "info" in response:
                result = f"✓ Info:\n{json.dumps(response['info'], indent=2, ensure_ascii=False)}"
            elif "content" in response:
                result = f"✓ Obsah souboru:\n\n{response['content']}"
            elif "data" in response:
                result = f"✓ Data:\n{json.dumps(response['data'], indent=2, ensure_ascii=False)}"
            elif "layers" in response:
                result = f"✓ Nastavené vrstvy ({response.get('type', '3D')}):\n{json.dumps(response['layers'], indent=2, ensure_ascii=False)}"
            else:
                result = f"✓ {response.get('message', 'Akce provedena úspěšně')}"
        else:
            result = f"✗ Chyba: {response.get('message', 'Neznámá chyba')}"
        
        # Omezení délky logu pro přehlednost
        log_result = result[:200] + "..." if len(result) > 200 else result
        logger.info(f"Výsledek: {log_result}")
        
        return [TextContent(type="text", text=result)]
    
    except Exception as e:
        error_msg = f"✗ Kritická chyba v call_tool: {str(e)}"
        logger.error(error_msg)
        return [TextContent(type="text", text=error_msg)]


async def main():
    """
    Spustí MCP server přes stdio.
    """
    logger.info("Spouštím Godot MCP Server v5 (Nodes, Scenes, Files, Terrain3D)...")
    async with stdio_server() as (read_stream, write_stream):
        logger.info("Server připraven, čekám na příkazy...")
        await app.run(
            read_stream,
            write_stream,
            app.create_initialization_options()
        )


if __name__ == "__main__":
    asyncio.run(main())
