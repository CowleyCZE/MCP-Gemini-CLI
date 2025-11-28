"""
This script implements a FastMCP server for Windows GUI automation using pyautogui.
It provides tools for controlling the mouse, keyboard, and taking screenshots.
"""

import os
import tempfile
from typing import List
import base64
import json
from pathlib import Path

import pyautogui
from fastmcp import FastMCP

# --- Safety ---
pyautogui.FAILSAFE = True

# --- MCP Server Initialization ---
mcp = FastMCP(
    name="Windows GUI Control",
    version="1.0.0",
)


# --- Tools ---
@mcp.tool()
def mouse_move(x: int, y: int, duration: float = 0.5):
    """
    Moves the mouse cursor to the specified coordinates on the screen.

    Args:
        x: The x-coordinate to move the mouse to.
        y: The y-coordinate to move the mouse to.
        duration: The time in seconds to spend moving the mouse.
    """
    try:
        pyautogui.moveTo(x, y, duration=duration)
        return f"Mouse moved to ({x}, {y})."
    except Exception as e:
        return f"Error moving mouse: {e}"


@mcp.tool()
def mouse_click(x: int, y: int, button: str = "left", double: bool = False):
    """
    Performs a mouse click at the specified coordinates.

    Args:
        x: The x-coordinate to click at.
        y: The y-coordinate to click at.
        button: The mouse button to click ('left', 'right', 'middle'). Defaults to 'left'.
        double: Whether to perform a double-click. Defaults to False.
    """
    try:
        if double:
            pyautogui.doubleClick(x, y, button=button)
            return f"Double-clicked {button} button at ({x}, {y})."
        else:
            pyautogui.click(x, y, button=button)
            return f"Clicked {button} button at ({x}, {y})."
    except Exception as e:
        return f"Error clicking mouse: {e}"


@mcp.tool()
def keyboard_type(text: str, interval: float = 0.1):
    """
    Types the given text using the keyboard.

    Args:
        text: The string to type.
        interval: The time in seconds to wait between each key press.
    """
    try:
        pyautogui.write(text, interval=interval)
        return f"Typed text: '{text}'."
    except Exception as e:
        return f"Error typing text: {e}"


@mcp.tool()
def keyboard_press(keys: List[str]):
    """
    Presses and releases a combination of keyboard keys (hotkey).

    Args:
        keys: A list of keys to press simultaneously (e.g., ['ctrl', 's']).
    """
    try:
        pyautogui.hotkey(*keys)
        return f"Pressed hotkey: {', '.join(keys)}."
    except Exception as e:
        return f"Error pressing hotkey: {e}"


@mcp.tool()
def get_screen_size():
    """
    Returns the width and height of the primary screen.

    Returns:
        A dictionary containing the 'width' and 'height' of the screen.
    """
    try:
        width, height = pyautogui.size()
        return {"width": width, "height": height}
    except Exception as e:
        return f"Error getting screen size: {e}"


@mcp.tool()
def mouse_scroll(amount: int = 1, direction: str = "down", x: int = None, y: int = None):
    try:
        clicks = amount if direction.lower() == "up" else -amount
        if x is not None and y is not None:
            pyautogui.moveTo(x, y)
        pyautogui.scroll(clicks)
        return f"Scrolled {'up' if clicks > 0 else 'down'} {abs(clicks)}"
    except Exception as e:
        return f"Error scrolling mouse: {e}"


@mcp.tool()
def mouse_hscroll(amount: int = 1, direction: str = "right", x: int = None, y: int = None):
    try:
        clicks = amount if direction.lower() == "right" else -amount
        if x is not None and y is not None:
            pyautogui.moveTo(x, y)
        try:
            pyautogui.hscroll(clicks)
            return f"HScrolled {'right' if clicks > 0 else 'left'} {abs(clicks)}"
        except Exception:
            pyautogui.keyDown('shift')
            try:
                pyautogui.scroll(clicks)
            finally:
                pyautogui.keyUp('shift')
            return f"HScrolled (shift+scroll) {'right' if clicks > 0 else 'left'} {abs(clicks)}"
    except Exception as e:
        return f"Error horizontal scrolling mouse: {e}"


@mcp.tool()
def mouse_move_relative(dx: int, dy: int, duration: float = 0.5):
    try:
        pyautogui.moveRel(dx, dy, duration=duration)
        return f"Mouse moved relatively by ({dx}, {dy})."
    except Exception as e:
        return f"Error moving mouse relatively: {e}"


@mcp.tool()
def key_down(key: str):
    try:
        pyautogui.keyDown(key)
        return f"Key down: {key}"
    except Exception as e:
        return f"Error key down: {e}"


@mcp.tool()
def key_up(key: str):
    try:
        pyautogui.keyUp(key)
        return f"Key up: {key}"
    except Exception as e:
        return f"Error key up: {e}"


@mcp.tool()
def mouse_down(button: str = "left", x: int = None, y: int = None):
    try:
        if x is not None and y is not None:
            pyautogui.moveTo(x, y)
        pyautogui.mouseDown(button=button)
        return f"Mouse down: {button}"
    except Exception as e:
        return f"Error mouse down: {e}"


@mcp.tool()
def mouse_up(button: str = "left", x: int = None, y: int = None):
    try:
        if x is not None and y is not None:
            pyautogui.moveTo(x, y)
        pyautogui.mouseUp(button=button)
        return f"Mouse up: {button}"
    except Exception as e:
        return f"Error mouse up: {e}"


@mcp.tool()
def mouse_drag(dx: int, dy: int, duration: float = 0.5, button: str = "left", start_x: int = None, start_y: int = None):
    try:
        if start_x is not None and start_y is not None:
            pyautogui.moveTo(start_x, start_y)
        pyautogui.dragRel(dx, dy, duration=duration, button=button)
        return f"Mouse dragged by ({dx}, {dy}) with {button}"
    except Exception as e:
        return f"Error mouse drag: {e}"


@mcp.tool()
def mouse_drag_to(x: int, y: int, duration: float = 0.5, button: str = "left", start_x: int = None, start_y: int = None):
    try:
        if start_x is not None and start_y is not None:
            pyautogui.moveTo(start_x, start_y)
        pyautogui.dragTo(x, y, duration=duration, button=button)
        return f"Mouse dragged to ({x}, {y}) with {button}"
    except Exception as e:
        return f"Error mouse drag to: {e}"


@mcp.tool()
def take_screenshot_region(x: int, y: int, width: int, height: int, filename: str = "screenshot_region.jpg", max_width: int = 640):
    try:
        from PIL import Image
        if not filename.endswith('.jpg') and not filename.endswith('.jpeg'):
            filename = filename.rsplit('.', 1)[0] + '.jpg'
        if ".." in filename or "/" in filename or "\\" in filename:
            filename = "screenshot_region.jpg"
        temp_dir = tempfile.gettempdir()
        filepath = os.path.join(temp_dir, filename)
        screenshot = pyautogui.screenshot(region=(x, y, width, height))
        original_width, original_height = screenshot.size
        if screenshot.mode != 'RGB':
            screenshot = screenshot.convert('RGB')
        if original_width > max_width:
            scale_factor = original_width / max_width
            new_height = int(original_height / scale_factor)
            screenshot = screenshot.resize((max_width, new_height), 1)
        else:
            scale_factor = 1.0
        screenshot.save(filepath, format='JPEG', optimize=True, quality=60)
        with open(filepath, "rb") as image_file:
            encoded_string = base64.b64encode(image_file.read()).decode('utf-8')
        output = {
            "message": f"Region screenshot saved to: {filepath}",
            "filepath": filepath,
            "image_base64": encoded_string,
            "original_width": original_width,
            "original_height": original_height,
            "resized_width": screenshot.size[0],
            "resized_height": screenshot.size[1],
            "scale_factor": scale_factor
        }
        return json.dumps(output)
    except Exception as e:
        return json.dumps({"error": f"Error taking region screenshot: {e}"})


@mcp.tool()
def list_desktop_files(extension: str = None):
    """
    Lists all files on the Windows Desktop.

    Args:
        extension: Optional file extension to filter by (e.g., '.txt', '.pdf').

    Returns:
        A JSON string with a list of files found on the desktop.
    """
    try:
        # Get the Desktop path
        desktop_path = Path.home() / "Desktop"
        
        if not desktop_path.exists():
            return json.dumps({"error": "Desktop path not found"})
        
        # List all files
        files = []
        for item in desktop_path.iterdir():
            if item.is_file():
                if extension is None or item.suffix.lower() == extension.lower():
                    files.append({
                        "name": item.name,
                        "path": str(item),
                        "extension": item.suffix,
                        "size_bytes": item.stat().st_size
                    })
        
        return json.dumps({
            "desktop_path": str(desktop_path),
            "files_found": len(files),
            "files": files
        })
    except Exception as e:
        return json.dumps({"error": f"Error listing desktop files: {e}"})


@mcp.tool()
def find_file_on_desktop(filename: str):
    """
    Searches for a specific file on the Desktop by name (case-insensitive).

    Args:
        filename: The name of the file to search for (can be partial match).

    Returns:
        A JSON string with matching files.
    """
    try:
        desktop_path = Path.home() / "Desktop"
        
        if not desktop_path.exists():
            return json.dumps({"error": "Desktop path not found"})
        
        # Search for files
        matches = []
        search_term = filename.lower()
        
        for item in desktop_path.iterdir():
            if item.is_file() and search_term in item.name.lower():
                matches.append({
                    "name": item.name,
                    "path": str(item),
                    "extension": item.suffix
                })
        
        return json.dumps({
            "search_term": filename,
            "matches_found": len(matches),
            "matches": matches
        })
    except Exception as e:
        return json.dumps({"error": f"Error searching for file: {e}"})


@mcp.tool()
def locate_icon_on_screen(icon_name: str):
    """
    Attempts to locate a desktop icon by searching for its visual appearance.
    This uses pyautogui's image recognition.

    Args:
        icon_name: Name of the icon file to locate (must exist as image file).

    Returns:
        A JSON string with the coordinates if found.
    """
    try:
        # This would require icon image files to work properly
        # For now, return a helpful message
        return json.dumps({
            "error": "Icon location requires reference images. Use list_desktop_files instead.",
            "suggestion": "Use list_desktop_files to find files, then use keyboard shortcuts to select them."
        })
    except Exception as e:
        return json.dumps({"error": f"Error locating icon: {e}"})


@mcp.tool()
def delete_file(filepath: str):
    """
    Deletes a file at the specified path.
    WARNING: This permanently deletes the file!

    Args:
        filepath: Full path to the file to delete.

    Returns:
        A message indicating success or failure.
    """
    try:
        file_path = Path(filepath)
        
        # Safety check - only allow Desktop files
        desktop_path = Path.home() / "Desktop"
        if desktop_path not in file_path.parents and file_path.parent != desktop_path:
            return json.dumps({"error": "Can only delete files on Desktop for safety"})
        
        if not file_path.exists():
            return json.dumps({"error": f"File not found: {filepath}"})
        
        if not file_path.is_file():
            return json.dumps({"error": f"Path is not a file: {filepath}"})
        
        # Delete the file
        file_path.unlink()
        
        return json.dumps({
            "success": True,
            "message": f"File deleted: {filepath}"
        })
    except Exception as e:
        return json.dumps({"error": f"Error deleting file: {e}"})


@mcp.tool()
def take_screenshot(filename: str = "screenshot.jpg", max_width: int = 640):
    """
    Takes a screenshot optimized for AI vision analysis with minimal token usage.
    Returns base64 encoded image that AI can analyze to determine where to click.

    Args:
        filename: The desired filename for the screenshot. Defaults to 'screenshot.jpg'.
        max_width: Maximum width of the resized image. Defaults to 640 pixels.

    Returns:
        A JSON string with 'filepath', 'image_base64', dimensions, and scale factor.
    """
    try:
        # Import PIL here to avoid issues
        from PIL import Image
        
        # Force .jpg extension for better compression
        if not filename.endswith('.jpg') and not filename.endswith('.jpeg'):
            filename = filename.rsplit('.', 1)[0] + '.jpg'
        
        if ".." in filename or "/" in filename or "\\" in filename:
            filename = "screenshot.jpg"

        temp_dir = tempfile.gettempdir()
        filepath = os.path.join(temp_dir, filename)

        # Take screenshot
        screenshot = pyautogui.screenshot()
        original_width, original_height = screenshot.size
        
        # Convert to RGB (JPEG doesn't support alpha channel)
        if screenshot.mode != 'RGB':
            screenshot = screenshot.convert('RGB')
        
        # Resize to reduce token usage while keeping it readable
        if original_width > max_width:
            scale_factor = original_width / max_width
            new_height = int(original_height / scale_factor)
            # Use LANCZOS (high quality) resampling - value is 1
            screenshot = screenshot.resize((max_width, new_height), 1)
        else:
            scale_factor = 1.0
        
        # Save with balanced JPEG compression
        screenshot.save(filepath, format='JPEG', optimize=True, quality=60)

        with open(filepath, "rb") as image_file:
            encoded_string = base64.b64encode(image_file.read()).decode('utf-8')
        
        output = {
            "message": f"Screenshot saved to: {filepath}",
            "filepath": filepath,
            "image_base64": encoded_string,
            "original_width": original_width,
            "original_height": original_height,
            "resized_width": screenshot.size[0],
            "resized_height": screenshot.size[1],
            "scale_factor": scale_factor,
            "note": f"To click at a position you see, multiply coordinates by {scale_factor:.2f}"
        }

        return json.dumps(output)
    except Exception as e:
        return json.dumps({"error": f"Error taking screenshot: {e}"})


# --- Main Execution ---
if __name__ == "__main__":
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    print(f"Starting Windows GUI Control MCP Server ({transport.upper()} mode)...")
    print("FAILSAFE is ON. Move mouse to the top-left corner to quit.")
    host = os.environ.get("MCP_HOST", "127.0.0.1")
    port = int(os.environ.get("MCP_PORT", "8000"))
    mcp.run(transport=transport, host=host, port=port)
