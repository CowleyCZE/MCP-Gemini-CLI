#!/usr/bin/env python3
"""
Test skript pro ověření Godot MCP serveru
"""

import socket
import json
import time

GODOT_HOST = "localhost"
GODOT_PORT = 4242

def test_connection():
    """Test základního připojení"""
    print("🔍 Test 1: Připojení k Godot serveru...")
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        sock.connect((GODOT_HOST, GODOT_PORT))
        print("✓ Připojení úspěšné!")
        sock.close()
        return True
    except Exception as e:
        print(f"✗ Chyba připojení: {e}")
        return False

def send_command(command: dict):
    """Odešle příkaz a vrátí odpověď"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5.0)
        sock.connect((GODOT_HOST, GODOT_PORT))
        
        # Odeslání
        json_data = json.dumps(command)
        sock.sendall(json_data.encode('utf-8'))
        
        # Příjem
        response_data = sock.recv(4096)
        sock.close()
        
        if response_data:
            return json.loads(response_data.decode('utf-8'))
        else:
            return {"status": "error", "message": "Žádná odpověď"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

def test_create_node():
    """Test vytvoření node"""
    print("\n🔍 Test 2: Vytvoření Node3D...")
    command = {
        "cmd": "create_node",
        "type": "Node3D",
        "name": "TestNode",
        "parent": ""
    }
    response = send_command(command)
    print(f"Odpověď: {json.dumps(response, indent=2, ensure_ascii=False)}")
    return response.get("status") == "ok"

def test_set_property():
    """Test nastavení vlastnosti"""
    print("\n🔍 Test 3: Nastavení pozice...")
    command = {
        "cmd": "set_prop",
        "path": "TestNode",
        "prop": "position",
        "val": [1, 2, 3]
    }
    response = send_command(command)
    print(f"Odpověď: {json.dumps(response, indent=2, ensure_ascii=False)}")
    return response.get("status") == "ok"

def test_get_tree():
    """Test získání stromu scény"""
    print("\n🔍 Test 4: Získání stromu scény...")
    command = {"cmd": "get_scene_tree"}
    response = send_command(command)
    if response.get("status") == "ok":
        print("✓ Strom scény získán:")
        print(json.dumps(response.get("tree"), indent=2, ensure_ascii=False))
        return True
    else:
        print(f"✗ Chyba: {response.get('message')}")
        return False

def test_delete_node():
    """Test smazání node"""
    print("\n🔍 Test 5: Smazání TestNode...")
    command = {
        "cmd": "delete_node",
        "path": "TestNode"
    }
    response = send_command(command)
    print(f"Odpověď: {json.dumps(response, indent=2, ensure_ascii=False)}")
    return response.get("status") == "ok"

def main():
    print("=" * 60)
    print("GODOT MCP SERVER - TEST SUITE")
    print("=" * 60)
    print("\n⚠️  Ujistěte se, že:")
    print("1. Godot Editor je spuštěný")
    print("2. MCP Bridge plugin je aktivní")
    print("3. Máte otevřenou nějakou scénu")
    print("\nStiskněte Enter pro pokračování...")
    input()
    
    results = []
    
    # Test 1: Připojení
    results.append(("Připojení", test_connection()))
    
    if results[0][1]:
        # Test 2-5: Operace
        time.sleep(0.5)
        results.append(("Vytvoření node", test_create_node()))
        
        time.sleep(0.5)
        results.append(("Nastavení vlastnosti", test_set_property()))
        
        time.sleep(0.5)
        results.append(("Získání stromu", test_get_tree()))
        
        time.sleep(0.5)
        results.append(("Smazání node", test_delete_node()))
    
    # Souhrn
    print("\n" + "=" * 60)
    print("SOUHRN TESTŮ")
    print("=" * 60)
    for test_name, success in results:
        status = "✓ PASS" if success else "✗ FAIL"
        print(f"{status} - {test_name}")
    
    passed = sum(1 for _, success in results if success)
    total = len(results)
    print(f"\nVýsledek: {passed}/{total} testů prošlo")
    
    if passed == total:
        print("\n🎉 Všechny testy úspěšné! Můžete pokračovat k Gemini CLI.")
    else:
        print("\n⚠️  Některé testy selhaly. Zkontrolujte Godot plugin.")

if __name__ == "__main__":
    main()