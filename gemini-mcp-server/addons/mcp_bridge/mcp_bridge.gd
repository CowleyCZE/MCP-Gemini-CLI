@tool
extends EditorPlugin

var tcp_server: Node = null

func _enter_tree():
	print("═══════════════════════════════════════════")
	print("  MCP BRIDGE PLUGIN - SPOUŠTĚNÍ")
	print("═══════════════════════════════════════════")
	
	# Vytvoření TCP serveru
	tcp_server = preload("res://addons/mcp_bridge/tcp_server.gd").new()
	tcp_server.name = "MCPBridgeServer"
	EditorInterface.get_base_control().add_child(tcp_server)
	
	print("✓ MCP Bridge plugin aktivován")
	print("✓ TCP Server naslouchá na portu 4242")
	print("═══════════════════════════════════════════")

func _exit_tree():
	print("═══════════════════════════════════════════")
	print("  MCP BRIDGE PLUGIN - UKONČOVÁNÍ")
	print("═══════════════════════════════════════════")
	
	# Ukončení serveru
	if tcp_server:
		tcp_server.queue_free()
		tcp_server = null
	
	print("✓ MCP Bridge plugin deaktivován")
	print("═══════════════════════════════════════════")
