# ЛК3: загрузка Linux и systemd — практикум

Пошаговый семинар на **90 минут** для начинающих с базой Linux и сетей. Поднимем Ubuntu в VirtualBox, создадим HTTP-службу, воспроизведём отказ и разберём перезапуск, ограничения ресурсов и socket activation. Материал соответствует практической части ЛК3, слайдам **34–57**.

Этот README подходит для демонстрации преподавателя и самостоятельного повторения. В каждом опыте есть вопрос, команды, ожидаемые признаки и объяснение результата. **Установку VM и подготовку пакетов выполните до занятия**: они не входят в 90 минут.

## Навигация

- [Установка VirtualBox и Ubuntu на macOS / Windows](#vm)
- [SSH и браузер на основном компьютере](#ssh)
- [Подготовка файлов и исходного снимка](#prepare)
- [План семинара](#seminar)
- [1. Следы загрузки Linux](#boot)
- [2. Своя служба, автозапуск и журнал](#service)
- [3. Инцидент: порт занят другим процессом](#conflict)
- [4. Автоматический перезапуск](#restart)
- [5. Ограничение памяти](#memory)
- [6. Права и изоляция приложения](#hardening)
- [7. Socket activation](#socket)
- [8. Проверка копии fstab](#fstab)
- [Завершение и повтор семинара](#finish)
- [Дополнительно: таймер](#timer)
- [Дополнительно: шесть мини-лабораторных с готовыми командами](#extra)
  - [Д1. Ограничить время работы задачи](#extra-timeout)
  - [Д2. Найти файл в приватном /tmp](#extra-private-tmp)
  - [Д3. Изменить лимит CPU работающей службы](#extra-cpu)
  - [Д4. Запустить два сайта из одного шаблона](#extra-template)
  - [Д5. Сделать и восстановить резервную копию](#extra-backup)
  - [Д6. Запустить обработчик при появлении файла](#extra-path)
- [Типичные проблемы](#troubleshooting)
- [Что проверено и документация](#verification)

## Как читать команды

- **На хосте** — в Terminal на macOS или PowerShell на Windows.
- **В Ubuntu** — в консоли VM или SSH-сессии этой VM. Все команды опытов выполняются здесь, из `~/sre-systemd-lab`.
- Команды запускаем небольшими блоками. Сначала прогнозируем результат, затем выполняем и объясняем наблюдение.
- `sudo` запросит пароль пользователя Ubuntu. При вводе пароль не отображается.
- Выход из просмотра `status`/журнала: `q`; из непрерывного просмотра `journalctl -f`: `Ctrl+C`.
- `is-active` для остановленной службы, `is-enabled` для disabled и команды намеренно неудачных опытов возвращают ненулевой код. В соответствующих шагах это ожидается. Не запускайте весь README одним скриптом с `set -e`.

<a id="vm"></a>
## 1. Установить VirtualBox и Ubuntu

### 1.1. Выбрать архитектуру

Учебная система — **Ubuntu Server 26.04.1 LTS**, без графического рабочего стола. После обновлений версии ядра и пакетов могут отличаться. Команды семинара одинаковы на ARM64 и AMD64.

| Основной компьютер | Пакет VirtualBox | ISO Ubuntu |
|---|---|---|
| Mac с Apple Silicon: M1/M2/M3/M4 и другие M-серии | macOS / Apple Silicon hosts | `ubuntu-26.04.1-live-server-arm64.iso` |
| Mac с Intel | macOS / Intel hosts | `ubuntu-26.04.1-live-server-amd64.iso` |
| Windows 11 на Intel/AMD | Windows hosts | `ubuntu-26.04.1-live-server-amd64.iso` |

На Mac архитектуру показывает **команда на хосте**:

```bash
uname -m
```

`arm64` — Apple Silicon; `x86_64` — Intel. На Windows посмотрите **Параметры → Система → О системе → Тип системы**. AMD64 подходит и процессорам Intel, и AMD. Windows на ARM требует ARM64-гостя; в документации VirtualBox 7.2 поддержка Windows/ARM-хоста обозначена экспериментальной, этот вариант здесь отдельно не отрабатывается.

**VirtualBox на Apple Silicon не запускает x86/AMD64-гостя.** Для этого Mac выбирайте обычный ARM64 Server ISO, без суффикса `+largemem`, и не образ Raspberry Pi.

### 1.2. Скачать установщики

1. [VirtualBox: официальные загрузки](https://www.virtualbox.org/wiki/Downloads). Установите актуальный стабильный выпуск ветки 7.2 или более новой поддерживаемой ветки для своего хоста.
2. Ubuntu Server:
   - [AMD64 ISO](https://releases.ubuntu.com/26.04/ubuntu-26.04.1-live-server-amd64.iso), [список файлов и SHA256SUMS](https://releases.ubuntu.com/26.04/).
   - [ARM64 ISO](https://cdimage.ubuntu.com/releases/26.04/release/ubuntu-26.04.1-live-server-arm64.iso), [список файлов и SHA256SUMS](https://cdimage.ubuntu.com/releases/26.04/release/).

На macOS откройте DMG и установите пакет VirtualBox. На Windows запустите EXE и завершите установку, включая компоненты виртуальной сети. Если установщик потребует перезагрузку хоста, выполните её до создания VM.

Для семинара достаточно базового VirtualBox. Extension Pack и Guest Additions не нужны: будем работать через консоль и SSH.

Можно проверить SHA256 скачанного ISO и сравнить с `SHA256SUMS` в **соответствующем каталоге загрузки**.

**macOS, в каталоге со скачанным ARM64 ISO:**

```bash
shasum -a 256 ubuntu-26.04.1-live-server-arm64.iso
```

**Windows PowerShell, в каталоге с AMD64 ISO:**

```powershell
Get-FileHash .\ubuntu-26.04.1-live-server-amd64.iso -Algorithm SHA256
```

### 1.3. Создать VM

Названия пунктов интерфейса могут немного различаться между версиями VirtualBox.

1. Нажмите **New / Создать**. Имя VM: `lk3-ubuntu`.
2. Выберите скачанный ISO. Тип ОС — Linux, Ubuntu подходящей архитектуры. Если нет отдельного пункта 26.04, используйте общий профиль Ubuntu для этой архитектуры.
3. Выберите **Skip Unattended Installation / Пропустить автоматическую установку**. Далее установим Ubuntu вручную; это также избегает ограничений unattended-установки на ARM.
4. Выделите **4096 MB RAM**, **2 виртуальных CPU**. На хосте желательно иметь хотя бы 8 GB RAM и свободные ресурсы на время занятия.
5. Создайте новый динамический виртуальный диск **VDI, 30 GB**. На диске хоста оставьте запас места для VM и снимка.
6. Используйте **UEFI**. На x86 включите EFI в настройках системы VM, если оно выключено. На ARM прошивка UEFI используется в соответствующем профиле.
7. Сеть: **Adapter 1 → NAT**, адаптер включён, **Cable Connected / Кабель подключён**. Остальное виртуальное оборудование оставьте по умолчанию для выбранной архитектуры.
8. В настройках NAT откройте **Advanced → Port Forwarding / Проброс портов** и добавьте правило:

| Name | Protocol | Host IP | Host Port | Guest IP | Guest Port |
|---|---|---|---|---|---|
| ssh | TCP | `127.0.0.1` | `2222` | оставить пустым | `22` |

NAT позволяет Ubuntu скачивать пакеты. Правило направляет подключения к порту 2222 вашего компьютера на SSH-порт VM. Bridged-сеть и настройка роутера не требуются.

### 1.4. Установить Ubuntu Server

Запустите VM и пройдите установщик:

1. Выберите язык и раскладку.
2. Выберите обычный **Ubuntu Server**. Графическая среда для работы не требуется.
3. Сеть оставьте с DHCP: через NAT должен появиться адрес.
4. Proxy оставьте пустым, зеркало пакетов — по умолчанию, если в вашей сети нет особых требований.
5. Для хранения выберите новый виртуальный диск **30 GB** и автоматическую разметку. Убедитесь, что это диск учебной VM. Шифрование для этого семинара не требуется, предложенный LVM можно оставить.
6. Имя машины: `lk3-ubuntu`. Имя пользователя: **`student`**. Задайте собственный пароль. Если выбрали другое имя, замените `student` в SSH-командах ниже.
7. Включите **Install OpenSSH server**. Для первого входа по паролю оставьте password authentication разрешённой в учебной VM.
8. Дополнительные featured snaps не выбирайте.
9. После установки перезагрузите VM. Извлеките ISO из виртуального привода, если установщик просит удалить носитель или снова запускается установка.
10. Войдите в консоль Ubuntu под `student`.

**В Ubuntu:**

```bash
cat /etc/os-release
uname -m
ps -p 1 -o pid,comm,args
ip -br address
```

Ожидаются Ubuntu 26.04, `aarch64` на Apple Silicon либо `x86_64` на Intel/AMD и **systemd с PID 1**.

<a id="ssh"></a>
## 2. Подключиться с хоста

### 2.1. SSH

**На хосте: Terminal macOS или PowerShell Windows:**

```text
ssh -p 2222 student@127.0.0.1
```

При первом подключении проверьте, что подключаетесь к своей VM, и подтвердите сохранение ключа. Введите пароль Ubuntu. После входа приглашение будет примерно `student@lk3-ubuntu:~$` — теперь команды выполняются **в гостевой Ubuntu**.

Если в Windows команда `ssh` не найдена, установите компонент **OpenSSH Client** через Optional Features / Дополнительные компоненты Windows. OpenSSH Server на Windows устанавливать не нужно.

Если SSH в Ubuntu не установили при инсталляции, выполните **в консоли VM**:

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh.service
```

Оставьте консоль VirtualBox доступной: она пригодится, если SSH пропадёт после перезагрузки. Для занятия удобно открыть две SSH-сессии: команды в первой, наблюдение журнала во второй.

### 2.2. При желании открыть страницу в браузере хоста

Наш HTTP-сервер слушает `127.0.0.1:8080` **внутри Ubuntu**. Этот адрес не является localhost macOS или Windows. Основные проверки выполняем через `curl` в Ubuntu.

Когда понадобится браузер, откройте **ещё один терминал на хосте**:

```text
ssh -N -o ExitOnForwardFailure=yes -p 2222 -L 18080:127.0.0.1:8080 student@127.0.0.1
```

Оставьте его открытым. После запуска службы в опыте 2 откройте на хосте **http://127.0.0.1:18080/**. Завершение туннеля — `Ctrl+C`. Если 18080 занят, выберите другой свободный порт, например 18081, и поменяйте адрес в браузере.

Туннель нужен потому, что приложение слушает loopback гостя. Простой NAT-проброс на сетевой адрес VM не делает такой слушатель доступным снаружи.

<a id="prepare"></a>
## 3. Подготовить стенд до семинара

Все команды этого раздела выполняются **в Ubuntu**.

### 3.1. Скачать примеры и установить пакеты

```bash
sudo apt update
sudo apt install -y git python3 curl netcat-openbsd
cd ~
git clone https://github.com/vmeshche/sre-systemd-lab.git
cd ~/sre-systemd-lab
sudo bash scripts/prepare.sh
bash scripts/check-environment.sh
```

Аккаунт GitHub для скачивания публичного репозитория не требуется. При повторной подготовке уже существующего checkout используйте `git pull --ff-only`, а не второй `git clone` в ту же папку.

Если готовый каталог уже находится на хосте, его можно перенести без GitHub. **На хосте, из каталога, содержащего папку `sre-systemd-lab`:**

```text
scp -P 2222 -r ./sre-systemd-lab student@127.0.0.1:~/
```

Затем в Ubuntu перейдите в `~/sre-systemd-lab` и выполните обе команды подготовки скриптов выше. Пакеты должны быть установлены в любом варианте. Повторное копирование в уже изменённый каталог не заменяет восстановление снимка VM.

Что делает `prepare.sh`:

- создаёт системного пользователя `course-web` без интерактивного входа;
- устанавливает учебную страницу в `/srv/lk3/index.html`;
- устанавливает скрипт опыта с памятью в `/opt/lk3/lk3-memory.py`;
- устанавливает, но **не запускает**, `lk3-port-holder.service`;
- проверяет синтаксис готовых unit-файлов.

Основной `course-web.service` и его дополнения будем устанавливать во время занятия. Если он уже установлен, скрипт подготовки попросит восстановить исходное состояние. Это защищает сценарий от оставшегося с прошлой репетиции `Restart=`.

`check-environment.sh` ничего не меняет. Перед первым опытом ожидаем:

```text
OK: PID 1 is systemd
OK: cgroups v2
OK: course-web account exists
OK: Ports 8080 and 8081 are free
Ready for exercise 1. Keep this state as a powered-off VM snapshot.
```

В выводе также будут фактические версии системы. Для полной Server VM ожидаются `systemd`, файловая система `cgroup2fs`, Python, curl и `nc`. Проверка UEFI использует `/sys/firmware/efi`.

### 3.2. Сохранить исходное состояние

1. Убедитесь, что подготовка завершена, порты 8080/8081 свободны и основной unit ещё не установлен.
2. В Ubuntu выполните:

```bash
sudo poweroff
```

3. После выключения VM создайте в VirtualBox снимок **`lk3-ready`**: выберите VM → **Snapshots / Снимки → Take / Сделать**.
4. Запустите VM и снова подключитесь по SSH.

Снимок выключенной VM удобно использовать перед каждой новой группой. Не путайте снимок с Save State: сохранённое состояние работающей машины оставляет в памяти текущие процессы и не заменяет чистую подготовку.

### 3.3. Что лежит в репозитории

| Путь | Назначение |
|---|---|
| `examples/01-service/` | Основная HTTP-служба и страница |
| `examples/02-port-conflict/` | Второй процесс, намеренно занимающий тот же порт |
| `examples/03-restart/` | Drop-in с политикой перезапуска |
| `examples/04-resources/` | Выделение 100 MiB для опыта с лимитом |
| `examples/05-hardening/` | Drop-in с ограничением прав |
| `examples/06-socket/` | Сокет и шаблон echo-обработчика |
| `examples/07-fstab/` | Строка с отсутствующим UUID для проверки копии fstab |
| `examples/08-timer/` | Необязательный пример календарного таймера |
| `scripts/` | Подготовка файлов и проверка исходного окружения |
| `extra/` | Готовые файлы дополнительных мини-лабораторных Д1–Д6; Д1 использует только команды |

<a id="seminar"></a>
## 4. План занятия на 90 минут

Отсчёт начинается с уже подготовленной VM.

| Минуты | Слайды ЛК3 | Действие |
|---|---|---|
| 0–6 | 34–36 | Проверяем стенд, договариваемся, где выполняются команды |
| 6–16 | 37–38 | Ищем следы загрузки, сравниваем time/blame/critical-chain |
| 16–30 | 39–41 | Устанавливаем службу, проверяем HTTP, enable и journal |
| 30–43 | 42–44 | Занимаем порт, находим настоящего слушателя, восстанавливаем службу |
| 43–55 | 45–46 | Включаем Restart, сравниваем SIGKILL и stop |
| 55–66 | 47–49 | Ограничиваем память и подтверждаем причину OOM |
| 66–71 | 50 | Применяем hardening и проверяем HTTP |
| 71–80 | 51–53 | Активируем echo по соединению |
| 80–86 | 54–55 | Проверяем повреждённую копию fstab |
| 86–90 | 56–57 | Обсуждаем выводы и останавливаем опыты |

Второй терминал нужен для наблюдения, но все основные опыты можно выполнить по очереди в одном. **После каждого нового SSH-входа:**

```bash
cd ~/sre-systemd-lab
```

<a id="boot"></a>
## Опыт 1. Найти следы загрузки Linux

**Вопрос:** если доступна обычная консоль Ubuntu, какие этапы загрузки уже состоялись?

### Выполнить

```bash
test -d /sys/firmware/efi && echo 'UEFI boot' || echo 'EFI directory not found'
cat /proc/cmdline
findmnt /
ps -p 1 -o pid,comm,args
sudo journalctl -b -k --no-pager -n 25
```

### Что увидеть

- `UEFI boot` подтверждает наличие EFI-интерфейса в работающем ядре.
- `/proc/cmdline` показывает параметры, переданные ядру. Их набор зависит от установки.
- `findmnt /` показывает текущую корневую файловую систему. Название диска/LVM-тома у каждого может отличаться.
- PID 1 — `systemd`.
- `journalctl -b -k` показывает сообщения ядра текущей загрузки. Это не полный журнал прошивки или GRUB.

Теперь измерения:

```bash
systemd-analyze time
systemd-analyze critical-chain multi-user.target
systemd-analyze blame --no-pager
```

**Вопрос:** можно ли сложить все длительности из blame и получить время загрузки?

<details>
<summary>Ответ и объяснение преподавателю</summary>

Нет: службы запускаются параллельно, а их интервалы пересекаются. `time` показывает доступные измерения этапов, `blame` — длительности активации отдельных юнитов, `critical-chain` — одну из значимых цепочек порядка. Они не измеряют автоматически момент готовности приложения для пользователя. Firmware/loader-время доступно не на каждой платформе.

</details>

**Если вывод другой:** отсутствие EFI-каталога требует проверки режима прошивки VM; отсутствие firmware-времени в `systemd-analyze` само по себе не является отказом. Названия дисков, времена и версии не должны совпадать с преподавательскими побайтно.

<a id="service"></a>
## Опыт 2. Создать HTTP-службу

### 2.1. Прочитать unit и установить его

```bash
cat examples/01-service/course-web.service
sudo systemd-analyze verify examples/01-service/course-web.service
sudo install -m 0644 examples/01-service/course-web.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start course-web
systemctl status course-web --no-pager
```

Разберите `User`, `WorkingDirectory`, `ExecStart`, `Type=exec` и `WantedBy=multi-user.target`. Пользователь и каталог созданы при подготовке. Unit запускает обычный foreground-процесс Python.

`verify` при успехе обычно ничего не печатает. Это проверка конфигурации, а не HTTP. `daemon-reload` перечитывает unit-файлы и сам не запускает приложения.

### 2.2. Проверить полезный результат

```bash
curl --fail --retry 5 --retry-delay 1 --retry-connrefused --max-time 3 http://127.0.0.1:8080/
systemctl show course-web -p MainPID
sudo ss -ltnp 'sport = :8080'
```

Ожидается HTML с заголовком **«Учебный сервер работает»**, ненулевой MainPID и слушатель `127.0.0.1:8080`. PID из `ss` должен соответствовать Python-процессу нашей службы. Curl делает короткие повторные попытки: `Type=exec` может завершить запуск раньше, чем Python откроет порт.

### 2.3. Разделить start и enable

Сначала спрогнозируйте результат:

```bash
systemctl is-active course-web
systemctl is-enabled course-web
```

После первого ручного `start` ожидаются **active** и **disabled**. Затем:

```bash
sudo systemctl enable course-web
systemctl is-enabled course-web
ls -l /etc/systemd/system/multi-user.target.wants/course-web.service
```

Теперь ожидаем **enabled** и ссылку на unit. `enable` создаёт связь по `[Install]`; запущенный процесс уже существовал. `enable --now` мог бы совместить настройку связи и немедленный запуск.

**Проверка после реального reboot — по желанию, около двух дополнительных минут:**

```bash
sudo reboot
```

SSH закроется. Дождитесь загрузки, снова выполните на хосте `ssh -p 2222 student@127.0.0.1`, затем в Ubuntu:

```bash
cd ~/sre-systemd-lab
systemctl is-active course-web
curl --fail http://127.0.0.1:8080/
```

Ожидаются active и страница без ручного start.

### 2.4. Найти запрос в журнале

```bash
sudo journalctl -b -u course-web --no-pager -n 30
sudo journalctl --list-boots --no-pager
```

Ищите строку вида `"GET / HTTP/1.1" 200`. Python пишет запросы в stderr, который попадает в journal.

Во втором терминале можно запустить `sudo journalctl -f -u course-web`, выполнить новый curl в первом и увидеть новую запись. Выход из слежения — `Ctrl+C`.

Для предыдущей загрузки:

```bash
sudo journalctl -b -1 -u course-web --no-pager -n 30
```

Предыдущая загрузка может отсутствовать: это зависит от наличия прошлых загрузок, постоянного хранения журнала и его очистки. Для отдельного опыта с сохранением журнала можно до следующего reboot выполнить:

```bash
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo journalctl --flush
```

Это работает при стандартном `Storage=auto`; явно настроенный `Storage=volatile` требует отдельной правки конфигурации. Потерянные записи прошлых загрузок команда не восстановит.

**Проверка понимания:** active означает состояние unit. Ответ HTTP подтверждает конкретную функцию. Enabled описывает связи активации и не гарантирует, что программа не упадёт.

**Если служба не работает:** смотрите `sudo journalctl -b -u course-web --no-pager -n 40`. `217/USER` указывает на проблему с пользователем, `200/CHDIR` — с рабочим каталогом, `203/EXEC` — с запуском программы. HTTP 404 требует проверки файла и каталога.

**Перед следующим опытом:** course-web работает и enabled. Drop-in с Restart ещё не установлен.

<a id="conflict"></a>
## Опыт 3. Воспроизвести инцидент с занятым портом

**Вопрос:** может ли curl возвращать правильную страницу, когда нужная служба находится в failed?

### 3.1. Занять порт вторым процессом

```bash
sudo systemctl stop course-web
sudo systemctl start lk3-port-holder
sudo ss -ltnp 'sport = :8080'
```

Продолжайте **после появления слушателя** `127.0.0.1:8080`. Если его ещё нет, повторите `ss` через секунду. Держатель порта раздаёт ту же страницу, что и основной сервис.

Теперь запустите основной unit:

```bash
sudo systemctl start course-web
systemctl status course-web --no-pager
sudo journalctl -b -u course-web --no-pager -n 30
curl --fail http://127.0.0.1:8080/
```

### 3.2. Найти доказательства

Ожидаем:

- в журнале `Address already in use` / `Errno 98`;
- `course-web` переходит в failed после попытки открыть порт;
- curl продолжает возвращать страницу, потому что отвечает другой процесс.

`systemctl start` с Type=exec может успеть сообщить об успешном запуске Python, прежде чем Python обнаружит занятый порт. Если status ещё показывает active, повторите его через секунду. Ориентируйтесь на итоговое состояние и журнал.

Сравните:

```bash
sudo ss -ltnp 'sport = :8080'
systemctl show lk3-port-holder -p MainPID
systemctl show course-web -p MainPID
```

Слушающий PID должен совпасть с MainPID у `lk3-port-holder`. Статический текст страницы не доказывает, какой unit отвечает: оба процесса читают один файл.

### 3.3. Восстановить службу

```bash
sudo systemctl stop lk3-port-holder
sudo systemctl reset-failed course-web
sudo systemctl start course-web
curl --fail --retry 5 --retry-delay 1 --retry-connrefused --max-time 3 http://127.0.0.1:8080/
systemctl show course-web -p MainPID
sudo ss -ltnp 'sport = :8080'
```

Теперь порт должен принадлежать `course-web`, а HTTP — отвечать. `reset-failed` сбрасывает состояние отказа и счётчики, но порт освободила именно остановка держателя.

<details>
<summary>Что объяснить студентам</summary>

«Мы отдельно проверили состояние нужной службы, причину её отказа и владельца порта. Один успешный curl проверял HTTP-ответ, но не доказывал работу конкретного unit. После исправления снова проверили и владельца, и ответ».

</details>

**Если конфликт не появился:** держатель мог ещё не открыть порт либо уже завершился по `RuntimeMaxSec=20min`. Проверьте его журнал. Если course-web постоянно перезапускается, остался restart drop-in от предыдущего прохождения: верните снимок или выполните полный сброс в конце README.

**Повтор опыта:** после восстановления можно снова начать с 3.1, пока Restart ещё не добавлен.

<a id="restart"></a>
## Опыт 4. Настроить автоматический перезапуск

**Вопрос:** чем аварийное завершение процесса отличается от `systemctl stop`?

### 4.1. Установить drop-in

```bash
cat examples/03-restart/restart.conf
sudo install -d -m 0755 /etc/systemd/system/course-web.service.d
sudo install -m 0644 examples/03-restart/restart.conf /etc/systemd/system/course-web.service.d/
sudo systemctl daemon-reload
sudo systemctl restart course-web
systemctl cat course-web
systemctl show course-web -p Restart -p RestartUSec
```

Ожидаем `Restart=on-failure`, `RestartUSec=2s`. Файл дополняет основной unit. При ручной установке нужен `daemon-reload`; при `systemctl edit` перечитывание выполняется автоматически. Изменения параметров запуска уже работающего процесса всё равно могут требовать restart.

### 4.2. Вызвать аварийное завершение

Запишите текущие значения:

```bash
systemctl show course-web -p MainPID -p NRestarts
sudo systemctl kill --kill-whom=main --signal=SIGKILL course-web
```

Обсудите прогноз и подождите **не меньше трёх секунд**. Затем:

```bash
systemctl show course-web -p MainPID -p NRestarts
curl --fail --retry 5 --retry-delay 1 --retry-connrefused --max-time 3 http://127.0.0.1:8080/
sudo journalctl -b -u course-web --no-pager -n 25
```

Ожидаем новый PID, увеличение NRestarts относительно записанного значения и рабочий HTTP. PID — переменное число; не требуйте совпадения с преподавателем. Счётчик может быть больше единицы после нескольких попыток.

### 4.3. Сравнить с намеренной остановкой

```bash
sudo systemctl stop course-web
sleep 3
systemctl is-active course-web
```

Ожидаем **inactive**. Восстановите рабочее состояние:

```bash
sudo systemctl start course-web
curl --fail --retry 5 --retry-delay 1 --retry-connrefused --max-time 3 http://127.0.0.1:8080/
```

<details>
<summary>Почему попытки не ограничены одним повтором?</summary>

`Restart=on-failure` действует после каждого подходящего сбоя. `RestartSec` задаёт паузу, а `StartLimitIntervalSec` и `StartLimitBurst` ограничивают частоту запусков, а не их общее число за жизнь службы. Достаточно редкие падения могут вызывать рестарты неограниченно долго. Ручной stop не вызывает такой рестарт. При достижении start-limit systemd сам не возобновляет попытки только из-за истечения интервала: нужен новый запрос запуска. Прежде чем сбрасывать счётчик, устраните причину отказа.

Проверьте эффективные настройки конкретной VM:

```bash
systemctl show course-web -p StartLimitIntervalUSec -p StartLimitBurst
```

Одна политика Restart не обнаруживает зависший процесс, который продолжает существовать.

</details>

**Повтор:** SIGKILL можно отправить ещё раз после восстановления HTTP. Для продолжения оставьте службу работающей.

<a id="memory"></a>
## Опыт 5. Ограничить память группы процессов

**Вопрос:** что произойдёт, если процесс затронет 100 MiB памяти внутри cgroup с пределом 50 MiB?

### 5.1. Прочитать код и запустить отдельную службу

```bash
cat examples/04-resources/lk3-memory.py
systemctl show course-web -p ControlGroup
sudo systemd-run --unit=lk3-memory \
  -p MemoryMax=50M \
  -p MemorySwapMax=0 \
  -p RuntimeMaxSec=15s \
  /usr/bin/python3 /opt/lk3/lk3-memory.py
```

`systemd-run` создаёт временный unit для этого опыта. Он не меняет лимиты `course-web`. Скрипт выделяет и затрагивает 100 MiB. В предел входит также собственная память Python. Запрет swap делает результат понятнее, а время работы дополнительно ограничено 15 секундами.

### 5.2. Доказать причину завершения

Через пару секунд:

```bash
systemctl show lk3-memory -p Result -p MemoryMax -p MemorySwapMax
sudo journalctl -b -u lk3-memory --no-pager -n 30
```

Ожидаемые признаки:

```text
Result=oom-kill
MemoryMax=52428800
MemorySwapMax=0
```

В журнале ищите указание на **kernel OOM killer** и завершение процесса. Один `status=9/KILL` или одно слово failed ещё не доказывает OOM. При необходимости посмотрите сообщения ядра:

```bash
sudo journalctl -b -k --no-pager -n 80
```

В этом опыте работает OOM ядра при cgroup-лимите. Это не демонстрация systemd-oomd.

### 5.3. Посмотреть признаки давления на ресурсы

```bash
cat /proc/pressure/memory
cat /proc/pressure/cpu
```

PSI показывает время ожидания ресурсов. Короткий опыт не обязан дать заметное значение средних `avg10/60/300`. `MemoryHigh` вызывает освобождение памяти и торможение при превышении порога, допускает превышение и сам по себе не вызывает OOM. `MemoryMax` служит жёстким пределом.

**Дополнительный вопрос:** на машине с восемью логическими CPU `CPUQuota=50%` даст четыре CPU? Нет: это суммарный предел CPU-времени группы, эквивалентный половине одного логического CPU. CPUWeight задаёт относительный вес при конкуренции.

**Если результат другой:** `can't open file` — проверить путь к скрипту; `203/EXEC` — исполняемую программу; `Result=timeout` — сработали 15 секунд, это не OOM. Если показано success, сначала проверьте фактически применённые лимиты и cgroups v2.

**Повтор:** после того как просмотрели завершившийся опыт, выполните `sudo systemctl reset-failed lk3-memory` и повторите 5.1. Если старый unit ещё работает, сначала остановите его через `sudo systemctl stop lk3-memory`.

<a id="hardening"></a>
## Опыт 6. Ограничить права приложения

**Вопрос:** сможет ли наш HTTP-сервер читать страницу, если большую часть файловой системы сделать доступной ему только для чтения?

```bash
cat examples/05-hardening/hardening.conf
sudo install -m 0644 examples/05-hardening/hardening.conf /etc/systemd/system/course-web.service.d/
sudo systemctl daemon-reload
sudo systemctl restart course-web
systemctl show course-web -p NoNewPrivileges -p ProtectSystem -p PrivateTmp
curl --fail --retry 5 --retry-delay 1 --retry-connrefused --max-time 3 http://127.0.0.1:8080/
```

Ожидаем `NoNewPrivileges=yes`, `ProtectSystem=strict`, `PrivateTmp=yes` и успешный HTTP-ответ.

| Настройка | Что объяснить |
|---|---|
| `User=course-web` | Приложение работает под отдельным непривилегированным пользователем |
| `NoNewPrivileges=yes` | Exec не может добавить новые привилегии; уже имеющиеся права не отзываются |
| `ProtectSystem=strict` | Большая часть дерева файлов становится read-only для этой службы, со специальными исключениями |
| `PrivateTmp=yes` | У службы свои `/tmp` и `/var/tmp`; в этой комбинации они остаются записываемыми |

Сервер читает готовую страницу, поэтому нужная функция сохраняется. Приложению с постоянными записями можно выделить разрешённый каталог, например через `StateDirectory=`. Эти настройки не делают всю систему read-only и не заменяют анализ безопасности приложения.

Для обсуждения можно посмотреть:

```bash
systemd-analyze security course-web.service --no-pager
```

Оценка служит подсказкой и не является доказательством безопасности. Для короткой демонстрации достаточно проверки параметров и HTTP.

**Откат только этого опыта:**

```bash
sudo rm /etc/systemd/system/course-web.service.d/hardening.conf
sudo systemctl daemon-reload
sudo systemctl restart course-web
```

Откат нужен только если хотите сравнить состояния. Для остальных опытов hardening можно оставить.

<a id="socket"></a>
## Опыт 7. Запустить обработчик по входящему соединению

Это отдельный echo-сервис на **8081**. HTTP-служба остаётся на **8080**.

**Вопрос:** кто будет слушать порт до появления первого процесса-обработчика?

### 7.1. Прочитать и установить два файла

```bash
cat examples/06-socket/lk3-echo.socket
cat examples/06-socket/lk3-echo@.service
sudo systemd-analyze verify \
  examples/06-socket/lk3-echo.socket \
  examples/06-socket/lk3-echo@.service
sudo install -m 0644 \
  examples/06-socket/lk3-echo.socket \
  examples/06-socket/lk3-echo@.service \
  /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lk3-echo.socket
```

`ListenStream` задаёт адрес слушателя. `Accept=yes` создаёт отдельный экземпляр шаблона `lk3-echo@.service` на принятое соединение. Одинаковая основа имени связывает socket с шаблоном автоматически. `cat` читает соединение через stdin и отправляет ответ через stdout. DynamicUser выделяет обработчику временного пользователя.

### 7.2. Проверить состояние до клиента

```bash
systemctl status lk3-echo.socket --no-pager
sudo ss -ltnp 'sport = :8081'
systemctl list-units 'lk3-echo@*.service' --no-pager
```

Ожидаем **active (listening)** у socket, слушающий порт у systemd и отсутствие работающих экземпляров echo до первого клиента.

### 7.3. Отправить сообщение

```bash
printf 'hello\n' | nc -N 127.0.0.1 8081
sudo journalctl -b -u 'lk3-echo@*' --no-pager -n 20
```

Ожидаемый ответ клиенту:

```text
hello
```

В journal видны запуск и завершение экземпляра с переменной частью имени. Самой строки `hello` там может не быть: stdout направлен в сокет, а не в журнал. `-N` в netcat-openbsd закрывает отправку после окончания stdin, позволяя обработчику дочитать вход и завершиться.

### 7.4. Увидеть живой обработчик

В первом терминале Ubuntu выполните и оставьте соединение открытым:

```bash
nc 127.0.0.1 8081
```

Введите строку и нажмите Enter. Во втором терминале Ubuntu:

```bash
systemctl list-units 'lk3-echo@*.service' --no-pager
```

Теперь экземпляр должен оставаться активным. Закройте клиента через `Ctrl+C`.

<details>
<summary>Объяснение и связь с теорией</summary>

Systemd заранее открыл слушающий сокет. В режиме Accept=yes он принимает соединение и запускает обработчик именно для этого соединения. Cat получает готовые stdin/stdout, поэтому ему не нужна собственная поддержка сетевого протокола systemd. Для Accept=no приложение получает слушающий сокет и обычно само принимает подключения.

Наш Python http.server сам открывает порт и не использует автоматически переданный сокет. Простая замена ExecStart на http.server не реализует socket activation. Также один экземпляр здесь соответствует соединению, а не одному HTTP-запросу.

Если оставить socket активным, новое обращение снова запустит обработчик. Это отдельный механизм от Restart=. Остановка слушателя сама по себе не обязана завершить уже открытые соединения.

</details>

**Если ответа нет:** проверьте оба имени файлов, журнал экземпляра, владельца 8081 и `daemon-reload`. Команда `nc -N` должна выполняться в Ubuntu с пакетом netcat-openbsd.

<a id="fstab"></a>
## Опыт 8. Проверить копию fstab

**Вопрос:** может ли строка иметь правильный формат и всё равно помешать загрузке?

Создадим временную копию и добавим ссылку на отсутствующий ресурс. Настоящий `/etc/fstab` в этом опыте не редактируем, монтирование и reboot не нужны.

```bash
LAB_FSTAB=$(mktemp /tmp/lk3-fstab.XXXXXX)
cp /etc/fstab "$LAB_FSTAB"
printf '\n' >> "$LAB_FSTAB"
cat examples/07-fstab/invalid-entry.txt >> "$LAB_FSTAB"
findmnt --verify --verbose --tab-file "$LAB_FSTAB"
```

Ожидаем сообщения об отсутствующем источнике `UUID=1234-5678` и, вероятно, точке `/mnt/lk3-missing`. Например:

```text
0 parse errors, 2 errors, 0 warnings
unreachable on boot required target: No such file or directory
unreachable on boot required source: UUID=1234-5678
```

Точный текст и число замечаний зависят от содержимого исходного fstab, версии util-linux и прав. Ненулевой код завершения здесь ожидается. Удалите копию **в том же терминале**, где задали переменную:

```bash
rm "$LAB_FSTAB"
unset LAB_FSTAB
```

<details>
<summary>Что это объясняет про boot?</summary>

Systemd-fstab-generator создаёт mount-юниты из fstab. Обязательное монтирование может ждать отсутствующее устройство и привести к отказу зависимых заданий. Findmnt проверяет конфигурацию и доступность ресурсов, но ничего не монтирует. Строка бывает синтаксически корректной при отсутствующем UUID.

В реальном инциденте нужны консоль, проверка устройства и UUID, журнал и исправление исходной конфигурации. `nofail` меняет требования к загрузке, но не исправляет отсутствующий диск. Нельзя обещать доступную root-shell в emergency mode: в Ubuntu root может быть заблокирован. Намеренное повреждение настоящего fstab в основной семинар не входит.

</details>

<a id="finish"></a>
## Завершить и повторить семинар

### Проверить понимание

| Симптом | Следующая осмысленная проверка |
|---|---|
| После reboot нет SSH | Консоль VM: GRUB, initramfs, emergency или обычный login? |
| Служба failed | Журнал конкретного unit и ошибка последнего запуска |
| HTTP отвечает, нужный unit failed | Владелец порта из `ss` и MainPID нужной службы |
| Процесс есть, HTTP не отвечает | Адрес прослушивания, журнал, локальный запрос и готовность приложения |
| По IP работает, по имени нет | Разрешение имени, а затем HTTP Host / TLS SNI и остальные отличия запросов |

### Остановить опыты

Сначала закройте интерактивные `nc` через `Ctrl+C`. Затем **в Ubuntu**:

```bash
sudo systemctl disable --now course-web.service
sudo systemctl disable --now lk3-echo.socket
sudo systemctl stop lk3-port-holder.service
sudo systemctl stop 'lk3-echo@*.service'
systemctl is-active course-web.service
systemctl is-active lk3-echo.socket
sudo ss -ltnp '( sport = :8080 or sport = :8081 )'
```

Ожидаем inactive у course-web и lk3-echo.socket и отсутствие слушателей. Ненулевой код `is-active` при inactive нормален. Если экземпляров echo уже нет, команда их остановки не должна находить активные экземпляры. Тест памяти должен завершиться самостоятельно; если он ещё идёт, выполните `sudo systemctl stop lk3-memory.service`.

Остановите SSH-туннель на хосте через `Ctrl+C`, если открывали его. При желании выключите VM через `sudo poweroff`.

### Повторить с начала

**Предпочтительный способ:** выключить VM и восстановить снимок `lk3-ready`, затем запустить её и выполнить `bash scripts/check-environment.sh`. Не создавайте снимок с текущими изменениями поверх исходного. При восстановлении более старого снимка проверьте актуальность checkout: `git pull --ff-only`.

Простого `disable --now` недостаточно для чистого повторения: unit и restart/hardening drop-in остаются на диске.

**Ручной возврат после прохождения основного семинара**, если снимка нет:

1. Выполните остановку выше.
2. Если выполняли дополнительный опыт с таймером, сначала остановите и удалите его по инструкции ниже.
3. Удалите только файлы, установленные этим практикумом:

```bash
sudo rm -f \
  /etc/systemd/system/course-web.service \
  /etc/systemd/system/course-web.service.d/restart.conf \
  /etc/systemd/system/course-web.service.d/hardening.conf \
  /etc/systemd/system/lk3-echo.socket \
  /etc/systemd/system/lk3-echo@.service
sudo rmdir --ignore-fail-on-non-empty /etc/systemd/system/course-web.service.d
sudo systemctl daemon-reload
```

Если каталог drop-in уже удалён, сообщение rmdir об отсутствии каталога можно пропустить. Если внутри остались другие файлы, разберитесь с ними: автоматически удалять неизвестные дополнения не нужно.

Если memory-unit остался failed, сбросьте именно его:

```bash
if systemctl is-failed --quiet lk3-memory.service; then
  sudo systemctl reset-failed lk3-memory.service
fi
```

Затем:

```bash
cd ~/sre-systemd-lab
sudo bash scripts/prepare.sh
bash scripts/check-environment.sh
```

Это возвращает исходные файлы и проверки, но не очищает всю историю journal. Для одинаковой истории загрузки и полного исходного состояния используйте снимок VM.

<a id="timer"></a>
## Дополнительно. Календарный таймер

Этот пример относится к теории о timer-юнитах и **не входит в основной план 90 минут**. Его можно пройти по инструкции за 5–10 минут. Пользователь `course-web` должен быть создан шагом подготовки. Практическое применение таймера с восстановлением файлов есть в [опыте Д5](#extra-backup).

### Установить

```bash
cd ~/sre-systemd-lab
cat examples/08-timer/lk3-tick.service
cat examples/08-timer/lk3-tick.timer
sudo systemd-analyze verify examples/08-timer/lk3-tick.service examples/08-timer/lk3-tick.timer
sudo install -m 0644 examples/08-timer/lk3-tick.service examples/08-timer/lk3-tick.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lk3-tick.timer
systemctl list-timers --all lk3-tick.timer --no-pager
```

`lk3-tick.service` однократно печатает время через `date`. Таймер вызывает его на границе каждой минуты. `AccuracySec=1s` уменьшает допустимое окно срабатывания, но не превращает систему в real-time.

Дождитесь следующей минуты и проверьте:

```bash
sudo journalctl -b -u lk3-tick.service --no-pager -n 20
systemctl is-active lk3-tick.timer
systemctl is-active lk3-tick.service
```

В журнале должна появиться дата, например `2026-10-01T08:24:00+00:00`, с вашим текущим временем и часовым поясом. Timer остаётся active. Завершившийся oneshot без `RemainAfterExit=yes` обычно inactive — это нормальный успешный результат, а не отказ.

### Проверить Persistent

```bash
sudo systemctl stop lk3-tick.timer
```

Пропустите хотя бы одну границу минуты, затем:

```bash
sudo systemctl start lk3-tick.timer
sudo journalctl -b -u lk3-tick.service --no-pager -n 10
```

`Persistent=true` позволяет догнать пропущенное календарное срабатывание. Несколько пропущенных минут не создают очередь из такого же количества запусков. Дополнительный ближайший запуск по обычному расписанию возможен отдельно. Если service остаётся активным, таймер не создаёт вторую копию той же службы.

### Завершить дополнительный опыт

```bash
sudo systemctl disable --now lk3-tick.timer
sudo systemctl stop lk3-tick.service
sudo systemctl clean --what=state lk3-tick.timer
sudo rm /etc/systemd/system/lk3-tick.timer /etc/systemd/system/lk3-tick.service
sudo systemctl daemon-reload
```

Очистка state удаляет сохранённую отметку Persistent для нового прохождения.

<a id="extra"></a>
## Дополнительно. Мини-лабораторные с готовыми командами

Шесть независимых опытов для тех, кто хочет ещё поработать с systemd. Выбирайте любой, копируйте команды небольшими блоками и сравнивайте результат с пояснением. Сдавать работу или писать собственные скрипты не требуется. Эти опыты **не входят в основной план 90 минут**.

### Подготовка

Все команды ниже выполняются **в Ubuntu VM**, в обычном Bash-терминале. Подойдёт пользователь с `sudo` или `root`. Обновите репозиторий и установите инструменты:

```bash
cd ~/sre-systemd-lab
git pull --ff-only
sudo apt update
sudo apt install -y python3 curl util-linux
```

`nsenter` для Д2 входит в `util-linux`. Нужна полноценная Ubuntu с systemd в роли PID 1 и cgroups v2, как в основном практикуме. Предварительно запускать `course-web` или проходить остальные опыты не нужно.

| Опыт | Время | Что увидим |
|---|---|---|
| [Д1. Время работы](#extra-timeout) | 5 минут | Процесс остановлен по тайм-ауту |
| [Д2. PrivateTmp](#extra-private-tmp) | 7–10 минут | Один путь `/tmp` показывает разное содержимое |
| [Д3. CPUQuota](#extra-cpu) | 7–10 минут | Потребление CPU меняется без перезапуска процесса |
| [Д4. Шаблон службы](#extra-template) | 10 минут | Два независимо работающих сайта |
| [Д5. Резервная копия](#extra-backup) | 10–15 минут | Таймер создаёт архив, из которого возвращаем старый текст |
| [Д6. Path activation](#extra-path) | 10–15 минут | Появление файла запускает обработчик |

У опытов собственные имена `lk3-extra-*`. Команды очистки удаляют только их unit-файлы и учебные данные. В каждом опыте пройдите раздел очистки перед повтором. Если прервали опыт, вернитесь к его очистке. Опыты Д2 и Д3 автоматически ограничены 15 минутами; после этого потребуется повторный запуск. Переменные `LAB_*` действуют в текущем терминале: после переподключения выполните блок, в котором переменная присваивается.

<a id="extra-timeout"></a>
### Д1. Остановить слишком долгую задачу

**Что увидим:** процесс собирается работать 60 секунд, а systemd остановит его примерно через три. Такое ограничение полезно для зависших фоновых задач.

#### Запустить и посмотреть результат

```bash
sudo systemd-run --unit=lk3-extra-timeout \
  -p RuntimeMaxSec=3s \
  /usr/bin/sleep 60
sleep 5
systemctl show lk3-extra-timeout.service -p ActiveState -p Result
```

Ожидаем две строки (их порядок может отличаться):

```text
ActiveState=failed
Result=timeout
```

```bash
sudo journalctl -b -u lk3-extra-timeout.service --no-pager -n 15
```

В журнале найдите сообщение об истечении времени работы и остановке процесса. `failed` здесь — ожидаемый результат опыта. Если при сильной нагрузке ещё видно `active`, повторите проверку через пару секунд.

**Почему так:** `systemd-run` создал временную службу, а `RuntimeMaxSec` ограничил длительность её активной работы. Это отдельный параметр от `TimeoutStartSec`, который ограничивает фазу запуска. Сам `sleep` о лимите ничего не знает.

#### Очистка и повтор

```bash
sudo systemctl reset-failed lk3-extra-timeout.service
```

После сброса завершившаяся временная служба может исчезнуть из списка загруженных unit-ов — это нормально. Файл в `/etc/systemd/system` не создавался. Теперь можно повторить запуск.

**Если не получилось:** сообщение о существующем unit означает, что остался предыдущий запуск. Если он ещё работает, сначала выполните `sudo systemctl stop lk3-extra-timeout.service`; если находится в `failed`, сбросьте состояние командой выше.

<a id="extra-private-tmp"></a>
### Д2. Найти файл в приватном /tmp

**Что увидим:** служба создаёт `/tmp/lk3-extra-message.txt`, но обычный терминал не видит этот файл. Посмотрим на файловую систему глазами службы.

#### Установить и запустить

```bash
cd ~/sre-systemd-lab
cat extra/02-private-tmp/lk3-extra-tmp.service
sudo install -m 0644 extra/02-private-tmp/lk3-extra-tmp.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start lk3-extra-tmp.service
systemctl show lk3-extra-tmp.service -p ActiveState -p MainPID -p PrivateTmp
```

Ожидаем `ActiveState=active`, ненулевой `MainPID` и `PrivateTmp=yes`. Подготовительная команда `ExecStartPre` записала файл, затем служба запустила `sleep`, чтобы у нас было время рассмотреть её окружение.

#### Посмотреть снаружи и изнутри

```bash
ls -l /tmp/lk3-extra-message.txt
```

Ожидаем **No such file or directory** / **Нет такого файла или каталога** и ненулевой код команды. Это запланированное наблюдение. Если файл с таким именем уже существовал в общем `/tmp`, он является отдельным файлом и не относится к записи службы.

```bash
LAB_TMP_PID=$(systemctl show lk3-extra-tmp.service -p MainPID --value)
sudo nsenter --target "$LAB_TMP_PID" --mount -- \
  /usr/bin/cat /tmp/lk3-extra-message.txt
```

Ожидаем:

```text
hello from private tmp
```

**Почему так:** `PrivateTmp=yes` дал службе отдельные `/tmp` и `/var/tmp`. `nsenter --mount` запустил `cat` в том же пространстве монтирования, поэтому он увидел временный каталог службы. PID берём из systemd; конкретное число у каждого будет своим. `DynamicUser=yes` выделяет службе временного пользователя.

#### Очистка и повтор

```bash
sudo systemctl stop lk3-extra-tmp.service
sudo rm /etc/systemd/system/lk3-extra-tmp.service
sudo systemctl daemon-reload
```

Приватные временные файлы удаляются при остановке службы. Общий `/tmp` вручную чистить не нужно.

**Если не получилось:** при `MainPID=0` служба уже завершилась или не запустилась. Посмотрите `sudo journalctl -b -u lk3-extra-tmp.service --no-pager -n 20`, снова запустите службу и заново присвойте `LAB_TMP_PID`. Ошибка `nsenter: command not found` означает, что нужно установить `util-linux`.

<a id="extra-cpu"></a>
### Д3. Изменить лимит CPU работающей службы

**Что увидим:** один вычислительный процесс сначала получает до одного CPU, затем примерно 20% и 50% CPU. Его PID при изменении лимита сохраняется.

#### Запустить нагрузку и измерить

```bash
cd ~/sre-systemd-lab
cat extra/03-cpu/busy.py
sudo install -d -m 0755 /opt/lk3-extra
sudo install -m 0644 extra/03-cpu/busy.py /opt/lk3-extra/busy.py
sudo systemd-run --unit=lk3-extra-cpu \
  -p CPUAccounting=yes \
  -p CPUQuota=100% \
  -p RuntimeMaxSec=15min \
  /usr/bin/python3 /opt/lk3-extra/busy.py
systemctl show lk3-extra-cpu.service -p MainPID -p CPUQuotaPerSecUSec
python3 extra/03-cpu/measure-cpu.py
```

Последняя команда измеряет CPU-время всей cgroup службы за пять секунд. При свободном CPU результат обычно близок к `100% одного логического CPU`. Скрипт только читает статистику из `/sys/fs/cgroup`; его исходник лежит рядом с `busy.py`.

#### Применить квоты без перезапуска

```bash
sudo systemctl set-property --runtime lk3-extra-cpu.service CPUQuota=20%
systemctl show lk3-extra-cpu.service -p MainPID -p CPUQuotaPerSecUSec
python3 extra/03-cpu/measure-cpu.py
```

Ожидаем прежний PID, `CPUQuotaPerSecUSec=200ms` и потребление примерно 20% одного CPU.

```bash
sudo systemctl set-property --runtime lk3-extra-cpu.service CPUQuota=50%
systemctl show lk3-extra-cpu.service -p MainPID -p CPUQuotaPerSecUSec
python3 extra/03-cpu/measure-cpu.py
```

Теперь ожидаем `CPUQuotaPerSecUSec=500ms` и примерно 50%. На загруженном компьютере значения могут быть ниже: квота задаёт верхний предел, а не гарантированную долю. Небольшие отклонения измерения нормальны.

**Почему так:** systemd меняет ограничение CPU-времени cgroup работающей службы. `20%` — пятая часть одного логического CPU, даже если VM выделено несколько CPU. `--runtime` не сохраняет настройку после перезагрузки. В этом опыте сама служба тоже временная.

#### Очистка и повтор

```bash
sudo systemctl stop lk3-extra-cpu.service
sudo rm /opt/lk3-extra/busy.py
```

Не оставляйте вычислительный процесс работать после наблюдений. Если его уже остановил 15-минутный лимит и при повторе имя занято, выполните `sudo systemctl reset-failed lk3-extra-cpu.service`, затем повторите установку и запуск.

**Если не получилось:** сообщение о пропавшей cgroup означает, что служба завершилась; проверьте её журнал. Очень низкий первый результат может означать, что CPU хоста занят другими задачами. Сравнивайте несколько измерений и фактическое значение `CPUQuotaPerSecUSec`.

<a id="extra-template"></a>
### Д4. Запустить два сайта из одного шаблона

**Что увидим:** один unit-файл создаёт две службы с разными портами, страницами и журналами. Остановка одной не затрагивает вторую.

#### Подготовить страницы и шаблон

```bash
cd ~/sre-systemd-lab
sudo install -d -m 0755 /srv/lk3-extra-web/8082 /srv/lk3-extra-web/8083
printf 'site on 8082\n' | sudo tee /srv/lk3-extra-web/8082/index.html
printf 'site on 8083\n' | sudo tee /srv/lk3-extra-web/8083/index.html
sudo chmod 0644 /srv/lk3-extra-web/8082/index.html /srv/lk3-extra-web/8083/index.html
cat extra/04-template/lk3-extra-web@.service
sudo install -m 0644 extra/04-template/lk3-extra-web@.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start lk3-extra-web@8082.service lk3-extra-web@8083.service
```

В файле найдите `%i`: systemd подставит туда `8082` или `8083` из имени экземпляра. Подстановка используется и для порта, и для каталога со страницей.

#### Проверить независимость экземпляров

```bash
curl --fail --retry 5 --retry-delay 1 --retry-connrefused --max-time 3 http://127.0.0.1:8082/
curl --fail --retry 5 --retry-delay 1 --retry-connrefused --max-time 3 http://127.0.0.1:8083/
systemctl list-units 'lk3-extra-web@*.service' --no-pager
sudo journalctl -b -u lk3-extra-web@8082.service --no-pager -n 10
sudo journalctl -b -u lk3-extra-web@8083.service --no-pager -n 10
```

Ответы: `site on 8082` и `site on 8083`. В списке две активные службы, у каждой свой журнал HTTP-запросов.

```bash
sudo systemctl stop lk3-extra-web@8082.service
curl --fail --max-time 3 http://127.0.0.1:8082/
curl --fail --max-time 3 http://127.0.0.1:8083/
```

Первый `curl` должен завершиться ошибкой соединения — это ожидается. Второй продолжает возвращать `site on 8083`. Выполняйте команды по отдельности, даже если первая вернула ошибку.

#### Очистка и повтор

```bash
sudo systemctl stop lk3-extra-web@8082.service lk3-extra-web@8083.service
sudo rm /etc/systemd/system/lk3-extra-web@.service
sudo systemctl daemon-reload
sudo rm -r /srv/lk3-extra-web
```

**Если не получилось:** при `Address already in use` проверьте владельца порта через `sudo ss -ltnp '( sport = :8082 or sport = :8083 )'`. При `200/CHDIR` проверьте каталоги из первого блока, при HTTP 403 — права на страницы. Все обращения выполняются из Ubuntu, а не с localhost macOS/Windows.

<a id="extra-backup"></a>
### Д5. Сделать и восстановить резервную копию по таймеру

**Что увидим:** служба архивирует маленькую учебную папку. Таймер повторяет это каждую минуту. После изменения текста вернём его прежнюю версию из первого архива в отдельный каталог.

#### Подготовить файлы и сделать первую копию вручную

```bash
cd ~/sre-systemd-lab
sudo install -d -m 0755 /srv/lk3-extra-backup/source /srv/lk3-extra-backup/restore /opt/lk3-extra
printf 'version 1\n' | sudo tee /srv/lk3-extra-backup/source/message.txt
sudo chmod 0644 /srv/lk3-extra-backup/source/message.txt
sudo install -m 0644 extra/05-backup/backup.py /opt/lk3-extra/backup.py
cat extra/05-backup/lk3-extra-backup.service extra/05-backup/lk3-extra-backup.timer
sudo install -m 0644 extra/05-backup/lk3-extra-backup.service extra/05-backup/lk3-extra-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start lk3-extra-backup.service
sudo journalctl -b -u lk3-extra-backup.service --no-pager -n 10
```

Ожидаем `Created /var/lib/lk3-extra-backup/backup-<дата-и-время>.tar.gz`. `Type=oneshot` выполняет действие и завершается; `inactive` после успешной архивации нормально.

Сохраним имя первой копии **в текущем терминале** и посмотрим содержимое:

```bash
LAB_FIRST_BACKUP=$(sudo find /var/lib/lk3-extra-backup/ -maxdepth 1 -type f -name 'backup-*.tar.gz' | sort | head -n 1)
printf '%s\n' "$LAB_FIRST_BACKUP"
sudo tar -tzf "$LAB_FIRST_BACKUP"
```

В архиве есть `source/` и `source/message.txt`. Имя содержит UTC-время с микросекундами, поэтому повторный запуск создаёт новый архив. `StateDirectory=lk3-extra-backup` поручает systemd создать каталог данных, доступный временно выделенному пользователю службы. Для просмотра архива используем `sudo`.

#### Включить расписание и получить следующую копию

```bash
printf 'version 2\n' | sudo tee /srv/lk3-extra-backup/source/message.txt
sudo systemctl enable --now lk3-extra-backup.timer
systemctl list-timers --all lk3-extra-backup.timer --no-pager
```

Дождитесь времени `NEXT` из таблицы — обычно до минуты, с небольшим допустимым отклонением. Затем:

```bash
sudo journalctl -b -u lk3-extra-backup.service --no-pager -n 15
sudo find /var/lib/lk3-extra-backup/ -maxdepth 1 -type f -name 'backup-*.tar.gz' | sort
```

Ожидаем ещё один архив и новую запись `Created`. Если пока видна одна копия, дождитесь `NEXT` и повторите проверку. `Persistent=true` позволяет догнать пропущенное календарное срабатывание после неактивности таймера; он не создаёт отдельный архив за каждую пропущенную минуту.

#### Восстановить старый текст

```bash
sudo tar -xzf "$LAB_FIRST_BACKUP" -C /srv/lk3-extra-backup/restore
cat /srv/lk3-extra-backup/source/message.txt
cat /srv/lk3-extra-backup/restore/source/message.txt
```

Ожидаемый вывод:

```text
version 2
version 1
```

Получилось восстановить прежнее содержимое, сохранив текущий файл. Для настоящего бэкапа также нужны хранение вне исходного диска, срок хранения и контроль ошибок; здесь мы наблюдаем запуск по расписанию и проверяем восстановление небольшого файла.

#### Очистка и повтор

```bash
sudo systemctl disable --now lk3-extra-backup.timer
sudo systemctl stop lk3-extra-backup.service
sudo systemctl clean --what=state lk3-extra-backup.timer
sudo systemctl clean --what=state lk3-extra-backup.service
sudo rm /etc/systemd/system/lk3-extra-backup.timer /etc/systemd/system/lk3-extra-backup.service
sudo systemctl daemon-reload
sudo rm /opt/lk3-extra/backup.py
sudo rm -r /srv/lk3-extra-backup
unset LAB_FIRST_BACKUP
```

`clean --what=state` удаляет отметку `Persistent` у таймера и учебные архивы из `StateDirectory` службы. Сначала обязательно остановите timer и service, как в блоке выше.

**Если не получилось:** при пустом `LAB_FIRST_BACKUP` проверьте журнал первой ручной архивации. Если открыли новый терминал, повторите блок присваивания переменной. При ошибке доступа к исходному файлу проверьте режим `0644` и права `0755` на каталоги. Для повторения с первой версии сначала выполните очистку.

<a id="extra-path"></a>
### Д6. Запустить обработчик при появлении файла

**Что увидим:** активный `.path` ждёт конкретный файл. Как только файл появляется, systemd запускает готовый обработчик, который записывает результат и удаляет входной файл.

#### Установить наблюдение

```bash
cd ~/sre-systemd-lab
sudo install -d -m 0755 /var/lib/lk3-extra-inbox /opt/lk3-extra
sudo install -m 0644 extra/06-path/process-inbox.py /opt/lk3-extra/process-inbox.py
cat extra/06-path/lk3-extra-inbox.path extra/06-path/lk3-extra-inbox.service
sudo install -m 0644 extra/06-path/lk3-extra-inbox.path extra/06-path/lk3-extra-inbox.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lk3-extra-inbox.path
systemctl status lk3-extra-inbox.path --no-pager
```

Ожидаем **active (waiting)**. В чистом опыте обработчик ещё не запускался. `PathExists=` наблюдает за `/var/lib/lk3-extra-inbox/request.txt`. По общей основе имени `.path` связан с `lk3-extra-inbox.service`.

#### Передать первый файл

```bash
printf 'first message\n' | sudo tee /var/lib/lk3-extra-inbox/request.tmp
sudo mv /var/lib/lk3-extra-inbox/request.tmp /var/lib/lk3-extra-inbox/request.txt
sleep 1
sudo cat /var/lib/lk3-extra-inbox/processed.txt
sudo journalctl -b -u lk3-extra-inbox.service --no-pager -n 10
```

Ожидаем `Обработано: first message`. В журнале — запуск, сообщение `Processed request.txt -> processed.txt; input removed` и успешное завершение.

Сначала пишем временный файл, затем переименовываем его в наблюдаемое имя в том же каталоге. Так обработчик получает уже записанный файл. `processed.txt` хранит только последний результат.

#### Повторить с другими данными

```bash
printf 'second message\n' | sudo tee /var/lib/lk3-extra-inbox/request.tmp
sudo mv /var/lib/lk3-extra-inbox/request.tmp /var/lib/lk3-extra-inbox/request.txt
sleep 1
sudo cat /var/lib/lk3-extra-inbox/processed.txt
systemctl is-active lk3-extra-inbox.path
systemctl is-active lk3-extra-inbox.service
```

Ожидаем `Обработано: second message`, затем `active` у `.path` и `inactive` у завершившегося oneshot-сервиса. Последний `is-active` вернёт ненулевой код — это нормально. Если машина занята и обработка ещё идёт, повторите проверки через пару секунд.

**Почему обработчик удаляет входной файл:** условие `PathExists=` должно перестать выполняться. Иначе после завершения сервиса systemd снова увидит файл, повторит запуск и может дойти до ограничения частоты. Здесь один входной файл и один результат; новую запись отправляем после получения предыдущего результата. Это учебный пример запуска по событию файловой системы, не очередь сообщений.

В этом коротком опыте обработчик работает от root с `ProtectSystem=strict`; systemd оставляет доступным для записи его `StateDirectory`. Для приложения с более широкими функциями отдельно подбирают пользователя и права.

#### Очистка и повтор

```bash
sudo systemctl disable --now lk3-extra-inbox.path
sudo systemctl stop lk3-extra-inbox.service
sudo systemctl clean --what=state lk3-extra-inbox.service
sudo rm /etc/systemd/system/lk3-extra-inbox.path /etc/systemd/system/lk3-extra-inbox.service
sudo systemctl daemon-reload
sudo rm /opt/lk3-extra/process-inbox.py
```

`clean --what=state` удаляет каталог этого опыта вместе с входными и выходными файлами.

**Если не получилось:** проверьте `systemctl status lk3-extra-inbox.path --no-pager` и журнал сервиса. Убедитесь, что файл переименован именно в `request.txt`. Если изменяли пример и получили `start-limit-hit`, остановите `.path`, устраните причину по журналу, сбросьте состояния `sudo systemctl reset-failed lk3-extra-inbox.service lk3-extra-inbox.path`, затем снова запустите `.path`.

<a id="troubleshooting"></a>
## Если что-то не работает

| Симптом | Что проверить |
|---|---|
| ISO не загружается на Apple Silicon | Нужен `live-server-arm64.iso`; AMD64 в VirtualBox на ARM не запустится |
| VM сообщает об отсутствии загрузочного носителя | ISO подключён к виртуальному приводу? После установки загружается ли виртуальный диск? |
| В Windows недоступна аппаратная виртуализация | Включены ли Intel VT-x / AMD-V в UEFI хоста? После изменения перезагрузите хост |
| VirtualBox медленно работает рядом с Hyper-V/WSL2 | Обновите VirtualBox, остановите лишние VM и проверьте [известные ограничения](https://www.virtualbox.org/manual/topics/KnownIssues.html); изменение настроек гипервизора Windows требует отдельного решения |
| Ubuntu не получает сеть | Адаптер включён, NAT выбран, виртуальный кабель подключён; проверьте `ip -br address`, `ip route` |
| Пакеты не скачиваются | `getent hosts archive.ubuntu.com` / `getent hosts ports.ubuntu.com`, затем `sudo apt update`; ошибки DNS и HTTP решаются по-разному |
| SSH: Connection refused | VM запущена, правило NAT ведёт host 2222 → guest 22, внутри есть SSH-служба/сокет; проверьте `sudo ss -ltnp 'sport = :22'` |
| Host port 2222 уже занят | Выберите 2223 в правиле NAT и используйте его во всех SSH-командах |
| SSH: Permission denied | Имя и пароль относятся к Ubuntu, а не к macOS/Windows или GitHub |
| SSH сообщает о смене host key после переустановки | Сначала подтвердите, что VM действительно переустановлена; затем удалите только запись этого адреса: `ssh-keygen -R '[127.0.0.1]:2222'` |
| Команды не найдены или показывают macOS | Вы в терминале хоста; сначала войдите по SSH в Ubuntu |
| `System has not been booted with systemd` | Нужна полная Server VM; проверьте `ps -p 1 -o comm=` |
| Скрипт с Windows заканчивается `bash\r` / `$'\r'` | Клонируйте репозиторий внутри Ubuntu; `.gitattributes` задаёт LF для скриптов и unit-файлов |
| Unit не найден | Установлен ли файл в `/etc/systemd/system/`, выполнен ли `daemon-reload`? |
| Curl иногда отказывает сразу после start | Type=exec ещё не гарантирует открытый порт; используйте показанный curl с ограниченными повторами, затем смотрите журнал |
| Curl работает, нужный unit failed | Определите владельца порта через `sudo ss -ltnp` |
| После snapshot восстановились старые настройки | Восстановлен ли именно `lk3-ready`, созданный до установки основной службы и drop-in? |
| `start-limit-hit` | Сначала устраните причину сбоя, затем `sudo systemctl reset-failed course-web` и `sudo systemctl start course-web` |
| Memory-unit уже существует | Проверьте его состояние; завершившийся failed-unit сбросьте через reset-failed перед повтором |
| Netcat не понимает `-N` | Выполняйте команду внутри Ubuntu с пакетом `netcat-openbsd` |

Если VM не отвечает, сначала откройте её консоль в VirtualBox. Не начинайте с переустановки или изменения нескольких настроек одновременно: зафиксируйте сообщение и последний успешный шаг.

<a id="verification"></a>
## Проверка материалов и первоисточники

Команды основных опытов проверены 1 октября 2026 года на **Ubuntu 26.04.1 ARM64, systemd 259.5**, в отдельном контейнере с настоящим systemd в роли PID 1 и cgroups v2. Воспроизведены HTTP, конфликт порта, автоматический restart, остановка, cgroup OOM, файловая изоляция, socket activation, проверка копии fstab и календарный timer. Подробности и границы проверки — в [VALIDATION.md](VALIDATION.md).

Дополнительные опыты **Д1–Д6 проверены 2 октября 2026 года** в таком же отдельном окружении: выполнены блоки команд из README, проверены результаты и очистка. Затем все шесть опытов повторены обычным пользователем с `sudo` после первого прохождения от root. Подтверждены тайм-аут, приватный `/tmp`, изменение CPUQuota, два экземпляра шаблона, восстановление из архива и запуск через `.path`.

Установка VirtualBox на macOS/Windows, загрузка UEFI, SSH через NAT и восстановление снимка в рамках этой проверки не воспроизводились. Перед показом пройдите установку и короткую репетицию на конкретном компьютере. Контейнерная проверка не заменяет загрузку полноценной VM.

Источники для подготовки и разбора отличий версий:

- [VirtualBox: загрузки](https://www.virtualbox.org/wiki/Downloads), [установка и поддерживаемые хосты](https://www.virtualbox.org/manual/topics/installation.html).
- [VirtualBox: сочетания архитектур хоста и гостя](https://www.virtualbox.org/manual/topics/Introduction.html), [ограничения ARM и другие известные проблемы](https://www.virtualbox.org/manual/topics/KnownIssues.html).
- [VirtualBox: NAT и проброс портов](https://www.virtualbox.org/manual/topics/networkingdetails.html).
- [Ubuntu 26.04: изменения для пользователей LTS](https://documentation.ubuntu.com/release-notes/26.04/summary-for-lts-users/).
- [systemd.service](https://github.com/systemd/systemd/blob/v259.5/man/systemd.service.xml), [systemd.unit](https://github.com/systemd/systemd/blob/v259.5/man/systemd.unit.xml), [systemctl](https://github.com/systemd/systemd/blob/v259.5/man/systemctl.xml).
- [systemd.resource-control](https://github.com/systemd/systemd/blob/v259.5/man/systemd.resource-control.xml), [systemd.exec](https://github.com/systemd/systemd/blob/v259.5/man/systemd.exec.xml).
- [systemd.socket](https://github.com/systemd/systemd/blob/v259.5/man/systemd.socket.xml), [systemd.timer](https://github.com/systemd/systemd/blob/v259.5/man/systemd.timer.xml).
- [systemd.path](https://github.com/systemd/systemd/blob/v259.5/man/systemd.path.xml), [systemd-run](https://github.com/systemd/systemd/blob/v259.5/man/systemd-run.xml), [nsenter](https://man7.org/linux/man-pages/man1/nsenter.1.html).
- [findmnt](https://man7.org/linux/man-pages/man8/findmnt.8.html), [Python http.server](https://docs.python.org/3/library/http.server.html).
