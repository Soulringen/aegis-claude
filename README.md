# Aegis Claude

A Windows reset for the local identifiers Claude Desktop and Claude Code store on this PC. The next launch creates new ones. Your chat transcripts stay on disk.

Сброс локальных идентификаторов Claude Desktop и Claude Code на Windows. Следующий запуск создаёт новые. Тексты чатов остаются на диске.

## Русский

Скрипт показывает, какие файлы нашёл, и ничего не удаляет, пока вы сами не выберете удаление. Само приложение Claude не трогает.

### Что делает

Claude запоминает компьютер отдельно от аккаунта: `machineID`, `userID`, `ant-did`, реестр устройства, соли телеметрии, cookies и локальное хранилище приложения. Пока эти данные лежат на диске, новый вход выглядит как тот же компьютер.

Скрипт стирает этот слой. После следующего запуска Claude записывает новые идентификаторы.

### Что остаётся

- диалоги Claude Code в `%USERPROFILE%\.claude\projects`
- сессии и история файлов
- `settings.json`
- сессии десктопного приложения
- сама установка в `%LOCALAPPDATA%\AnthropicClaude`

Логин сбрасывается, его нужно ввести заново.

### Что скрипт не меняет

- язык Windows, часовой пояс и IP-адрес
- cookies `claude.ai` в Chrome и Edge, включая `ajs_anonymous_id`
- переписки, которые уже лежат на сервере аккаунта

### Как запустить

Дважды щёлкните `Reset-ClaudeIdentity.bat`.

Окно покажет найденные идентификаторы и папки с чатами, затем спросит:

```text
Напишите 1, чтобы удалить идентификаторы, 2 чтобы выйти из программы
```

- **1** останавливает процессы Claude и удаляет идентификаторы
- **2** закрывает окно, файлы не меняются

Тот же запуск из PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Reset-ClaudeIdentity.ps1
```

Закройте Claude перед удалением. Если файл останется занят, скрипт напишет об этом и попросит запустить его ещё раз.

## English

The script prints what it found and deletes nothing until you choose to. It does not uninstall Claude.

### What it does

Claude remembers the computer apart from the account: `machineID`, `userID`, `ant-did`, the device registry, telemetry salts, and the app's own cookies and local storage. While those files remain, a new sign-in still looks like the same machine.

The script removes that layer. The next launch writes fresh identifiers.

### What stays

- Claude Code transcripts in `%USERPROFILE%\.claude\projects`
- sessions and file history
- `settings.json`
- desktop session folders
- the install under `%LOCALAPPDATA%\AnthropicClaude`

The saved login is cleared, so you sign in again.

### What it leaves alone

- Windows locale, timezone, and your IP address
- Chrome and Edge cookies for `claude.ai`, including `ajs_anonymous_id`
- conversations already stored on the account's servers

### How to run

Double-click `Reset-ClaudeIdentity.bat`.

The window lists the identifiers and the chat folders, then asks:

```text
Напишите 1, чтобы удалить идентификаторы, 2 чтобы выйти из программы
```

- **1** stops Claude and deletes the identifiers
- **2** closes the window and changes nothing

The same run from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Reset-ClaudeIdentity.ps1
```

Quit Claude before deleting. If a file is still open, the script says so and you can run it again.
