# Что реализовать в лабораторных работах №6–9

Проект «Пирожки с предсказаниями» на Rust, Axum, SQLx и PostgreSQL. Каждая работа
продолжает предыдущую.

## Лаба №6. Базовый API

- Создать Rust-проект. В `devenv.nix` подключить Rust, PostgreSQL, `sqlx-cli` и `xh`.
  Настроить создание БД `prediction_pies` и передавать `DATABASE_URL` с адресом
  Unix-сокета конкретного клона.
- Добавить SQLx-миграцию `001_initial.sql`. Создать таблицу `pies` с полями
  `id UUID PRIMARY KEY` (генерируется PostgreSQL), `prediction TEXT NOT NULL` и
  `created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP`. В той же миграции
  вставить 8–10 коротких предсказаний на русском.
- Реализовать `GET /pie` на Axum. Создать `PgPool` из `DATABASE_URL`, передать его через
  состояние Axum и выбирать случайную строку через `sqlx::query_as` и `FromRow`. Вернуть
  JSON с полями `id`, `prediction` и `created_at`. Адрес слушателя брать из `APP_ADDR`,
  в devenv задать `127.0.0.1:3000`.
- Проверить новый клон. Поднять отдельный PostgreSQL, применить миграцию вручную,
  запустить API и вызвать `GET /pie` через `xh`.

Источник — `C:\study\braginLabs\Labs\script.md`.

## Лаба №7. Миграции, запуск и качество кода

- Добавить `.envrc` для активации devenv через direnv.
- Добавить `002_add_prediction_category.sql` с колонкой
  `category TEXT NOT NULL DEFAULT 'general'`. Для учебного отката использовать
  `bash scripts/revert-category.sh`. Настроить последовательность в `devenv up`:
  готовность PostgreSQL → `app:migrate` (`sqlx migrate run`) → запуск API.
- Перевести запрос предсказания на макрос SQLx с проверкой при компиляции. В
  демонстрации показать, как `cargo check` находит ошибочное имя столбца.
- Перевести локальный PostgreSQL на TCP с привязкой к `127.0.0.1`. Выделять порты
  PostgreSQL и API отдельно для каждого клона. Подставлять фактический `PGPORT` в
  `DATABASE_URL` и передавать выбранный HTTP-порт приложению через `PORT`.
- Настроить Portless. Формировать `API_URL` вида
  `http://api.fortune-pies-<хеш-пути>.localhost`, используя первые 12 символов SHA-256
  от пути клона. Проверить одновременную работу двух клонов на разных портах и под
  разными именами.
- Добавить `scripts/quality.sh` и команды devenv `fmt` и `chk`. Форматировать Markdown
  через `mdformat`, shell через `shfmt`, Rust через `cargo fmt`. В `chk` проверять
  форматирование рабочего дерева и запускать ShellCheck и Clippy без изменения файлов.
- Добавить `.pre-commit-config.yaml` для `prek` и `scripts/check-commit-msg.sh`. Хук
  `pre-commit` запускает `chk`, а `commit-msg` проверяет текст сообщения через `convco`.

Источник — `C:\study\braginLabs\Labs\07-scenario.md`.

## Лаба №8. Бэкапы, секреты и расширение pass

- Написать `scripts/db-backup.sh` для конвейера `pg_dump | zstd | gpg`. Принимать путь к
  архиву аргументом, получателя шифрования через `GPG_RECIPIENT`, а настройки PostgreSQL
  через переменные `PG*`. Включить `set -euo pipefail` и `umask 077`. Сохранять архив
  под итоговым именем после успешного завершения конвейера. Добавить `backups/` в
  `.gitignore`.
- Проверить восстановление через GPG, `zstd` и `psql` в отдельную тестовую БД. Для
  `psql` включить остановку при ошибке.
- Настроить `pass` с GPG. В `secretspec.toml` объявить `PGPASSWORD` для профилей
  `development` и `staging` с провайдером `pass://`. Настроить отдельные пароли и роли
  PostgreSQL для профилей и проверить их через `secretspec check`.
- Включить интеграцию SecretSpec в `devenv.yaml` с профилем `development`. Убрать пароль
  из `DATABASE_URL`, проверить использование `PGPASSWORD` в SQLx и передавать секрет API
  через `secretspec run` при ручном запуске и через `devenv up`.
- Сделать локальное расширение `~/.password-store/.extensions/fzf.bash`. Передавать в
  `fzf` имена записей и копировать выбранный пароль через `pass show --clip`. Проверить
  на тестовой записи.

Источник — `C:\study\braginLabs\Labs\lab08_plan.md`.

## Лаба №9. GitHub Actions и учебный релиз

- На локальной БД с применёнными миграциями выполнить
  `cargo sqlx prepare -- --all-targets` и закоммитить `.sqlx/`. В CI выставить
  `SQLX_OFFLINE=true` и обеспечить запуск devenv без доступа к локальному `pass`,
  закрытому GPG-ключу и секретам проекта.
- Добавить один unit-тест для чистой функции. Пример в сценарии проверяет, что строка из
  пробелов отклоняется, а непустое предсказание принимается.
- Добавить `.github/workflows/ci.yml` с запуском на `push`, `pull_request` и вручную. На
  Ubuntu runner установить Nix и devenv, подключить кеш Cachix и запустить
  `devenv shell -- chk` и `devenv shell -- cargo test --locked`. Закоммитить
  `Cargo.lock` и `devenv.lock`.
- Показать успешный CI, падение теста в демонстрационной ветке и успешный прогон после
  исправления. Когда нужный коммит в `main` пройдёт CI, создать и опубликовать
  аннотированный тег `v0.1.0`.

Источник — `C:\study\braginLabs\Labs\lab09_detailed_slide_notes.md`.

## Расхождения между сценариями

- В №6 таблица называется `pies`, база — `prediction_pies`. В примерах №7 фигурируют
  таблица `predictions` и база `pies`. Для сквозного проекта предлагается сохранить
  имена из №6 и адаптировать SQL и настройки подключения из №7. База в существующем
  `PGDATA` сохраняет прежние роли и имена при изменении `initialDatabases`.
- В №7 SQL-запрос читает `category`, а сценарий №6 задаёт три поля JSON-ответа.
  Включение `category` в ответ API требует отдельного решения.
