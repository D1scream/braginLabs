# Лабораторная работа №6. devenv и Prediction Pies API

**Проект:** Rust + Axum + SQLx + PostgreSQL\
**Идея приложения:** API «пирожков с предсказаниями»\
**Endpoint:** `GET /pie`

## 1. Вступление

`devenv` — инструментом для воспроизводимых окружений разработки на базе Nix.

Сделаем небольшой API пирожков с предсказаниями.
Приложение будет на Rust и Axum, данные будем хранить в PostgreSQL, а работать с базой через SQLx.

Само приложение я буду в основном вайбкодить через Codex прямо в терминале. 
Нас в первую очередь интересует не синтаксис Axum, а то, как проект описывает всё окружение, необходимое для разработки.

Начинаем с пустого каталога.

## 2. Пустой репозиторий и devenv

```sh
cd ~/path/to/06-devenv/projects
mkdir prediction-pies
cd prediction-pies
git init
devenv init
```

Пока `devenv` получает свои входы, пару слов о Nix.

Обычный сценарий часто начинается с инструкции: установите такую версию компилятора,
затем такую базу данных, затем ещё несколько утилит.

Nix предлагает другой подход. Мы декларативно описываем, что нам нужно получить, а Nix
строит соответствующее окружение.

При этом разные версии пакетов могут существовать рядом, потому что результаты хранятся
отдельно в Nix store.

Для сегодняшнего занятия достаточно держать в голове три свойства: декларативность,
воспроизводимость и изоляцию.

```sh
ls -la
cat devenv.nix
```

`devenv init` создал стартовое описание окружения.

Главный файл для нас — `devenv.nix`. В нём постепенно появятся язык, база данных,
CLI-инструменты и переменные окружения.

Сразу начнём нормальную историю Git.

```sh
git status --short
git add .
git commit -m 'chore: initialize development environment'
```

Мы уже проходили Conventional Commits, поэтому используем их с первого commit.

Здесь пользовательской функциональности ещё нет — только начальная инфраструктура
проекта, поэтому `chore`.

______________________________________________________________________

## 3. Rust как часть окружения

Открыть `devenv.nix` и добавить:

```nix
languages.rust.enable = true;
```

```sh
devenv shell
```

Пока окружение перестраивается, вспомним первые два принципа Twelve-Factor App.

Первый — **Codebase**: одна кодовая база находится под version control и может иметь
несколько развёртываний.

Мы как раз начали с Git-репозитория.

Второй — **Dependencies**: зависимости должны быть явно объявлены и изолированы.

Rust у нас появился не потому, что я попросил каждого студента отдельно установить его в
систему. Необходимость Rust теперь записана в самом проекте.

```sh
rustc --version
cargo --version
```

```sh
cargo init .
cargo run
```

Получили обычный `Hello, world!`, но важный момент — `cargo` и `rustc` пришли из
development environment проекта.

```sh
git add .
git commit -m 'chore: initialize Rust application'
```

______________________________________________________________________

## 4. Первый checkpoint

Зафиксируем, где мы находимся.

История пока очень короткая: сначала мы описали development environment, затем создали
Rust-приложение.

Дальше нам понадобится PostgreSQL.

Но перед этим важно не смешивать два разных уровня зависимостей.

`axum`, `sqlx`, `serde` и другие Rust crates — это зависимости самой программы. Их
описывает `Cargo.toml`, а конкретное разрешение версий фиксирует `Cargo.lock`.

Компилятор Rust, PostgreSQL, HTTP-клиент и другие инструменты разработчика — это уже
зависимости окружения.

То есть Cargo отвечает на вопрос: «от чего зависит моя программа?»

А devenv — «что мне нужно, чтобы работать над этим проектом?»

Это связанные, но разные задачи.

______________________________________________________________________

## 5. Первый Codex: PostgreSQL и SQLx CLI

```sh
codex
```

Минимальный фундамент я специально сделал руками.

Теперь будем расширять проект маленькими заданиями для Codex. После каждого законченного
изменения посмотрим diff и commit сделаем сами.

### Запрос для Codex

```text
Configure this project for PostgreSQL development with devenv.

Requirements:

- keep the existing Rust support;
- enable the devenv PostgreSQL service;
- create an initial database named `prediction_pies`;
- keep PostgreSQL on devenv's default project-local Unix socket;
- add `sqlx-cli` to the development packages;
- expose `DATABASE_URL` for SQLx and the application, pointing to
  the `prediction_pies` database through devenv's PostgreSQL socket;
- do not modify the Rust application yet.

Keep the configuration minimal.
Do not create a git commit.

When finished, summarize the changes and show the relevant diff.
```

```sh
git diff
```

Проверить смысл, а не буквальное совпадение:

- `services.postgres.enable = true`;
- `initialDatabases` содержит `prediction_pies`;
- `sqlx-cli` доступен в environment;
- `DATABASE_URL` использует проектный PostgreSQL socket;
- в Rust-код Codex пока не полез.

Если Codex сделал TCP `localhost:5432`, попросить исправить:

### Запрос для Unix-сокета

```text
Use devenv's project-local PostgreSQL Unix socket instead of a hard-coded
localhost TCP endpoint. `DATABASE_URL` must remain usable by SQLx.
```

Перезайти в environment, чтобы получить новые пакеты и переменные:

```sh
exit
devenv shell
echo "$DATABASE_URL"
devenv up -d
```

Третий принцип Twelve-Factor — **Config**.

Конфигурация, которая может различаться между окружениями, не должна быть зашита в
исходный код. Она передаётся через environment.

У нас уже появился хороший конкретный пример — `DATABASE_URL`.

Rust-коду не нужно знать, где именно на моём компьютере находится socket PostgreSQL. Он
получает строку подключения снаружи.

Четвёртый принцип — **Backing services**.

База данных, очередь, cache, SMTP — приложение рассматривает их как подключаемые
ресурсы.

Сегодня PostgreSQL локальный и запускается devenv. В другом окружении он может жить
совсем на другой машине. Для приложения это прежде всего изменение конфигурации
подключения.

```sh
psql prediction_pies -c 'select current_database();'
psql prediction_pies -c '\dt'
```

База уже существует, но таблиц пока нет.

```sh
git add .
git commit -m 'build: add PostgreSQL development service'
```

______________________________________________________________________

## 6. Checkpoint PostgreSQL

Теперь репозиторий описывает уже не только Rust toolchain, но и PostgreSQL.

А связь приложения с базой передаётся через `DATABASE_URL`.

Следующий шаг — создать данные.

______________________________________________________________________

## 7. SQLx и одна миграция

### Запрос для Codex

```text
Add the database layer with SQLx.

Requirements:

- add the Rust dependencies needed for PostgreSQL SQLx support;
- use Tokio;
- use UUID for IDs;
- use a timezone-aware Rust type for PostgreSQL TIMESTAMPTZ;
- use runtime-checked `sqlx::query_as` with `FromRow`;
- do NOT use SQLx compile-time query macros in this lesson;
- create exactly one SQLx migration using `sqlx migrate add`.

The migration must create this table:

pies
- id: UUID PRIMARY KEY generated by PostgreSQL;
- prediction: TEXT NOT NULL;
- created_at: TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP.

The same migration must insert around 8–10 short predictions in Russian.

Do not implement the HTTP API yet.
Do not create a git commit.

At the end, summarize the changed files.
```

```sh
git status --short
git diff
ls migrations
cat migrations/*.sql
```

Миграция — это обычный SQL-файл.

В нашем маленьком учебном проекте одна первоначальная миграция сразу создаёт таблицу и
добавляет начальный набор предсказаний.

В большом приложении schema migrations и seed data вполне могут жить отдельно.

```sh
sqlx migrate run
```

Миграции хорошо иллюстрируют двенадцатый принцип Twelve-Factor — **Admin processes**.

Это разовая административная задача, а не постоянно работающий web process.

При этом она выполняется из того же кода и в том же окружении, что и приложение.

Сегодня миграции запускаем руками командой `sqlx migrate run`.

На следующем занятии отдельно улучшим этот workflow.

```sh
sqlx migrate info
psql prediction_pies -c \
  'select id, prediction, created_at from pies limit 3;'
```

Данные на месте.

И ещё одна оговорка: сегодня запросы SQLx будем проверять во время выполнения. На
следующей лекции отдельно посмотрим на compile-time query checking.

```sh
cargo fmt
cargo check
```

```sh
git add .
git commit -m 'feat: add pie database'
```

______________________________________________________________________

## 8. Checkpoint базы

Теперь у нас есть настоящая прикладная часть проекта: таблица пирожков с UUID, текстом
предсказания и временем создания.

Следующий маленький шаг — единственный HTTP endpoint.

______________________________________________________________________

## 9. Axum: GET /pie

### Запрос для Codex

```text
Implement the HTTP API with Axum.

Requirements:

- add Axum and only the missing runtime/serialization dependencies;
- create a SQLx PgPool from `DATABASE_URL`;
- read the bind address from an environment variable named `APP_ADDR`;
- add `APP_ADDR = "127.0.0.1:3000"` to devenv;
- use Axum state to share the PgPool;
- expose exactly one endpoint:

  GET /pie

- select one random row from `pies`;
- use runtime-checked `sqlx::query_as`, not compile-time query macros;
- return JSON with exactly:

  {
    "id": UUID,
    "prediction": string,
    "created_at": timestamp
  }

Keep the project intentionally small.
Do not add logging, middleware, OpenAPI, tests, or an error-handling framework.
Do not create a git commit.

Run formatting and compilation checks when finished.
```

Пока Cargo впервые собирает Axum и SQLx, ещё несколько принципов.

Пятый — **Build, release, run**: сборка приложения и его запуск — разные стадии.

Сейчас Cargo превращает исходники и зависимости в исполняемый код.

Шестой — **Processes**.

Web-приложение работает как процесс, а постоянное состояние мы не держим в его памяти —
оно находится в PostgreSQL.

Седьмой — **Port binding**.

Приложение само предоставляет HTTP-сервис через сетевой адрес.

И даже этот адрес мы не зашиваем в код: он приходит через `APP_ADDR`.

```sh
git diff
cargo run
```

В другом терминале временно проверить через `curl`:

```sh
curl http://127.0.0.1:3000/pie
```

Повторить:

```sh
curl http://127.0.0.1:3000/pie
```

Каждый запрос получает случайный пирожок из PostgreSQL.

Остановить приложение:

```text
Ctrl+C
```

```sh
cargo fmt --check
cargo check
```

```sh
git add .
git commit -m 'feat: add random pie endpoint'
```

______________________________________________________________________

## 10. Архитектура и xh

Теперь полный путь запроса очень короткий.

HTTP-запрос приходит в Axum, через SQLx pool выполняется запрос к PostgreSQL, выбирается
случайная запись, и клиент получает JSON.

`curl` с задачей справился, но для ручной работы с HTTP API я предпочитаю `xh`.

### Запрос для Codex

```text
Add `xh` to the devenv development packages.

Do not change the Rust application.
Do not create a git commit.

Show the resulting configuration diff.
```

Перезайти в shell при необходимости:

```sh
exit
devenv shell
```

Это ещё один маленький пример идеи development environment.

Можно было установить `xh` глобально в операционную систему.

Но тогда проект молча предполагал бы, что у каждого разработчика эта утилита уже есть.

Вместо этого мы записываем: `xh` нужен именно этому проекту.

У другого репозитория набор инструментов может быть совершенно другим.

```sh
xh --version
```

Запустить приложение:

```sh
cargo run
```

Из второго терминала:

```sh
xh :3000/pie
xh :3000/pie
```

Двоеточие у `xh` — короткая запись для localhost.

Получили простой и удобный способ проверять endpoint из терминала.

Остановить приложение.

```sh
git add .
git commit -m 'build: add xh HTTP client'
```

______________________________________________________________________

## 11. Fresh clone: главная демонстрация

Проверь пути каталогов данных и сокета PostgreSQL:

```sh
printf 'PGDATA=%s\nPGHOST=%s\n' "$PGDATA" "$PGHOST"
git log --oneline
git status --short
```

До сих пор всё работало в каталоге, в котором мы сами постепенно строили проект.

Теперь проверим главное обещание.

Представим, что этот репозиторий только что получил другой разработчик.

Выйти из текущего devenv shell, но **не останавливать PostgreSQL первого checkout**:

```sh
exit
cd ..
git clone prediction-pies prediction-pies-fresh
cd prediction-pies-fresh
```

Это новый checkout.

`.devenv` и состояние PostgreSQL в Git не хранятся. У нас только содержимое репозитория.

```sh
devenv shell
```

Десятый принцип Twelve-Factor — **Dev/prod parity**: development, staging и production
стоит держать настолько похожими, насколько это разумно.

Для нас хороший практический пример — PostgreSQL.

Если приложение рассчитано на PostgreSQL, локально мы тоже можем использовать
PostgreSQL, а не заменять его чем-то «примерно похожим».

devenv делает локальный экземпляр дешёвым и воспроизводимым.

```sh
printf 'PGDATA=%s\nPGHOST=%s\n' "$PGDATA" "$PGHOST"
devenv up -d
```

Обратите внимание на пути.

Это уже другой `PGDATA` и другой каталог Unix socket.

То есть PostgreSQL первого checkout и PostgreSQL второго checkout — два независимых
экземпляра одного сервиса.

```sh
sqlx migrate run
```

Новая база сначала пустая с точки зрения схемы приложения, поэтому применяем миграцию из
репозитория.

И запускаем приложение.

```sh
cargo run
```

Восьмой принцип — **Concurrency**: сервис масштабируется количеством экземпляров
процессов, а не хранением состояния в одном конкретном процессе.

Девятый — **Disposability**: процессы должны быстро запускаться и корректно
останавливаться.

Одиннадцатый — **Logs**: приложение пишет события наружу как поток, а окружение решает,
что с ними делать.

Logging сегодня специально не настраиваем — это тоже оставим на следующую лекцию.

И двенадцатый, который уже видели, — **Admin processes**: разовые операции вроде
миграций выполняются в том же окружении, что и приложение.

Из другого терминала:

```sh
xh :3000/pie
```

И вот приложение работает уже из свежего checkout.

Мы получили Rust, инструменты, отдельный PostgreSQL, применили ту же миграцию и
запустили тот же сервис.

Именно ради этого мы описывали development environment рядом с кодом.

Остановить `cargo run`.

______________________________________________________________________

## 12. Финал

В завершение обратите внимание: сегодня встретилось много вещей, которые мы уже
обсуждали раньше.

SemVer помогает договориться о версиях зависимостей.

Conventional Commits — о понятной истории изменений.

Переменные окружения отделяют конфигурацию от кода.

А Twelve-Factor App связывает многие из этих решений в общие принципы проектирования
сервисных приложений.

Особенно хорошо сегодня виден третий пункт — **Config: store config in the
environment**.

Наш код не знает конкретный путь к PostgreSQL socket и не обязан жёстко знать адрес
конкретного deploy. Он получает `DATABASE_URL` и `APP_ADDR` из окружения.

И последнее, что важнее конкретного devenv.

Инструменты со временем будут меняться.

Через несколько лет мы можем пользоваться другим environment manager, другим
HTTP-клиентом, другими AI-инструментами и даже другим языком.

Но идеи — явно описывать зависимости, отделять конфигурацию от кода, хранить понятную
историю изменений и стремиться к воспроизводимому окружению — останутся.

Поэтому хотелось бы, чтобы после курса с вами остался не только конкретный набор команд,
а культура разработки, которую эти инструменты помогают реализовать.

На следующем занятии продолжим этот же проект: займёмся тестами, compile-time queries
SQLx, миграциями, logging и самим developer workflow.

______________________________________________________________________

## Коммиты

Пример истории коммитов:

```text
build: add xh HTTP client
feat: add random pie endpoint
feat: add pie database
build: add PostgreSQL development service
chore: initialize Rust application
chore: initialize development environment
```
