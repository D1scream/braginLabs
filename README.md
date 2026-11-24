# Пирожки с предсказаниями

Учебный API на Rust, Axum, SQLx и PostgreSQL. [Гид по лабораторным](lab-guide.md) ·
[Требования](lab-implementation.md)

## Запуск в Windows

Понадобятся PowerShell 7.4 или новее, Rust с Cargo, SQLx CLI и локальная учебная БД
PostgreSQL `prediction_pies`. Подставь имя роли, которой принадлежит эта база.

```powershell
cargo install sqlx-cli --version 0.8.6 --locked --no-default-features --features postgres
$env:PGUSER = '<локальная роль>'
$env:PGPASSWORD = Read-Host 'Пароль PostgreSQL' -MaskInput
$env:DATABASE_URL = "postgresql://127.0.0.1:5432/prediction_pies"
.\scripts\run-windows.ps1
```

Проверь API из второго окна командой `Invoke-RestMethod http://127.0.0.1:3000/pie`. Для
тестов достаточно `cargo test --locked`. После выхода из API удали временный пароль из
окружения командой `Remove-Item Env:PGPASSWORD`.

Для режима №6 используй `.\scripts\run-windows.ps1 -Lab6`. Он применяет только начальную
миграцию и включает проверку запроса при выполнении. В Windows подключение к БД идёт по
TCP. Для двух экземпляров приложения задай разные `PORT` и `DATABASE_URL` в двух окнах
PowerShell.

Для `fmt`, `chk` и Git-хуков открой Git Bash из Git for Windows. С `mdformat`, `shfmt`,
`shellcheck`, `prek` и `convco` в `PATH` команды такие:

```bash
bash scripts/quality.sh fmt
bash scripts/quality.sh chk
prek install
```

### SecretSpec в Windows

Для проверки профиля через переменные Windows задай `PGPASSWORD` в текущем PowerShell и
выполни:

```powershell
$env:SECRETSPEC_REASON = 'Запуск учебного API'
secretspec check --profile development --provider env --no-prompt
secretspec run --profile development --provider env -- pwsh -NoProfile -File scripts/run-windows.ps1
```

Для окружения staging подставь `staging`, адрес его учебной базы и её учётные данные.
Подстановка `--provider env` действует только для этой команды.

### Бэкап в PowerShell

Понадобятся `pg_dump.exe`, `psql.exe`, `zstd.exe` и `gpg.exe` в `PATH`, а также ключ
GPG. Команды ниже выполняются с той же локальной ролью и паролем.

```powershell
$env:PGHOST = '127.0.0.1'
$env:PGPORT = '5432'
$env:PGDATABASE = 'prediction_pies'
$env:GPG_RECIPIENT = '<отпечаток ключа GPG>'
.\scripts\db-backup.ps1 .\backups\pies.sql.zst.gpg

createdb prediction_pies_restore
.\scripts\db-backup.ps1 .\backups\pies.sql.zst.gpg -RestoreDatabase prediction_pies_restore
psql -d prediction_pies_restore -c 'SELECT count(*) FROM pies;'
```

## Запуск через devenv

Для работы в WSL установи Nix и devenv 2.4 или новее. Держи клон в файловой системе
Ubuntu, например в `~/projects`, чтобы PostgreSQL мог выставить права на каталог данных.

```bash
devenv up
```

PostgreSQL стартует первым, SQLx применяет миграции, затем запускается API. Из второго
терминала в том же клоне:

```bash
devenv shell
curl --resolve "${API_URL#http://}:80:127.0.0.1" "$API_URL/pie"
psql "$DATABASE_URL" -Atc 'SELECT current_database(), inet_server_port();'
```

Portless на Linux может запросить `sudo` для порта 80. Чтобы проверить API без прокси,
запусти `devenv --profile direct up` и используй порт API из интерфейса devenv. Для
проверки двух клонов запусти их одновременно и сравни порты и значение `API_URL` в
каждом.

## Лаба №6

Профиль `lab6` оставляет PostgreSQL на Unix-сокете и позволяет запускать приложение и
миграции вручную.

```bash
devenv --profile lab6 up -d
devenv --profile lab6 shell
export PGUSER="$(id -un)"
sqlx migrate run --target-version 1
cargo run --locked --features lab6
```

Из второго терминала выполни `xh :3000/pie`. Чтобы переключиться на основной режим,
останови API и выполни `devenv --profile lab6 down` перед `devenv up`.

## Лаба №7

Миграции в `migrations/` именуются `xxx_name.sql`, где `xxx` — номер из трёх цифр. Если
к учебной базе уже применялись миграции с прежними номерами, для этого набора создай
свежую учебную базу. Для учебного отката колонки `category` используй
`bash scripts/revert-category.sh`.

При настроенном хуке direnv выполни `direnv allow`. В окружении проекта доступны `fmt`,
`chk` и `prek install`. Остановить запущенные в фоне процессы можно через `devenv down`
с теми же флагами профилей, что и при запуске.

Чтобы проверить SQL при компиляции по живой схеме, запусти PostgreSQL с применёнными
миграциями и выполни `SQLX_OFFLINE=false cargo check`.

## Лаба №8

Войди через `devenv shell`, инициализируй учебное хранилище `pass` с ключом GPG и
заполни профили. При уже настроенном хранилище используй его без повторного `pass init`.

```bash
secretspec set PGPASSWORD --profile development
secretspec set PGPASSWORD --profile staging
secretspec check --profile development
devenv --profile secrets up
```

Останови обычный `devenv up` перед запуском профиля `secrets` в том же клоне. Обычный
режим доверяет подключениям к учебной БД с loopback. Режим `secrets` требует SCRAM для
TCP-подключений и создаёт роль выбранного профиля через локальный сокет. Для staging
выставь `PIES_SECRETS_PROFILE=staging` в терминале, из которого запускаешь devenv и
команды для staging.

Чтобы создать архив защищённой БД, в другом терминале в том же клоне выполни:

```bash
devenv --profile secrets shell
export GPG_RECIPIENT='<отпечаток учебного ключа GPG>'
bash scripts/with-db-password.sh bash scripts/db-backup.sh backups/pies.sql.zst.gpg
```

Команды для восстановления в отдельную тестовую БД приведены в
[гиде](lab-guide.md#8-%D0%B1%D1%8D%D0%BA%D0%B0%D0%BF%D1%8B-%D0%B8-%D1%81%D0%B5%D0%BA%D1%80%D0%B5%D1%82%D1%8B).
Для расширения `pass fzf` установи файл в каталог расширений хранилища:

```bash
extensions="${PASSWORD_STORE_EXTENSIONS_DIR:-${PASSWORD_STORE_DIR:-$HOME/.password-store}/.extensions}"
mkdir -p "$extensions"
install -m 700 scripts/pass-extensions/fzf.bash "$extensions/fzf.bash"
export PASSWORD_STORE_ENABLE_EXTENSIONS=true
pass fzf
```

## Лаба №9

В CI используются SQLx Offline и профиль SecretSpec без обязательных секретов. После
изменения SQL-запроса или схемы обнови `.sqlx/` на запущенной учебной БД с миграциями
командой `cargo sqlx prepare -- --all-targets`. Для SCRAM-режима запусти её через
`bash scripts/with-db-password.sh cargo sqlx prepare -- --all-targets`.

```bash
devenv shell -- chk
devenv shell -- cargo test --locked
```

Отправь проект с `devenv.lock` на GitHub и проверь задания Ubuntu и Windows в Actions. В
демонстрационной ветке покажи цикл «успех → падающий тест → успех». После успешного
прогона основной ветки создай и опубликуй аннотированный тег `v0.1.0`.
