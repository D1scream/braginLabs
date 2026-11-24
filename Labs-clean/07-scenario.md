# Лабораторная работа №7. Окружение и качество кода

**Тема:** Воспроизводимость базы данных, автоматизация запуска и контроль качества кода.

**Проект:** «Пирожки с предсказаниями»: Rust, Axum, SQLx, PostgreSQL и devenv.

## 1. Введение

**Автоматизация окружения и контроль качества**\
`devenv` · `direnv` · `PostgreSQL` · `SQLx` · `Portless` · `prek` · `convco`

«В шестой лабораторной мы создали сервис “Пирожки с предсказаниями”: Rust, Axum,
PostgreSQL, первая миграция и HTTP-эндпоинт. Главное достижение — проект можно
склонировать и поднять в воспроизводимом окружении devenv. Сегодня доведём это до
удобного ежедневного процесса: будем изменять базу миграциями, запускать несколько
клонов без конфликта портов, автоматически проверять исходники и сообщения коммитов».

```sh
pwd
git status --short
command -v sqlx
sqlx --version
```

«Команда `sqlx` уже есть, потому что в лабораторной №6 мы добавили пакет `pkgs.sqlx-cli`
в `packages` devenv. Не путайте CLI и Rust-крейт `sqlx`: первый управляет миграциями,
второй используется в коде».

Команда `sqlx` доступна в Nix-окружении.

## 2. Воспроизводимость: три составляющие

```text
devenv.nix + devenv.lock → инструменты и сервисы
migrations/              → схема и начальные данные
скрипты + Git hooks      → одинаковые команды и правила
```

«Мало установить одинаковые версии Rust и PostgreSQL. Если у одного разработчика в базе
есть новый столбец, а у другого нет, окружение всё ещё невоспроизводимо. Поэтому историю
изменений схемы нужно хранить в Git рядом с кодом. И точно так же нам нужны общие
правила форматирования и проверок».

## 3. direnv

```sh
# .envrc
eval "$(devenv direnvrc)"
use devenv
```

`cd project/` → загрузка devenv; `cd ..` → выгрузка.

«На прошлом занятии мы вручную входили в `devenv shell`. А direnv умеет активировать
окружение при смене каталога. После проверки содержимого `.envrc` мы один раз разрешаем
этот файл командой `direnv allow`. Обратите внимание: devenv начиная с версии 2 также
предлагает собственный `devenv hook`; direnv — один из вариантов, который мы сегодня
демонстрируем».

Подключи хук direnv в Zsh:

```sh
# ~/.zshrc, однократно
eval "$(direnv hook zsh)"
```

В проекте:

```sh
printf 'eval "$(devenv direnvrc)"\nuse devenv\n' > .envrc
direnv allow
cd ..
cd fortune-pies
command -v sqlx
```

При возвращении в каталог `sqlx` доступен без явного `devenv shell`. `.envrc` допустимо
закоммитить; `direnv allow` остаётся личным подтверждением.

`chore(dev): enable direnv activation`

## 4. Миграции SQLx

```text
migrations/
  2026..._initial.sql
  2026..._add_prediction_category.up.sql
  2026..._add_prediction_category.down.sql
```

`up` — применить, `down` — отменить.\
`_sqlx_migrations` — учёт применённых версий.

«В лабораторной №6 наша первая миграция создала таблицу предсказаний и заполнила её.
Изменять тот файл задним числом нельзя: у тех, кто уже применил миграцию, база не
изменится. Вместо этого создаём **новую** миграцию. Это не только способ обновить базу,
но и условие воспроизводимости: новый клон может получить ту же структуру по версии
исходников».

```sh
sqlx migrate info
sqlx migrate add -r add_prediction_category
```

Запиши SQL в созданные файлы `*.up.sql` и `*.down.sql`.

```sql
-- .up.sql
ALTER TABLE predictions
ADD COLUMN category TEXT NOT NULL DEFAULT 'general';
```

```sql
-- .down.sql
ALTER TABLE predictions
DROP COLUMN category;
```

«Добавим категорию предсказания. `NOT NULL` означает обязательное значение, а
`DEFAULT 'general'` позволяет мигрировать таблицу, где уже есть строки. Опция `-r`
создаёт пару обратимых миграций. Обратите внимание: `down` здесь удалит колонку и её
данные. Откаты не всегда безвредны».

```sh
sqlx migrate run
sqlx migrate info
psql "$DATABASE_URL" -c '\d predictions'
psql "$DATABASE_URL" -c 'SELECT version, description, success FROM _sqlx_migrations ORDER BY version;'
```

У `predictions` появился столбец `category`; состояние последней миграции —
applied/success. При повторном `sqlx migrate run` ничего повторно не меняется.

«Миграции выполняются последовательно и сохраняют историю в БД. Если изменить файл уже
применённой миграции, проверка контрольных сумм может обнаружить расхождение. Поэтому
исправления выпускают **следующей** миграцией».

`feat(db): add categories to predictions`

## 5. Демонстрационная автоматизация app:migrate

```text
PostgreSQL (@ready)
       ↓
app:migrate (sqlx migrate run)
       ↓
Axum API
```

«Теперь закрепим порядок запуска: сначала база готова принимать подключения, затем
применяется схема, и только после этого стартует API. В devenv процессы представлены
также задачами, поэтому можно объявить зависимости. Для **локального учебного проекта**
это удобно, но автоматический запуск миграций — не универсальная практика: на сервере
изменения схемы часто запускают отдельным контролируемым этапом развёртывания».

Фрагмент `devenv.nix`:

```nix
tasks."app:migrate" = {
  exec = "sqlx migrate run";
  after = [ "devenv:processes:postgres@ready" ];
};
processes.api.after = [ "app:migrate" ];
```

После `devenv up` задача миграций завершается до старта API. Параметры `before` и
`after` задают зависимости между задачами.

## 6. Макросы SQLx и cargo check / clippy

```text
query(...)    — запрос проверяется при выполнении
query!(...)   — SQLx проверяет SQL по схеме при сборке
```

| Команда | Что проверяет | |---|---| | `cargo check` | компиляцию без генерации
готового бинарника | | `cargo clippy` | компиляцию + дополнительные lint-проверки |

«Есть существенная разница между функцией `sqlx::query` и макросом `sqlx::query!`.
Макрос связывается с действующей схемой PostgreSQL **во время компиляции**. Поэтому
после миграции меняется не только база, но и то, какой SQL скомпилируется. Для этого
`DATABASE_URL` должен вести к запущенной актуальной БД».

Пример макроса SQLx для существующего обработчика:

```rust
let row = sqlx::query!(
    "SELECT prediction, category FROM predictions ORDER BY random() LIMIT 1"
)
.fetch_one(&pool)
.await?;
```

Затем намеренно пишем `categories` вместо `category` и запускаем:

```sh
cargo check
```

Восстанавливаем `category` и снова запускаем `cargo check`.

«`cargo check` проверяет, что код компилируется, но не создаёт готовый исполняемый файл.
`cargo clippy` тоже проверяет компиляцию, а дополнительно ищет подозрительные и
неидиоматичные конструкции Rust. Позже наша команда `chk` будет запускать Clippy, а
отдельный `cargo check` дублировать не будем».

Ошибка неверного столбца возникает до запуска API. После исправления запрос проходит
проверку.

## 7. Два клона по TCP: независимые порты

```text
Clone A: Postgres → 127.0.0.1:5432; API → 127.0.0.1:3000
Clone B: Postgres → 127.0.0.1:5433; API → 127.0.0.1:3001
```

*Номера иллюстративные; devenv выбирает реально свободные порты.*

«По умолчанию локальная PostgreSQL в devenv использует Unix-сокет. Сейчас включим TCP:
это делает URL привычным для разных клиентов и одновременно позволяет увидеть проблему
конфликтов портов. В devenv порт у PostgreSQL и у нашего API можно выделять
автоматически. Данные двух копий остаются в независимых каталогах. Важно не прописывать
`localhost:5432` как неизменяемую константу».

Фрагмент `devenv.nix`, добавляем к существующим `services.postgres` и `processes.api`:

```nix
services.postgres.listen_addresses = "127.0.0.1";
services.postgres.port = 5432;

env.DATABASE_URL =
  "postgresql://pies:pies@127.0.0.1:${toString config.env.PGPORT}/pies";

processes.api.ports.http.allocate = 3000;
processes.api.env.PORT = toString config.processes.api.ports.http.value;
```

В Axum вместо `127.0.0.1:3000`:

```rust
let port: u16 = std::env::var("PORT")?.parse()?;
let listener = tokio::net::TcpListener::bind(("127.0.0.1", port)).await?;
axum::serve(listener, app).await?;
```

**Проверка при переносе конфигурации №6:** `initialDatabases` создаёт базу и роль только
при первой инициализации конкретного `PGDATA`. Если старая база уже существует, замена
параметров `initialDatabases` не создаст задним числом роль `pies`; приведите
`DATABASE_URL` к существующему пользователю и БД (или создайте необходимые роли
отдельной операцией). Не удаляйте рабочую базу ради демонстрации.

В двух терминалах, каждый в своём каталоге:

```sh
devenv up
```

В оболочках этих каталогов отдельно:

```sh
echo "$DATABASE_URL"
psql "$DATABASE_URL" -Atc 'SELECT current_database(), inet_server_port();'
```

У A и B различаются реальные порты PostgreSQL; `devenv up` показывает разные порты API.
Если базы оба раза на 5432, значит первый экземпляр не был запущен либо не слушает TCP.

«Здесь пароль `pies` — исключительно учебный локальный пример. В реальном проекте
секреты не хранят в публичной конфигурации — этот вопрос разберём позже».

`build(dev): allocate TCP ports for local services`

## 8. Portless и устойчивые уникальные имена

```text
             HTTP Host: api.fortune-pies-<id>.localhost
                              ↓
                    общий localhost proxy
                       /             \
                 Clone A             Clone B
                  :3000               :3001
```

Идентификатор `<id>` = короткий хеш **пути каталога клона**.

«Автоматический порт решает конфликт, но теперь URL меняется. Portless добавляет
локальный HTTP reverse proxy: клиент обращается к красивому `.localhost`-имени, а прокси
перенаправляет запрос на текущий порт API. Для двух клонов стандартное имя проекта было
бы одинаковым, поэтому вычислим часть имени из корневого пути проекта. Это не механизм
проверки свободного имени, а детерминированное вычисление: один и тот же каталог
получает то же имя».

В `devenv.nix`:

```nix
{ config, ... }:
let
  instanceId = builtins.substring 0 12 (
    builtins.hashString "sha256" config.devenv.root
  );
  apiHostname = "api.fortune-pies-${instanceId}.localhost";
in {
  process.proxy.enable = true;
  processes.api.proxy.hostname = apiHostname;
  env.API_URL = "http://${apiHostname}";
}
```

*Это фрагмент для объединения с уже существующим `devenv.nix`; не создавать вторую
верхнеуровневую функцию.*

Перезапускаем `devenv up` в обоих каталогах, смотрим ссылки в интерфейсе и открываем
каждый адрес API. Также выводим:

```sh
echo "$API_URL"
```

«Здесь Portless нужен только для HTTP. Строка `DATABASE_URL` по-прежнему содержит
настоящий TCP-порт PostgreSQL. На Linux для локального прокси с портом 80 devenv может
запросить `sudo`. Если CLI не умеет разрешать поддомены `.localhost`, демонстрацию лучше
провести в браузере».

Оба URL различаются, а ответы API доступны при любом выбранном свободном backend-порте.

`build(dev): assign per-clone portless hostnames`

## 9. Инструменты качества

| Язык | `fmt` | `chk` | |---|---|---| | Markdown | `mdformat` | `mdformat --check` | |
Shell | `shfmt` | `shfmt -d`, `shellcheck` | | Rust | `cargo fmt` | `cargo fmt --check`,
`cargo clippy` |

«Теперь автоматизируем рутину. Мы хотим две отдельные команды: `fmt` действительно
исправляет форматирование, а `chk` ничего не меняет и возвращает ошибку при проблемах.
Для Markdown будет mdformat, для shell — shfmt и ShellCheck, для Rust — rustfmt и
Clippy. ShellCheck и Clippy не форматтеры: они ищут ошибки и плохие практики».

В `packages` добавляем `prek`, `convco`, `mdformat`, `shfmt`, `shellcheck`; Rust, SQLx
CLI и PostgreSQL уже из №6:

```nix
packages = with pkgs; [
  sqlx-cli xh prek convco mdformat shfmt shellcheck
];
```

«У нас уже есть компилятор, Rustfmt и Clippy благодаря `languages.rust.enable = true`.
Инструменты здесь фиксируются через devenv и `devenv.lock`, чтобы студент не искал
разные версии вручную».

## 10. Единый скрипт quality.sh

```text
             scripts/quality.sh
                  ┌───┴───┐
                  fmt     chk
               исправить  проверить
                  │         │
             те же файлы, те же параметры
```

«Главная опасность — когда форматтер и проверка живут в разных конфигурациях: в одной
изменили отступ, а в другой забыли. Поэтому выбор файлов и все общие параметры хранятся
в **одном** `scripts/quality.sh`. Devenv лишь объявляет удобные команды, ничего не
дублирует. В скрипте одинаковые массивы `md_options`, `sh_options`, одинаковая функция
поиска файлов; разными будут только ключи `--check` и `-w` или `-d`».

Фрагмент `scripts/quality.sh`:

```bash
md_options=(--wrap 88)
sh_options=(-ln bash -i 2 -ci)
mapfile -d '' -t md_files < <(collect_files '*.md' '*.markdown')
mapfile -d '' -t sh_files < <(collect_files '*.sh' '*.bash' '.envrc')
```

В `devenv.nix` оставляем только объявления:

```nix
scripts.fmt.exec =
  "bash ${config.devenv.root}/scripts/quality.sh fmt";
scripts.chk.exec =
  "bash ${config.devenv.root}/scripts/quality.sh chk";
```

Далее намеренно портим форматирование одного Markdown-файла и выполняем:

```sh
chk          # ожидается ошибка
fmt          # автоматическое исправление
chk          # успешная проверка
```

После `fmt` повторный `chk` проходит; `chk` не изменяет файлы. Если остаются
предупреждения ShellCheck или Clippy, их надо исправить вручную.

«Наши `chk` и `fmt` проверяют файлы рабочего дерева, а не только staged-версию Git. Это
простой учебный выбор: позже при необходимости настроим проверку строго по индексу или в
CI».

`chore: add shared formatting and checking commands`

## 11. Git-хуки, prek, convco

```text
git commit
   ↓
pre-commit → prek → scripts/quality.sh chk
   ↓
commit-msg → prek → convco check
   ↓
создание коммита (только при успехе)
```

«Git-хуки — скрипты, которые Git автоматически вызывает в определённых точках операции.
У нас будут два. `pre-commit` проверяет исходники, а `commit-msg` проверяет уже
подготовленный текст сообщения. У Git есть сам механизм, а prek помогает раздавать одну
конфигурацию всем участникам проекта и устанавливать хуки без ручного копирования в
`.git/hooks`».

Создать `.pre-commit-config.yaml`:

```yaml
default_install_hook_types:
  - pre-commit
  - commit-msg
repos:
  - repo: local
    hooks:
      - id: chk
        name: Check project
        entry: bash scripts/quality.sh chk
        language: system
        stages: [pre-commit]
        pass_filenames: false
        always_run: true
      - id: conventional-commit
        name: Check Conventional Commit
        entry: bash scripts/check-commit-msg.sh
        language: system
        stages: [commit-msg]
        pass_filenames: true
        always_run: true
```

В `scripts/check-commit-msg.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
convco check --from-stdin --strip < "$1"
```

*Итоговый скрипт в материалах дополнительно проверяет число аргументов и существование
файла.*

«Почему отдельная стадия `commit-msg`? Во время `pre-commit` окончательного сообщения
ещё нет. Git передаёт `commit-msg` путь к файлу с подготовленным текстом. Скрипт
передаёт его в стандартный ввод convco, который проверяет формат
`type(scope): description`. Флаг `--strip` убирает служебные комментарии Git и лишние
пробелы».

```sh
prek install
printf 'bad commit message\n' | convco check --from-stdin
printf 'feat(db): add categories\n' | convco check --from-stdin

# Затем реальный опыт с хуками:
git add .
git commit -m "update project"        # Failed
git commit -m "chore(git): enforce commit conventions"   # Passed
```

Плохое сообщение блокируется **до создания коммита**, хорошее проходит оба этапа.
Обратить внимание, что `prek install` установил и `pre-commit`, и `commit-msg` благодаря
`default_install_hook_types`.

«Локальные хуки — удобная первая линия защиты, но их можно обойти, например
`--no-verify`. Для командного проекта те же проверки стоит дополнительно запускать в CI.
Генерацию текстов коммитов через Codex сейчас не делаем — перенесём на отдельное
занятие».

## 12. Итоги

```text
Клон проекта → direnv → devenv
  PostgreSQL (свободный TCP-порт)
  → SQLx миграции → Axum API (Portless)
  → fmt / chk → prek → convco → Git commit
```

**Следующая лабораторная №8:** `cargo sqlx prepare`, тесты, логирование, Docker-сборка
для сервера, `pass` и SecretSpec; позже — помощь Codex с коммитами.

«Теперь один репозиторий содержит не только приложение, но и инструкцию, как получить
его базу, как его запустить, как проверять код и как оформлять изменения. Два клона
спокойно работают одновременно благодаря выделяемым портам и Portless. И самое важное:
миграции делают воспроизводимой не только среду инструментов, но и структуру базы
данных. В следующей работе займёмся сборкой и жизненным циклом приложения — проверкой
запросов без подключённой БД, тестами, логированием, секретами и подготовкой под
сервер».

В обоих клонах доступны API. `chk` проходит. `git log -1 --format=%s` показывает
conventional commit.

______________________________________________________________________

## Контрольные команды

```sh
sqlx --version
sqlx migrate info
sqlx migrate run
cargo check
cargo clippy --workspace --all-targets --all-features -- -D warnings
echo "$DATABASE_URL"
echo "$API_URL"
fmt
chk
prek install
prek run --all-files
printf 'docs: update setup guide\n' | convco check --from-stdin
```

`prek run --all-files` сам по себе запускает только соответствующие файл-ориентированные
хуки; проверку `commit-msg` демонстрируем реальным `git commit`, где Git передаёт файл
сообщения.

## Источники

- `devenv` 2.3+ для Portless; PostgreSQL выделяет порт автоматически при активном TCP
  listener: https://devenv.sh/processes/ и https://devenv.sh/services/postgres/.
- Задачи `app:migrate` и порядок `postgres@ready` → `api`: https://devenv.sh/tasks/.
- direnv `eval "$(devenv direnvrc)"; use devenv`:
  https://devenv.sh/integrations/direnv/.
- SQLx CLI и миграции: https://github.com/launchbadge/sqlx/tree/main/sqlx-cli.
- SQLx макросы: https://docs.rs/sqlx/latest/sqlx/macro.query.html.
- prek YAML и стадии: https://prek.j178.dev/reference/configuration/.
- convco проверка stdin: https://convco.github.io/check/.
