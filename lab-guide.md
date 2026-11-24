# Лабораторные работы №6–9

В четырёх работах ты соберёшь API «Пирожки с предсказаниями», научишься запускать его в
двух клонах, восстанавливать данные из резервной копии и проверять изменения через
GitHub Actions. Команды ниже рассчитаны на Bash или Zsh в Linux. Запуск в Windows описан
в [README](README.md#%D0%B7%D0%B0%D0%BF%D1%83%D1%81%D0%BA-%D0%B2-windows), список
требований — в [задании на реализацию](lab-implementation.md).

В примерах база называется `prediction_pies`, а таблица — `pies`, как в лабораторной №6.
Эти имена используются и в следующих работах.

## №6. API и локальная база

`devenv.nix` описывает инструменты и сервисы проекта. `devenv shell` делает доступными
Rust, SQLx CLI и переменные окружения. `devenv up` запускает PostgreSQL. У каждого клона
свой каталог данных и свой Unix-сокет, через который приложение подключается к базе.

Когда приходит `GET /pie`, Axum передаёт запрос обработчику. Обработчик берёт соединение
из пула SQLx, выбирает случайную строку из `pies` и возвращает JSON. В этой работе
`query_as` с `FromRow` преобразует строку результата в Rust-структуру, а запрос
проверяется при выполнении.

```bash
devenv --profile lab6 up -d
devenv --profile lab6 shell
export PGUSER="$(id -un)"
sqlx migrate run --target-version 1
psql "$DATABASE_URL" -c 'SELECT count(*) FROM pies;'
cargo run --locked --features lab6
```

Во втором терминале выполни `xh :3000/pie`. Пример ответа:

```json
{
  "id": "7bcf1ad0-4d12-4fd3-b754-415e74234f10",
  "prediction": "Сегодня повезёт",
  "created_at": "2026-11-24T08:00:00Z"
}
```

**Шпаргалка.** `DATABASE_URL` указывает на PostgreSQL, `APP_ADDR` задаёт адрес
HTTP-сервера, `sqlx migrate info` показывает состояние миграций. Если приложение
сообщает, что таблицы нет, проверь, что миграции применены к той же базе, к которой
подключается API. Повтори запуск в свежем клоне, чтобы проверить, что схема и начальные
данные восстанавливаются из файлов проекта. [Сценарий №6](Labs/script.md)

## №7. Миграции, два клона и качество кода

В `migrations/002_add_prediction_category.sql` добавь
`ALTER TABLE pies ADD COLUMN category TEXT NOT NULL DEFAULT 'general';`. Значение
`general` получат и существующие строки. Для учебного отката выполни
`bash scripts/revert-category.sh`. Он передаёт SQLx обратную миграцию из временного
каталога. При откате значения в колонке `category` будут удалены.

Настрой `devenv up` так, чтобы миграции запускались после готовности PostgreSQL, а API
стартовал после успешной миграции. В Rust адаптируй запрос под `sqlx::query!`. Например,
запрос ниже читает категорию, а в JSON по-прежнему можно вернуть три поля из №6.

```sql
SELECT id, prediction, created_at, category
FROM pies
ORDER BY random()
LIMIT 1;
```

С запущенной БД и применённой миграцией попробуй заменить в макросе `category` на
`categories`. `cargo check` покажет ошибку столбца. Исправь запрос и повтори проверку.

Два клона могут работать одновременно, если каждому выделены собственные порты
PostgreSQL и API. `PGPORT` входит в строку подключения к БД, а из `PORT` приложение
берёт порт HTTP-сервера. Portless направляет запросы по `API_URL` на порт нужного клона.
Имя вычисляется из пути каталога, поэтому после перезапуска в том же каталоге URL
сохраняется.

**Шпаргалка.**

- `direnv allow` разрешает загрузку проверенного `.envrc` при входе в каталог.
- `psql "$DATABASE_URL" -Atc 'SELECT current_database(), inet_server_port();'`
  показывает базу и фактический TCP-порт. Сравни вывод в двух клонах и вызови `GET /pie`
  по обоим значениям `API_URL`.
- `fmt` исправляет форматирование. `chk` проверяет форматирование и запускает ShellCheck
  и Clippy.
- `prek install` устанавливает хуки. `pre-commit` запускает `chk`, а `commit-msg`
  проверяет сообщение через `convco`. Пример Conventional Commit —
  `feat(db): add prediction category`. [Сценарий №7](Labs/07-scenario.md)

## №8. Бэкапы и секреты

`pg_dump` выгружает SQL, `zstd` сжимает его, GPG шифрует сжатый поток. В
`scripts/db-backup.sh` включи `pipefail`, чтобы сбой любой команды считался ошибкой
всего конвейера. Записывай зашифрованный результат во временный файл и переноси в
итоговый путь после успеха. С помощью `umask 077` ограничь доступ к создаваемым файлам.

Пример для обычного локального режима. Для создания архива укажи отпечаток учебного
ключа в `GPG_RECIPIENT`. Восстановление выполняй в отдельной пустой БД через локальный
сокет.

```bash
PGUSER=pies_local bash scripts/db-backup.sh backups/pies.sql.zst.gpg
RESTORE_DB=prediction_pies_restore
socket="$DEVENV_RUNTIME/postgres"
createdb -h "$socket" -U "$(id -un)" "$RESTORE_DB"
set -o pipefail
gpg --decrypt backups/pies.sql.zst.gpg \
  | zstd -d \
  | psql -X -h "$socket" -U "$(id -un)" --set ON_ERROR_STOP=on --dbname "$RESTORE_DB"
psql -X -h "$socket" -U "$(id -un)" --dbname "$RESTORE_DB" -c 'SELECT count(*) FROM pies;'
```

`pass` хранит значения в файлах, зашифрованных GPG. SecretSpec описывает потребность
проекта в `PGPASSWORD`, выбирает пароль по профилю и передаёт его процессу. Настрой
парольную аутентификацию в учебном PostgreSQL и убери пароль из `DATABASE_URL`. Учти,
что секрет может понадобиться и задаче миграций, если она подключается к БД с той же
ролью.

**Шпаргалка.**

- `secretspec set PGPASSWORD --profile development` сохраняет пароль для разработки.
  Повтори с профилем `staging` и соответствующим паролем.
- `secretspec check --profile development` проверяет, что значение доступно.
  `secretspec run --profile development -- cargo run` передаёт его при запуске API.
- Расширение `pass fzf` ищет имена записей. При выборе оно вызывает, например,
  `pass show --clip demo/example`, чтобы скопировать значение в буфер обмена.
- В Git добавь декларацию `secretspec.toml`. Архивы, пароли и закрытые ключи держи вне
  истории Git. [План №8](Labs/lab08_plan.md)

## №9. CI, тест и тег

GitHub Actions проверяет код после отправки изменений. В workflow установи Nix и devenv,
подключи кеш Cachix и запусти через devenv те же команды, которыми пользуешься локально.
`cargo test --locked` использует версии из `Cargo.lock`.

SQLx Offline позволяет собрать код с `query!` на runner без подключения к базе. Сначала,
пока учебная БД доступна и миграции применены, сгенерируй метаданные. Затем проверь, что
команды работают с ними.

```bash
cargo sqlx prepare -- --all-targets
SQLX_OFFLINE=true devenv shell -- chk
SQLX_OFFLINE=true devenv shell -- cargo test --locked
```

Закоммить `.sqlx/` и включи `SQLX_OFFLINE=true` в workflow. При изменении SQL или схемы
обнови метаданные. Настрой CI так, чтобы окружение поднималось без локального `pass`.
Unit-тесту достаточно чистой функции, например проверки текста предсказания:

```rust
#[test]
fn rejects_blank_prediction() {
    assert!(!is_valid_prediction("   "));
    assert!(is_valid_prediction("Удача рядом"));
}
```

Здесь `is_valid_prediction` может возвращать `!s.trim().is_empty()`. В демонстрационной
ветке измени ожидаемый результат, посмотри причину падения в GitHub Actions и верни
корректную проверку.

**Шпаргалка.** Workflow лежит в `.github/workflows/ci.yml`. События `push`,
`pull_request` и `workflow_dispatch` запускают его при отправке изменений, для pull
request и вручную. После успешного CI на нужном коммите в `main` создай аннотированный
тег командой `git tag -a v0.1.0 -m "Fortune Pies 2026"` и опубликуй его через
`git push origin v0.1.0`. [Сценарий №9](Labs/lab09_detailed_slide_notes.md)
