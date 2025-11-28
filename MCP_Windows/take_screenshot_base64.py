@mcp.tool()
def take_screenshot_base64(filename: str = "screenshot.jpg", max_width: int = 400):
    """
    Takes a VERY small screenshot with base64 encoding for AI vision analysis.
    WARNING: Only use when absolutely necessary due to token limits!

    Args:
        filename: The desired filename. Defaults to 'screenshot.jpg'.
        max_width: Maximum width (default 400px - very small!).

    Returns:
        A JSON string with 'filepath' and 'image_base64' keys.
    """
    try:
        if not filename.endswith('.jpg') and not filename.endswith('.jpeg'):
            filename = filename.rsplit('.', 1)[0] + '.jpg'
        
        if ".." in filename or "/" in filename or "\\" in filename:
            filename = "screenshot.jpg"

        temp_dir = tempfile.gettempdir()
        filepath = os.path.join(temp_dir, filename)

        # Take screenshot
        screenshot = pyautogui.screenshot()
        
        # Convert to RGB
        if screenshot.mode != 'RGB':
            screenshot = screenshot.convert('RGB')
        
        # Very aggressive resize
        width, height = screenshot.size
        if width > max_width:
            new_height = int((max_width / width) * height)
            screenshot = screenshot.resize((max_width, new_height))
        
        # Save with very aggressive compression
        screenshot.save(filepath, format='JPEG', optimize=True, quality=30)

        with open(filepath, "rb") as image_file:
            encoded_string = base64.b64encode(image_file.read()).decode('utf-8')
        
        output = {
            "message": f"Small screenshot saved: {filepath} ({screenshot.size[0]}x{screenshot.size[1]})",
            "filepath": filepath,
            "image_base64": encoded_string,
            "width": screenshot.size[0],
            "height": screenshot.size[1],
            "warning": "Very low quality for token efficiency"
        }

        return json.dumps(output)
    except Exception as e:
        return json.dumps({"error": f"Error taking screenshot: {e}"})