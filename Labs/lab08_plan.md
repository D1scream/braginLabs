# Лабораторная работа №8: GPG, pass, SecretSpec и расширения CLI

**Проект:** «Пирожки с предсказаниями» (Rust/Axum + SQLx + PostgreSQL + devenv)  
**Формат:** видео и демонстрация в терминале; 20 минут; 12 слайдов  
**Продолжаем лабораторную №7:** работающее API, миграции, Portless, `fmt`/`chk`, Git hooks.

## Идея занятия

Постепенно переходим от ручных команд к персональным инструментам и управлению секретами проекта:

```text
PostgreSQL
   │ pg_dump (plain SQL)
   ▼
zstd (или xz)         ← сжатие ДО шифрования
   │
   ▼
GPG                    ← шифрование для открытого ключа
   │
   ▼
.sql.zst.gpg
   │
   └─ scripts/db-backup.sh ← повторяемые действия превращаем в helper script

GPG → pass → SecretSpec → PGPASSWORD для разных окружений
                    │
                    └─ изучаем исходники pass → пишем pass fzf
```

**Результат для студента:** умеет создавать зашифрованную резервную копию и проверять восстановление; писать маленькие вспомогательные CLI-скрипты; пользоваться `pass`; декларативно связывать секреты с проектом через SecretSpec; понимать устройство Bash-программы `pass`; расширять её собственным поиском на `fzf`.

## Хронометраж

| Время | Слайд | Тема | Практический результат |
|---|---:|---|---|
| 00:00–00:50 | 1 | Задача: резервная копия и секреты | Видим цепочку занятия |
| 00:50–02:00 | 2 | `pg_dump`, `zstd`/`xz` и GPG | Понимаем правильный порядок операций |
| 02:00–04:30 | 3 | Создать и восстановить архив | Получаем `.sql.zst.gpg` |
| 04:30–06:30 | 4 | Helper script для резервной копии | `scripts/db-backup.sh` |
| 06:30–08:20 | 5 | Установка и инициализация `pass` | Личный парольный store |
| 08:20–09:40 | 6 | Как `pass` хранит данные | Каталог `.password-store` и `.gpg-id` |
| 09:40–12:30 | 7 | SecretSpec: профили и провайдер `pass` | Разные `PGPASSWORD` для `development`/`staging` |
| 12:30–13:50 | 8 | Подключение секретов к devenv/SQLx | Секрет только в runtime приложения |
| 13:50–15:50 | 9 | Разбираем исходный код `pass` | Bash-функции и механизм extensions |
| 15:50–18:35 | 10 | Пишем расширение `pass fzf` | Интерактивный выбор записи |
| 18:35–19:20 | 11 | Проверка и ограничения | Копируем выбранный пароль, не показывая его |
| 19:20–20:00 | 12 | Итоги и следующие шаги | Замыкаем сюжет |

> **Монтаж:** ключ GPG и тестовая БД подготовлены до записи; большие вставки кода набираются по заранее подготовленному сценарию. Если писать всё с нуля в реальном времени, реалистичнее 25–30 минут.

---

## Слайд 1. Зачем всё это? (00:00–00:50)

- Напоминаем: в №7 мы научились воспроизводить окружение и проверять код.
- Теперь нужно **сохранить данные** и **не хранить пароли в Git**.
- Финальный бонус: `pass` — простой Bash-скрипт, который мы сможем расширить.

## Слайд 2. Сжатие → шифрование (00:50–02:00)

```text
pg_dump --format=plain → zstd -3 → gpg --encrypt → backup.sql.zst.gpg
```

- **Сначала сжимаем**, затем шифруем. Зашифрованные данные почти несжимаемы.
- `zstd`: практичный выбор по скорости. `xz`: альтернатива ради более плотного сжатия ценой времени.
- Используем `pg_dump --format=plain`, поскольку custom-формат PostgreSQL сам по себе может быть уже сжат.
- GPG: открытым ключом шифруем, закрытым расшифровываем. Для демонстрации заранее подготовлен тестовый ключ.

## Слайд 3. Бэкап и проверка восстановления (02:00–04:30)

*Предусловие:* подключение PostgreSQL задано переменными `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE` и, при необходимости, `PGPASSWORD`. Сам пароль в командную строку не передаём.

```bash
mkdir -p backups

pg_dump --format=plain --no-owner --no-privileges \
  | zstd -T0 -3 \
  | gpg --compress-algo none --encrypt \
      --recipient "$GPG_RECIPIENT" \
      --output backups/fortune-pies.sql.zst.gpg
```

Восстанавливаем **только в отдельную, заранее созданную тестовую базу**:

```bash
set -o pipefail

gpg --decrypt backups/fortune-pies.sql.zst.gpg \
  | zstd --decompress \
  | psql -X --set ON_ERROR_STOP=on --dbname "$RESTORE_DB"
```

При выборе `xz` меняем `zstd -T0 -3` на `xz -T0`, а при восстановлении — на `xz -dc`. Самостоятельно сжимать **после** GPG не нужно.

## Слайд 4. Helper script — меньше копирования команд (04:30–06:30)

**Мотивация:** длинный pipeline повторяется, нужны аргументы, проверка ошибок, единые параметры. Вместо shell alias делаем исполняемый файл `scripts/db-backup.sh`.

```text
scripts/db-backup.sh OUTPUT.sql.zst.gpg
      ├─ проверяет аргументы и адресата GPG
      ├─ включает set -euo pipefail и umask 077
      ├─ выполняет pg_dump | zstd | gpg
      └─ сохраняет результат, не оставляя повреждённый архив при ошибке
```

Показываем `chmod +x`, запуск с именем архива и связь с уже знакомой идеей `devenv scripts`. Исходник учебной реализации — в приложении А ниже.

## Слайд 5. Устанавливаем и настраиваем `pass` (06:30–08:20)

```bash
# Пример для Artix/Arch; набор пакетов зависит от дистрибутива.
sudo pacman -S --needed gnupg pass fzf wl-clipboard zstd

gpg --list-secret-keys --keyid-format LONG
# Если ключа нет: gpg --full-generate-key

pass init "$GPG_RECIPIENT"
pass insert demo/example
pass ls
```

`pass` использует GPG, но не заменяет его. Личное хранилище и закрытый GPG-ключ — **за пределами репозитория проекта**. Для реального использования отдельно обсудить резервную копию закрытого ключа и пароля к нему.

## Слайд 6. Данные `pass` — обычные файлы (08:20–09:40)

```text
~/.password-store/
├── .gpg-id
├── demo/
│   └── example.gpg
└── secretspec/
    └── fortune-pies/
        ├── development/
        │   └── PGPASSWORD.gpg
        └── staging/
            └── PGPASSWORD.gpg
```

- Каждая запись — отдельный файл, зашифрованный GPG.
- `.gpg-id` задаёт получателей шифрования.
- **Имена записей и структура каталогов не зашифрованы**; содержимое `.gpg` зашифровано.
- `pass` может использовать Git для синхронизации, но это не Git репозитория приложения.

## Слайд 7. SecretSpec: одна декларация, разные пароли (09:40–12:30)

Файл `secretspec.toml` **коммитим** в проект: он объявляет потребности, но не содержит значений.

```toml
[project]
name = "fortune-pies"
revision = "1.0"

[providers]
local = "pass://"

[profiles.development]
PGPASSWORD = { description = "Development PostgreSQL password", providers = ["local"] }

[profiles.staging]
PGPASSWORD = { description = "Staging PostgreSQL password", providers = ["local"] }
```

```bash
secretspec set PGPASSWORD --profile development
secretspec set PGPASSWORD --profile staging

secretspec check --profile development
secretspec check --profile staging
pass ls secretspec/fortune-pies
```

**Идея:** профиль выбирает окружение (`development`, `staging`), провайдер — место хранения (`pass`). SecretSpec по умолчанию размещает записи `pass` по схеме `secretspec/{project}/{profile}/{key}`.

> В реальном production разумно выбрать командный или серверный secrets manager; `pass` хорошо подходит для личной разработки. Пароли в двух профилях должны соответствовать учётным записям/ролям PostgreSQL в соответствующих окружениях.

## Слайд 8. Привязываем SecretSpec к devenv и API (12:30–13:50)

```yaml
# devenv.yaml (добавляем к существующей конфигурации)
secretspec:
  enable: true
  profile: development
```

```bash
# Внутри devenv shell:
secretspec run --profile development -- cargo run
```

- `secretspec run` передаёт `PGPASSWORD` **дочернему процессу во время запуска**, а не записывает в `devenv.nix`.
- PostgreSQL CLI и SQLx умеют читать `PGPASSWORD`. Адрес, порт и имя БД уже задаёт devenv; это сохраняет идею свободных портов из №7.
- **Проверить код проекта:** `DATABASE_URL` не должен содержать конфликтующий пароль; SQLx должен использовать параметры соединения, для которых `PGPASSWORD` применяется. На самом PostgreSQL должна быть настроена парольная аутентификация — наличие переменной само по себе её не включает.
- Для запуска через `devenv up` аналогично оборачиваем команду запуска **процесса API**, а не весь shell, в `secretspec run`.

## Слайд 9. Читаем `pass` как Bash-программу (13:50–15:50)

```bash
command -v pass
less "$(command -v pass)"
```

Выделяем в исходниках:

1. `umask 077`, `set -o pipefail` и переменные конфигурации.
2. `PREFIX` / `PASSWORD_STORE_DIR`: каталог хранилища.
3. Функции `cmd_init`, `cmd_show`, `cmd_insert` и вызовы `gpg`.
4. Диспетчер `case` по подкомандам.
5. `cmd_extension`: ищет исполняемый `COMMAND.bash`, затем **`source`-ит его**.

Мостик к следующему слайду: не меняем чужой код, а дописываем своё расширение.

## Слайд 10. Личное расширение `pass fzf` (15:50–18:35)

**Важно:** файл расширения живёт **локально у пользователя**, не в `fortune-pies/`.

```text
~/.password-store/.extensions/fzf.bash
```

Принцип:

```text
find *.gpg → убрать расширение → fzf → pass show --clip <запись>
```

Команды:

```bash
mkdir -p ~/.password-store/.extensions
$EDITOR ~/.password-store/.extensions/fzf.bash
chmod 700 ~/.password-store/.extensions/fzf.bash
export PASSWORD_STORE_ENABLE_EXTENSIONS=true
pass fzf
```

Готовый короткий вариант расширения — в приложении Б. `fzf` получает **только имена записей**, а не сами пароли. У `pass` уже есть логика копирования и очистки буфера обмена — используем её, не переписывая.

## Слайд 11. Проверка и безопасность (18:35–19:20)

- Демонстрация: `pass fzf` → ищем `demo/example` → выбираем → значение копируется в буфер обмена без печати в терминал.
- Для Wayland используется `wl-clipboard`; проверяем работу `pass show --clip demo/example`.
- Важные ограничения: менеджер буфера обмена может сохранять историю; скрипт-расширение — исполняемый доверенный код; названия записей видны, хотя значения зашифрованы.
- Не показываем реальные пароли на экране, не записываем архивы в Git и не храним закрытый GPG-ключ в репозитории.

## Слайд 12. Что получилось (19:20–20:00)

```text
PostgreSQL → pg_dump → zstd → GPG → encrypted backup
                   │
                   └── helper script

GPG → pass → SecretSpec profiles → приложение с PGPASSWORD
        │
        └── Bash source → extension → fzf
```

**Вывод:** простые Unix-инструменты соединяются в более удобную и контролируемую систему. При этом код проекта, личные секреты и персональные расширения CLI живут в разных местах.

**Отложено:** Docker, SQLx Offline, локальный HTTPS через Portless/mkcert, тестирование, логирование, Bubblewrap, Codex-помощник для коммитов.

---

## Приложение А. Заготовка `scripts/db-backup.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${GPG_RECIPIENT:?Set GPG_RECIPIENT to a GPG encryption key}"
output=${1:?Usage: db-backup.sh OUTPUT.sql.zst.gpg}

mkdir -p -- "$(dirname -- "$output")"
if [[ -e $output ]]; then
  printf 'File already exists: %s\n' "$output" >&2
  exit 1
fi

tmpdir=$(mktemp -d -- "${output}.tmp.XXXXXXXX")
trap 'rm -rf -- "$tmpdir"' EXIT

# PostgreSQL connection is provided through PGHOST, PGPORT,
# PGUSER, PGDATABASE and (where required) PGPASSWORD.
pg_dump --format=plain --no-owner --no-privileges \
  | zstd -T0 -3 \
  | gpg --batch --compress-algo none --encrypt \
      --recipient "$GPG_RECIPIENT" \
      --output "$tmpdir/backup"

mv -- "$tmpdir/backup" "$output"
printf 'Saved encrypted backup: %s\n' "$output"
```

Проверяем успешное завершение **всего pipeline** (`pipefail`), не оставляем промежуточный plaintext SQL-файл, ограничиваем права (`umask 077`), пишем во временную директорию и переносим результат в целевое имя только после успеха. Для урока использовать тестовые данные.

## Приложение Б. Расширение `~/.password-store/.extensions/fzf.bash`

```bash
#!/usr/bin/env bash

# pass sources this file; PREFIX is defined by pass.
selected=$(
  find "$PREFIX" -type f -name '*.gpg' -printf '%P\n' \
    | sed 's/\.gpg$//' \
    | fzf --prompt='pass> ' --height=40% --layout=reverse
) || exit 0

[[ -n $selected ]] || exit 0
pass show --clip "$selected"
```

В файле расширения есть вызов `pass`, но на него приходится уже **одна выбранная** запись. Нам не нужно вручную вызывать `gpg` или писать код работы с clipboard.

Для постоянного включения пользовательских расширений можно добавить в `~/.zshrc`:

```bash
export PASSWORD_STORE_ENABLE_EXTENSIONS=true
```

Альтернатива, если не хочется держать исполняемый файл внутри password store (например, когда он синхронизируется Git): перенести его в личный каталог и установить `PASSWORD_STORE_EXTENSIONS_DIR`.

## Подготовка к записи

- [ ] Рабочий проект после лабораторной №7, PostgreSQL с тестовыми данными и готовое подключение через `PG*`.
- [ ] Тестовая база `RESTORE_DB` для демонстрации восстановления; данные не жалко удалить.
- [ ] Создан тестовый GPG-ключ, понятен его fingerprint; есть доступ к закрытому ключу для расшифровки.
- [ ] В окружении доступны `pg_dump`, `psql`, `zstd`, `gpg`, `pass`, `fzf`; для Wayland — `wl-clipboard`.
- [ ] В `staging`/`development` созданы отдельные пароли **и серверные учётные записи**, поддерживающие парольную аутентификацию.
- [ ] Исключить `backups/` через `.gitignore`. Не фиксировать секреты или plaintext-архивы.
- [ ] Включать `PASSWORD_STORE_ENABLE_EXTENSIONS=true` только для своего проверенного расширения.
- [ ] Заготовить исходники скриптов заранее, чтобы уложиться в 20 минут.

## Ресурсы для подготовки

- [PostgreSQL: pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html)
- [PostgreSQL: переменные окружения libpq](https://www.postgresql.org/docs/current/libpq-envars.html)
- [pass — официальный сайт](https://www.passwordstore.org/)
- [pass — исходный Bash-скрипт](https://git.zx2c4.com/password-store/tree/src/password-store.sh)
- [pass — справка по расширениям](https://man.archlinux.org/man/pass.1.en)
- [SecretSpec: провайдер pass](https://secretspec.dev/providers/pass/)
- [SecretSpec: профили](https://secretspec.dev/concepts/profiles/)
- [SecretSpec: CLI](https://secretspec.dev/reference/cli/)
- [devenv: интеграция SecretSpec](https://devenv.sh/integrations/secretspec/)
- [SQLx: PgConnectOptions и PG-переменные](https://docs.rs/sqlx/latest/sqlx/postgres/struct.PgConnectOptions.html)
- [devenv 2.3: Portless, Pingora и HTTPS](https://devenv.sh/blog/2026/09/07/devenv-23-portless-and-tui-configuration/)

### Короткое примечание о reverse proxy

Локальные HTTP-адреса Portless в devenv обслуживает **встроенный общий reverse proxy на базе Pingora (Cloudflare)**. Это не отдельный Nginx/Caddy. HTTPS, если позже понадобится, включается через `processes.<name>.proxy.https.enable` с сертификатами `mkcert`.
