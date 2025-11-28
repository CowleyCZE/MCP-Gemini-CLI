import json
import asyncio
from fastmcp import Client

async def main():
    try:
        async with Client.from_url("http://127.0.0.1:8000/mcp") as client:
            result = await client.call_tool("take_screenshot", {})
            try:
                print(json.dumps(json.loads(result), indent=2))
            except Exception:
                try:
                    print(json.dumps(json.loads(result.content[0].text), indent=2))
                except Exception:
                    print(result)
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    asyncio.run(main())
