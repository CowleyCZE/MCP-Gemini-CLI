# Windows GUI Control MCP Server

Tento server umožňuje vzdáleně ovládat grafické rozhraní Windows pomocí příkazů zasílaných z MCP klienta.

## Instalace

1.  Ujistěte se, že máte nainstalovaný Python 3.8 nebo novější.
2.  Nainstalujte potřebné knihovny pomocí `pip`:

    ```bash
    pip install -r requirements.txt
    ```

## Spuštění serveru

Server spustíte následujícím příkazem v terminálu:

```bash
python windows_control.py
```

Server bude naslouchat na výchozím portu (obvykle 8000).

## Připojení k MCP klientovi

Pro připojení tohoto serveru k vašemu MCP klientovi (např. Gemini CLI), použijte následující příkaz v klientovi:

```bash
/mcp connect localhost:8000
```

Pokud server běží na jiném portu, upravte číslo portu v příkazu. Po úspěšném připojení budete moci volat definované nástroje (`mouse_move`, `mouse_click`, atd.) přímo z klienta.
