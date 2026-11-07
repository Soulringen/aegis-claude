# Aegis Claude

> **EN** — A Windows reset for the local identifiers that Claude Desktop and Claude Code keep on your PC. The next launch creates new ones. Your chats stay.
>
> **RU** — Сброс локальных идентификаторов Claude Desktop и Claude Code в Windows. Чаты остаются.

[Русский](#русский) · [English](#english)

<div align="center">

[![Download ZIP](https://img.shields.io/badge/Download-ZIP-2ea44f?style=for-the-badge&logo=github&logoColor=white)](https://github.com/Soulringen/aegis-claude/archive/refs/heads/main.zip)

**[⬇ Скачать / Download ZIP](https://github.com/Soulringen/aegis-claude/archive/refs/heads/main.zip)** — распакуйте и запустите `Reset-ClaudeIdentity.bat` / unzip and run `Reset-ClaudeIdentity.bat`

[![Telegram chat](https://img.shields.io/badge/Чат_—_обсуждаем_тут-Telegram-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/+7s28qgf7IWliMDdi)
[![Telegram channel](https://img.shields.io/badge/Ресеты_Claude_и_Codex-Telegram-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/my_ai_mayak)

</div>

---

## Русский

Claude запоминает компьютер отдельно от аккаунта. Пока эти метки лежат на диске, новый вход выглядит как тот же компьютер. Скрипт стирает этот слой — при следующем запуске Claude создаёт новые идентификаторы. Тексты чатов остаются.

### Быстрый старт

1. Нажмите кнопку **Download ZIP** выше и распакуйте папку.
2. Закройте Claude.
3. Дважды щёлкните `Reset-ClaudeIdentity.bat`.
4. В окне нажмите `1` — удалить, или `2` — выйти без изменений.

Сначала скрипт показывает, что нашёл, и ничего не трогает, пока вы не выберете `1`. Само приложение он не удаляет.

### Что меняется

| Удаляется | Остаётся |
| --- | --- |
| `machineID`, `userID`, `ant-did` | диалоги и память проектов (`%USERPROFILE%\.claude\projects`, `MEMORY.md`) |
| реестр устройства, соли и очередь телеметрии | сессии и история файлов |
| журналы `config.json`, история лимитов и метки аккаунтов | `settings.json` |
| cookies и локальное хранилище приложения | сессии десктопного приложения |
| сохранённый логин | установка в `%LOCALAPPDATA%\AnthropicClaude` |

Логин сбрасывается — войти нужно заново.

### Что скрипт не трогает

- язык Windows, часовой пояс и IP-адрес;
- cookies `claude.ai` в Chrome и Edge, включая `ajs_anonymous_id`;
- переписки, которые уже лежат на сервере аккаунта.

### Запуск из PowerShell

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Reset-ClaudeIdentity.ps1
```

Если файл занят, скрипт сообщит об этом — закройте Claude и запустите ещё раз.

---

## English

Claude remembers the computer apart from the account. While those marks stay on disk, a new sign-in still looks like the same machine. The script removes that layer — the next launch writes fresh identifiers. Your chats stay.

### Quick start

1. Click the **Download ZIP** button above and unzip the folder.
2. Quit Claude.
3. Double-click `Reset-ClaudeIdentity.bat`.
4. In the window press `1` to delete, or `2` to exit without changes.

The script first shows what it found and touches nothing until you choose `1`. It does not uninstall the app.

### What changes

| Removed | Kept |
| --- | --- |
| `machineID`, `userID`, `ant-did` | Claude Code transcripts and project memory (`%USERPROFILE%\.claude\projects`, `MEMORY.md`) |
| device registry, telemetry salts and queued events | sessions and file history |
| `config.json` journals, usage history, and account markers | `settings.json` |
| the app's cookies and local storage | desktop session folders |
| the saved login | install at `%LOCALAPPDATA%\AnthropicClaude` |

The saved login is cleared, so you sign in again.

### What it leaves alone

- Windows locale, timezone, and your IP address;
- Chrome and Edge cookies for `claude.ai`, including `ajs_anonymous_id`;
- conversations already stored on the account's servers.

### Run from PowerShell

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Reset-ClaudeIdentity.ps1
```

If a file is in use, the script says so — quit Claude and run it again.

---

## macOS

Скрипт для macOS лежит в `macos/reset-claude-identity.command` (та же логика, пути `~/Library/Application Support/Claude`).

```bash
chmod +x macos/reset-claude-identity.command
bash macos/reset-claude-identity.command        # предпросмотр, затем 1/2
```

A macOS script lives in `macos/reset-claude-identity.command` (same logic, `~/Library/Application Support/Claude` paths).

## Сообщество / Community

- **[Чат — обсуждаем тут](https://t.me/+7s28qgf7IWliMDdi)** — вопросы, помощь, обсуждение. / Questions, help, discussion.
- **[Канал «AI Маяк»](https://t.me/my_ai_mayak)** — уведомляем о ресетах лимитов Claude и Codex и прогнозируем их. / We post and predict Claude and Codex resets.
