#import "../style/style.typ": apply-style
        #show: apply-style
        #set document(
        title: "Document Processing & Printing Architecture — план разработки",
        author: "Mykola Ruban",
        description: "Document Processing & Printing Architecture — план разработки",
        keywords: ("typst", "pdf", "review", "task", "tasks", "rabbitmq", "print", "redis", "status", "раздел", "workflow", "cloudready", "data"),
        )
        = Document Processing & Printing Architecture — план разработки

Источник: [img/schema04.png](img/schema04.png) (Linux + Docker Compose | RabbitMQ — брокер задач, Redis — locks/cache/notifications | NST — печать).

Этот файл — рабочий план для разработки: структура хоста, каркас репозитория, контракты JSON API по каждому сервису, таблицы статусов.

---

== 1. компоненты (по схеме)

#table(
  columns: 3,
  table.header(
    [Компонент], [Роль], [Технология],
  ),
  [Web Task Monitor], [UI оператора: статусы, логи, health], [статический/SPA фронтенд],
  [FastAPI Container], [REST API, auth, интеграция с Business Central, WebSocket], [Python / FastAPI],
  [RabbitMQ Container], [брокер задач: очереди по типу, priority, TTL, retry, DLQ], [RabbitMQ],
  [Worker Container(s)], [исполнение задач: печать, конвертация, PDF, FTP/SFTP, workflow], [Python (Celery/consumer)],
  [Redis Container], [locks, cache (task status, auth, BC data), Pub/Sub (WS notifications)], [Redis],
  [PostgreSQL Container], [источник истины: tasks, документы, логи, конфигурация, пользователи], [PostgreSQL],
  [NST (Navision Service Tier)], [print gateway: приём заданий, выбор принтера, печать через Windows spooler], [внешний сервис (Business Central)],
  [FTP/SFTP Server], [обмен файлами], [внешний сервис],
  [Typst], [генерация PDF по шаблонам], [вызывается воркером],
)


---

== 2. структура linux-хоста

Раскладка volumes и конфигурации на хосте (то, что монтируется в контейнеры через `docker-compose.yml`).

#quote(block: true)[*TODO (улучшение, не блокирует старт):* сейчас деплой и владение `/opt/cloudready-tasks/` — под личным пользовательским аккаунтом на хосте. Перейти на выделенный системный сервисный аккаунт без логина (`useradd --system --no-create-home --shell /usr/sbin/nologin cloudready`), владелец каталога и всех файлов — этот аккаунт, права `750`. Снимает риск "сервис пропал вместе с личным доступом/учёткой" и приводит права к принятой практике для production-сервисов на Linux.]


```bash
/opt/cloudready-tasks/                # корень деплоя на хосте
├── docker-compose.yml
├── .env                                # секреты/переменные окружения (не в git)
├── .env.example
│
├── app/                                 # bind-mount → /app/_ внутри контейнеров
│   ├── data/
│   │   └── documents/                   # /app/data/documents — сгенерированные и загруженные файлы
│   │       ├── incoming/
│   │       ├── generated/
│   │       └── archive/
│   │
│   ├── templates/                       # /app/templates — Typst-шаблоны документов
│   │   ├── invoice.typ
│   │   ├── label.typ
│   │   └── report.typ
│   │
│   ├── config/                          # /app/config — конфигурация приложения
│   │   ├── printers.yaml                # список принтеров NST/Windows
│   │   ├── workflows.yaml               # описание workflow по типам задач
│   │   ├── ftp.yaml                     # профили FTP/SFTP
│   │   └── rabbitmq/
│   │       ├── definitions.json         # очереди/exchange/bindings (import при старте)
│   │       └── rabbitmq.conf
│   │
│   └── logs/                            # /app/logs — логи приложения (ротация через logrotate)
│       ├── api/
│       ├── worker/
│       └── rabbitmq/
│
├── volumes/                             # именованные docker volumes (персистентные данные СУБД/брокеров)
│   ├── postgres-data/
│   ├── rabbitmq-data/
│   └── redis-data/
│
├── smb/                                 # точки монтирования Windows SMB share (cifs-utils)
│   ├── exchange/                        # //WIN-FILESRV/exchange  — входящие/исходящие файлы
│   ├── archive/                         # //WIN-FILESRV/archive   — архив документов
│   └── shared/                          # //WIN-FILESRV/shared    — общие бизнес-файлы
│
└── ops/
    ├── backup/
    │   ├── backup-postgres.sh
    │   └── backup-volumes.sh
    ├── healthcheck/
    │   └── check-stack.sh
    └── logrotate.d/
        └── cloudready
```

Монтирование SMB на хосте (`/etc/fstab`, пример):

```bash
//WIN-FILESRV/exchange  /opt/cloudready-tasks/smb/exchange  cifs  credentials=/opt/cloudready-tasks/.smbcredentials,uid=1000,gid=1000,iocharset=utf8,vers=3.0  0  0
//WIN-FILESRV/archive   /opt/cloudready-tasks/smb/archive   cifs  credentials=/opt/cloudready-tasks/.smbcredentials,uid=1000,gid=1000,iocharset=utf8,vers=3.0  0  0
//WIN-FILESRV/shared    /opt/cloudready-tasks/smb/shared    cifs  credentials=/opt/cloudready-tasks/.smbcredentials,uid=1000,gid=1000,iocharset=utf8,vers=3.0  0  0
```

---

== 3. каркас репозитория (приложение)

Реализация — в отдельном репозитории `cloudready-tasks` (этот репозиторий, `CloudReady-Notes`, остаётся документацией/заметками; сам сервис в нём не разрабатывается). Монорепозиторий: один `docker-compose.yml`, отдельные сервисы в `services/`, общий код в `libs/`.

```bash
cloudready-tasks/
├── docker-compose.yml
├── docker-compose.override.yml          # локальная разработка (hot-reload, exposed ports)
├── Makefile                             # make up / down / logs / migrate / test
├── .env.example
│
├── services/
│   │
│   ├── api/                             # FastAPI Container
│   │   ├── Dockerfile
│   │   ├── pyproject.toml
│   │   ├── alembic/                     # миграции PostgreSQL
│   │   │   └── versions/
│   │   ├── app/
│   │   │   ├── main.py                  # entrypoint, роутеры, lifespan
│   │   │   ├── api/
│   │   │   │   ├── v1/
│   │   │   │   │   ├── tasks.py         # POST/GET /tasks
│   │   │   │   │   ├── print.py         # POST /tasks/print
│   │   │   │   │   ├── documents.py     # POST /tasks/convert, /tasks/generate
│   │   │   │   │   ├── printers.py      # GET /printers, /printers/{id}/status
│   │   │   │   │   ├── health.py        # GET /health, /health/ready
│   │   │   │   │   └── ws.py            # WS /ws/tasks?task_id= (опциональный фильтр)
│   │   │   │   └── deps.py              # auth, DB session, RabbitMQ publisher, Redis client
│   │   │   ├── core/
│   │   │   │   ├── config.py            # Settings (env)
│   │   │   │   ├── security.py          # auth & JWT/BC integration
│   │   │   │   └── logging.py
│   │   │   ├── models/                  # SQLAlchemy модели (Task, Document, User, Workflow)
│   │   │   ├── schemas/                 # Pydantic-схемы запросов/ответов
│   │   │   ├── services/
│   │   │   │   ├── task_service.py      # создание задач, запись в PostgreSQL
│   │   │   │   ├── bc_client.py         # интеграция с Business Central (NST)
│   │   │   │   ├── mq_publisher.py      # публикация в RabbitMQ (exchange/routing key)
│   │   │   │   ├── cache.py             # Redis: cache task status
│   │   │   │   └── notifier.py          # Redis Pub/Sub → WebSocket broadcast
│   │   │   └── db/
│   │   │       └── session.py
│   │   └── tests/
│   │
│   ├── worker/                          # Worker Container(s)
│   │   ├── Dockerfile
│   │   ├── pyproject.toml
│   │   ├── worker/
│   │   │   ├── main.py                  # consumer entrypoint (celery worker / aio-pika consumer)
│   │   │   ├── dispatcher.py            # маршрутизация по routing key → handler
│   │   │   ├── handlers/
│   │   │   │   ├── print_handler.py     # NST client: submit print job, poll status
│   │   │   │   ├── pdf_handler.py       # Typst: generate PDF
│   │   │   │   ├── convert_handler.py   # document conversion
│   │   │   │   ├── ftp_handler.py       # FTP/SFTP upload/download
│   │   │   │   └── workflow_executor.py # многошаговые workflow (workflows.yaml)
│   │   │   ├── clients/
│   │   │   │   ├── nst_client.py
│   │   │   │   ├── typst_client.py
│   │   │   │   └── storage_client.py
│   │   │   └── core/
│   │   │       ├── config.py
│   │   │       └── locks.py             # Redis distributed locks
│   │   └── tests/
│   │
│   └── web-task-monitor/                # Web Task Monitor (SPA)
│       ├── Dockerfile
│       ├── package.json
│       └── src/
│           ├── pages/
│           │   ├── Dashboard.tsx
│           │   ├── TaskList.tsx
│           │   ├── TaskDetails.tsx
│           │   ├── WorkflowView.tsx
│           │   └── PrinterStatus.tsx
│           └── api/client.ts
│
├── libs/
│   └── common/                          # общие для api и worker: enums статусов, DTO, MQ-схема
│       ├── statuses.py
│       ├── events.py
│       └── mq_topology.py               # описание exchange/queues/routing keys как код
│
└── infra/
    ├── rabbitmq/
    │   └── definitions.json             # очереди, DLX, bindings
    ├── postgres/
    │   └── init.sql
    └── grafana-dashboards/              # опционально, для Roles Summary → Observable
```

=== 3.1 `docker-compose.yml` (пример)

Раскладка сервисов на хост-структуру из раздела 2 и репозиторий из раздела 3. Порты RabbitMQ/Redis/PostgreSQL не публикуются наружу — только внутри `backend`-сети (раздел 8, "Сетевая изоляция"); наружу смотрят `api` (за reverse proxy) и `web-task-monitor`.

```yaml
= /opt/cloudready-tasks/docker-compose.yml
services:

  api:
    build: ./services/api
    image: cloudready/api:latest
    restart: unless-stopped
    env_file: .env
    environment:
      DATABASE_URL: postgresql+asyncpg://cloudready:${POSTGRES_PASSWORD}@postgres:5432/cloudready
      RABBITMQ_URL: amqp://cloudready:${RABBITMQ_PASSWORD}@rabbitmq:5672/
      REDIS_URL: redis://redis:6379/0
    volumes:
      - ./app/data/documents:/app/data/documents
      - ./app/templates:/app/templates:ro
      - ./app/config:/app/config:ro
      - ./app/logs/api:/app/logs
    ports:
      - "127.0.0.1:8000:8000"        # только на loopback, наружу — через reverse proxy на хосте
    depends_on:
      postgres: { condition: service_healthy }
      rabbitmq: { condition: service_healthy }
      redis: { condition: service_healthy }
    networks: [backend]

  worker:
    build: ./services/worker
    image: cloudready/worker:latest
    restart: unless-stopped
    env_file: .env
    environment:
      DATABASE_URL: postgresql+asyncpg://cloudready:${POSTGRES_PASSWORD}@postgres:5432/cloudready
      RABBITMQ_URL: amqp://cloudready:${RABBITMQ_PASSWORD}@rabbitmq:5672/
      REDIS_URL: redis://redis:6379/0
      NST_BASE_URL: ${NST_BASE_URL}
      NST_CALLBACK_SECRET: ${NST_CALLBACK_SECRET}
    volumes:
      - ./app/data/documents:/app/data/documents
      - ./app/templates:/app/templates:ro
      - ./app/config:/app/config:ro
      - ./app/logs/worker:/app/logs
      - ./smb/exchange:/mnt/smb/exchange
      - ./smb/archive:/mnt/smb/archive
    deploy:
      replicas: 2                     # Worker Container(s) (1..N) — раздел 9, многоворкерная координация
    depends_on:
      rabbitmq: { condition: service_healthy }
      redis: { condition: service_healthy }
    networks: [backend]

  web-task-monitor:
    build: ./services/web-task-monitor
    image: cloudready/web-task-monitor:latest
    restart: unless-stopped
    environment:
      API_BASE_URL: ${PUBLIC_API_URL}
    ports:
      - "127.0.0.1:8080:80"
    depends_on: [api]
    networks: [backend]

  rabbitmq:
    image: rabbitmq:3.13-management
    restart: unless-stopped
    environment:
      RABBITMQ_DEFAULT_USER: cloudready
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASSWORD}
    volumes:
      - rabbitmq-data:/var/lib/rabbitmq
      - ./app/config/rabbitmq/definitions.json:/etc/rabbitmq/definitions.json:ro
      - ./app/config/rabbitmq/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf:ro
      - ./app/logs/rabbitmq:/var/log/rabbitmq
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "check_running"]
      interval: 15s
      timeout: 10s
      retries: 5
    networks: [backend]
    # порт 5672/15672 не публикуется наружу — доступ только из backend-сети (раздел 8)

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 15s
      timeout: 5s
      retries: 5
    networks: [backend]

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: cloudready
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: cloudready
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./infra/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U cloudready"]
      interval: 15s
      timeout: 5s
      retries: 5
    networks: [backend]

networks:
  backend:
    driver: bridge

volumes:
  postgres-data:
    external: true      # указывает на /opt/cloudready-tasks/volumes/postgres-data (раздел 2)
  rabbitmq-data:
    external: true
  redis-data:
    external: true
```

`docker-compose.override.yml` (локальная разработка) добавляет `ports` для прямого доступа к `rabbitmq` (15672), `postgres` (5432), монтирует исходники в `api`/`worker` с `--reload`/hot-reload вместо собранного образа — не используется в проде.

---

== 4. rabbitmq: топология очередей

#table(
  columns: 5,
  table.header(
    [Exchange], [Тип], [Routing key], [Очередь], [Назначение],
  ),
  [`tasks.direct`], [direct], [`task.print`], [`q.print`], [задания печати → Worker → NST],
  [`tasks.direct`], [direct], [`task.pdf.generate`], [`q.pdf.generate`], [генерация PDF через Typst],
  [`tasks.direct`], [direct], [`task.convert`], [`q.convert`], [конвертация документов],
  [`tasks.direct`], [direct], [`task.ftp`], [`q.ftp`], [загрузка/выгрузка FTP/SFTP],
  [`tasks.direct`], [direct], [`task.workflow`], [`q.workflow`], [многошаговые workflow],
  [`tasks.dlx`], [fanout], [—], [`q.dead_letter`], [задачи, отклонённые N раз подряд],
)


Параметры очередей: `durable: true` на всех exchange/queues, сообщения публикуются с `delivery_mode=2` (persistent) — иначе volume `rabbitmq-data` не спасает от потери сообщений при рестарте контейнера. Плюс `x-message-ttl`, `x-max-priority` (0–10), `x-dead-letter-exchange: tasks.dlx`.

=== 4.1 Надёжная публикация задачи (outbox pattern)

`task_service.py` пишет в PostgreSQL и `mq_publisher.py` публикует в RabbitMQ — это два независимых действия. Если процесс упадёт между ними, задача может остаться в БД без сообщения в очереди (зависнет навсегда) либо наоборот. Решение — transactional outbox:

1. Создание задачи и вставка строки в `tasks_outbox` (`task_id`, `payload`, `published: false`) — одна транзакция PostgreSQL.
2. Отдельный фоновый процесс (в `worker` или отдельный `outbox-relay`) опрашивает `tasks_outbox WHERE published = false`, публикует в RabbitMQ, помечает `published = true` в той же транзакции, что и коммит с уровнем изоляции, исключающим двойную публикацию (`SELECT … FOR UPDATE SKIP LOCKED`).
3. `tasks.payload` (JSONB) хранит *полное* тело исходного запроса — не только ссылку. Это же поле используется эндпоинтом `/retry` (раздел 5.1) для повторной публикации из `dead_letter`, так как RabbitMQ не гарантирует хранение сообщения вечно и не предназначен быть источником для ручного replay через API.

*Идемпотентность — требование ко всем handler'ам, не только к печати.* Outbox-relay гарантирует минимум одну публикацию, RabbitMQ — минимум одну доставку: дубли возможны на каждом шаге, для любого типа задачи. `print_handler.py` проверяет `print_jobs.nst_job_ref` (раздел 5.2) — по тому же принципу:
- `ftp_handler.py` перед `upload` проверяет, не был ли этот `task_id` уже успешно загружен (например, по логу выполненных FTP-задач в БД), иначе повторная доставка сообщения загрузит файл на FTP второй раз;
- `pdf_handler.py`/`convert_handler.py` естественно идемпотентны за счёт атомарной записи по `task_id` в имени файла (раздел 5.1) — повторный рендер просто перезапишет тот же путь, побочного эффекта вовне нет.

Общее правило: любой handler, вызывающий *внешнюю* систему (NST, FTP/SFTP) с необратимым побочным эффектом, обязан сначала проверить, не выполнен ли уже этот `task_id`, и только затем действовать.

---

== 5. json-контракты api

=== 5.1 FastAPI Container — REST API

==== `POST /api/v1/tasks/print` — создать задание печати

Запрос:
```json
{
  "document": {
    "source": "generated",
    "reference": "doc_8f21c4",
    "format": "pdf"
  },
  "printer": {
    "id": "office-printer-01",
    "name": "Office Printer"
  },
  "priority": 5,
  "copies": 1,
  "idempotency_key": "bc-po-2026-00114-print-1",
  "metadata": {
    "bc_document_no": "PO-2026-00114",
    "requested_by": "user@gmail.com"
  }
}
```

`priority`: целое `0–10` (соответствует `x-max-priority` очереди), по умолчанию `5`. `idempotency_key` — опционален; если задача с таким ключом уже существует, API возвращает существующий `task_id` вместо создания дубликата (защита от повторной отправки при retry на стороне клиента/BC).

Ответ `202 Accepted`:
```json
{
  "task_id": "t_7c1e9a3b",
  "type": "print",
  "status": "queued",
  "queue": "q.print",
  "created_at": "2026-09-10T09:14:22Z",
  "links": {
    "self": "/api/v1/tasks/t_7c1e9a3b",
    "ws": "/ws/tasks?task_id=t_7c1e9a3b"
  }
}
```

==== `POST /api/v1/tasks/{task_id}/cancel` — отменить задачу

Допустимо только пока `status` в (`pending`, `queued`, `retrying`). Помечает `tasks.status = cancelled` в БД — этого *недостаточно*, чтобы удалить уже поставленное в RabbitMQ сообщение: `dispatcher.py` в воркере обязан перед выполнением каждого сообщения свериться с текущим статусом задачи (Redis-кеш, не БД — чтобы не бить по PostgreSQL на каждое сообщение) и молча завершить (`ack` без выполнения), если `status = cancelled`. Без этой проверки на стороне воркера "отмена" — иллюзия только в UI.
```json
{ "task_id": "t_7c1e9a3b", "status": "cancelled", "cancelled_at": "2026-09-10T09:16:02Z" }
```

==== `POST /api/v1/tasks/{task_id}/retry` — вручную повторить задачу из `dead_letter`

Требует роль оператора (Web Task Monitor). Сбрасывает `attempts`, публикует в исходную очередь *новое* сообщение, собранное из `tasks.payload` (раздел 4.1) — не пытается извлечь оригинальное сообщение из RabbitMQ DLQ.
```json
{ "task_id": "t_5b3e11aa", "status": "queued", "attempts": 0, "requeued_at": "2026-09-10T09:20:00Z" }
```

==== `POST /api/v1/documents` — загрузить внешний файл на печать (без генерации через Typst)

`multipart/form-data`: поле `file` (PDF/DOCX/…). Ответ `201 Created`:
```json
{
  "document_id": "doc_e51fa2",
  "filename": "external-invoice.pdf",
  "format": "pdf",
  "size_bytes": 184320,
  "stored_at": "/app/data/documents/incoming/doc_e51fa2.pdf"
}
```
Используется затем как `"document": { "source": "uploaded", "reference": "doc_e51fa2" }` в `POST /tasks/print`.

==== `POST /api/v1/tasks/generate` — сгенерировать PDF по шаблону (Typst)

Запрос:
```json
{
  "template": "invoice.typ",
  "data": {
    "invoice_no": "INV-2026-000481",
    "customer": "Hennlich CZ s.r.o.",
    "items": [
      { "sku": "HN-1023", "qty": 2, "price": 149.90 }
    ]
  },
  "output": {
    "filename": "invoice-INV-2026-000481.pdf",
    "store_to": "/app/data/documents/generated"
  },
  "priority": 3
}
```

Файл пишется воркером как `generated/{task_id}__invoice-INV-2026-000481.pdf` (временное имя + атомарный `rename` после успешного рендера), а не напрямую под `filename` из запроса — иначе повторный прогон (retry из раздела 7, до 2 попыток) может перезаписать файл первой попытки в момент, когда он уже используется на шаге печати workflow. `filename` в ответе задачи — то, что видит пользователь; физический путь на диске включает `task_id`.

Ответ `202 Accepted`:
```json
{
  "task_id": "t_a92f0d17",
  "type": "pdf.generate",
  "status": "queued",
  "queue": "q.pdf.generate",
  "created_at": "2026-09-10T09:15:01Z"
}
```

==== `GET /api/v1/tasks/{task_id}` — статус задачи

Ответ `200 OK`:
```json
{
  "task_id": "t_7c1e9a3b",
  "type": "print",
  "status": "running",
  "attempts": 1,
  "max_attempts": 3,
  "created_at": "2026-09-10T09:14:22Z",
  "updated_at": "2026-09-10T09:14:26Z",
  "result": null,
  "error": null,
  "history": [
    { "status": "queued", "at": "2026-09-10T09:14:22Z" },
    { "status": "running", "at": "2026-09-10T09:14:25Z", "worker": "worker-02" }
  ]
}
```

==== `GET /api/v1/tasks?status=failed&type=print&limit=50` — список задач (Web Task Monitor)

Ответ `200 OK`:
```json
{
  "items": [
    {
      "task_id": "t_5b3e11aa",
      "type": "print",
      "status": "failed",
      "error": { "code": "NST_PRINTER_OFFLINE", "message": "Printer office-printer-01 is offline" },
      "attempts": 3,
      "updated_at": "2026-09-10T08:59:10Z"
    }
  ],
  "page": { "limit": 50, "next_cursor": null, "total": 1 }
}
```

==== `GET /api/v1/printers` — статусы принтеров (для Printer Status в мониторе)

Ответ `200 OK`:
```json
{
  "printers": [
    { "id": "office-printer-01", "name": "Office Printer", "status": "online", "queue_length": 2 },
    { "id": "label-printer-01", "name": "Label Printer", "status": "offline", "queue_length": 0 }
  ]
}
```

==== `POST /api/v1/tasks/convert` — конвертация документа

Запрос:
```json
{
  "document": { "source": "uploaded", "reference": "doc_e51fa2", "format": "docx" },
  "target_format": "pdf",
  "priority": 4
}
```

Ответ `202 Accepted`:
```json
{
  "task_id": "t_d40b6e2c",
  "type": "convert",
  "status": "queued",
  "queue": "q.convert",
  "created_at": "2026-09-10T09:17:10Z"
}
```

==== `POST /api/v1/tasks/workflow` — запустить многошаговый workflow

Запрос:
```json
{
  "workflow": "invoice-generate-print-archive",
  "input": {
    "invoice_no": "INV-2026-000481",
    "printer_id": "office-printer-01",
    "archive_profile": "exchange-outgoing"
  },
  "priority": 5
}
```

Ответ `202 Accepted`:
```json
{
  "task_id": "t_f118a0c9",
  "type": "workflow",
  "status": "queued",
  "queue": "q.workflow",
  "steps": ["pdf.generate", "print", "ftp.upload"],
  "created_at": "2026-09-10T09:18:00Z"
}
```

Статус родительской `workflow`-задачи агрегируется из статусов шагов (раздел 6.1) — `failed`, если отказал любой шаг без успешного retry; `success`, только если завершены все шаги.

*Модель оркестрации — асинхронная saga, не блокирующий процесс.* `workflow_executor.py` не ждёт синхронно (в одном воркер-процессе) завершения `pdf.generate → print → ftp.upload` — иначе падение воркера теряет весь прогресс, несмотря на то, что каждый шаг формально в своей очереди. Вместо этого:
1. Таблица `workflow_steps` (`workflow_task_id`, `step_index`, `step_type`, `status`, `child_task_id`) фиксирует прогресс в PostgreSQL.
2. `workflow_executor.py` публикует шаг *не напрямую через `mq_publisher.py`*, а тем же вызовом `task_service.create_task()`, что и обычный API-запрос — то есть через outbox (раздел 4.1). Иначе прямая публикация в обход outbox воссоздаёт ту же проблему потери сообщения между записью прогресса в `workflow_steps` и фактической отправкой в RabbitMQ, от которой outbox должен защищать.
3. По завершении шага (`task.status_changed → success`, событие из `notifier.py`) executor читает `workflow_steps`, находит следующий незавершённый шаг и публикует его.
4. При перезапуске воркера executor восстанавливает прогресс из `workflow_steps`, а не из памяти — состояние workflow переживает падение любого отдельного воркер-процесса.

==== `WS /ws/tasks?task_id={id}` — обновления статусов в реальном времени (через Redis Pub/Sub)

Один эндпоинт на всех клиентов: без параметра `task_id` авторизованный клиент получает события по всем задачам, доступным его роли (используется Web Task Monitor); с параметром — только события конкретной задачи (используется клиентом, создавшим задачу). Фильтрация — на стороне API при публикации в сокет, не на клиенте.

WS — best-effort канал живых обновлений, не источник истины: Redis Pub/Sub ничего не буферизует, и событие, опубликованное пока клиент (или сам FastAPI-инстанс) был отключён, теряется без следа. Клиент обязан при каждом (пере)подключении сначала вызвать `GET /api/v1/tasks/{task_id}` (или `GET /api/v1/tasks?...` для общего потока), чтобы получить актуальный статус, и только затем полагаться на WS для последующих изменений.

Сообщение от сервера:
```json
{
  "event": "task.status_changed",
  "task_id": "t_7c1e9a3b",
  "status": "success",
  "at": "2026-09-10T09:14:31Z"
}
```

---

=== 5.2 Worker → NST — печать документа

NST на схеме — отдельный Windows-хост (Navision Service Tier), не контейнер в этом docker-compose. Значит `document_url`/`callback_url` не могут указывать на Docker-internal DNS-имя (`api:8000`) — NST его не резолвит. Используется реальный сетевой адрес API-хоста (LAN IP или DNS-имя за reverse proxy), и раз этот адрес теперь достижим с внешнего (по отношению к docker-сети) хоста, `/internal/documents/{id}` требует такой же аутентификации, как и `/internal/print-callback` — не "внутренний" эндпоинт в смысле безопасности, только в смысле неймспейса.

Запрос (Worker → NST Print Gateway):
```json
{
  "job_id": "t_7c1e9a3b",
  "document_url": "https://cloudready.hennlich.local/internal/documents/doc_8f21c4",
  "format": "pdf",
  "printer_name": "Office Printer",
  "copies": 1,
  "callback_url": "https://cloudready.hennlich.local/internal/print-callback"
}
```

`document_url` подписывается TTL-токеном (query-параметр), NST авторизуется им же при скачивании файла — токен выдаётся `print_handler.py` при формировании запроса, отдельного логина для NST не требуется. TTL должен превышать реалистичное время ожидания в очереди Windows Spooler (статус `queued` в разделе 6.2), а не только время самого HTTP-запроса — иначе задание, вставшее в спулере позади других, получит ошибку скачивания файла к моменту, когда NST наконец до него дойдёт. Если NST кэширует файл сразу при `received` (до фактической печати), это ограничение снимается — нужно уточнить у NST-стороны фактическое поведение перед фиксацией значения TTL.

Идемпотентность на стороне воркера: RabbitMQ гарантирует минимум одну доставку — если `ack` потеряется после того, как NST уже принял задание, сообщение переотправится и `print_handler.py` попробует отправить его повторно, а значит *физически напечатает документ второй раз*. Перед `submit` воркер обязан проверить `print_jobs.nst_job_ref` по `job_id`: если запись уже есть — не отправлять повторно, а перейти сразу к опросу статуса существующего `nst_job_ref`.

Ответ NST при приёме:
```json
{
  "job_id": "t_7c1e9a3b",
  "nst_job_ref": "NST-2026-889231",
  "status": "received"
}
```

Callback NST → API (изменение статуса задания печати). Запрос подписывается общим секретом (`X-Signature: HMAC-SHA256(body, NST_CALLBACK_SECRET)`), API отклоняет запрос без валидной подписи:
```json
{
  "nst_job_ref": "NST-2026-889231",
  "job_id": "t_7c1e9a3b",
  "status": "printed",
  "printed_at": "2026-09-10T09:14:40Z",
  "pages": 1
}
```

Связь статусов: `task.status` не приравнивается к `print_job.status` напрямую. Задача переходит в `success`, когда `print_job.status = printed`; переходит в `failed` при `print_job.status = failed`. Промежуточные статусы NST (`received`, `queued`, `printing`) отображаются в `task.status = running` — детали видны в `print_jobs.status` отдельно, чтобы не терять информацию при агрегации.

---

=== 5.3 Worker → FTP/SFTP Handler — внутренний контракт задачи

Тело сообщения RabbitMQ (`q.ftp`):
```json
{
  "task_id": "t_c02a71f4",
  "type": "ftp",
  "action": "upload",
  "profile": "exchange-outgoing",
  "local_path": "/app/data/documents/generated/invoice-INV-2026-000481.pdf",
  "remote_path": "/outgoing/invoice-INV-2026-000481.pdf",
  "on_success": { "delete_local": false },
  "attempt": 1
}
```

---

== 6. таблицы статусов

=== 6.1 Статус задачи (`tasks.status`, PostgreSQL + Redis cache)

#table(
  columns: 4,
  table.header(
    [Статус], [Описание], [Переход из], [Переход в],
  ),
  [`pending`], [задача создана, ещё не опубликована в очередь], [—], [`queued`],
  [`queued`], [задача в очереди RabbitMQ, ожидает воркера], [`pending`, `retrying`], [`running`, `cancelled`],
  [`running`], [воркер выполняет задачу], [`queued`], [`success`, `failed`, `retrying`],
  [`retrying`], [задача вернулась в очередь после ошибки, ждёт повторной попытки], [`failed` (если `attempts < max_attempts`)], [`queued`],
  [`success`], [задача выполнена успешно], [`running`], [— (финальный)],
  [`failed`], [ошибка выполнения, попытки исчерпаны], [`running`], [`dead_letter`],
  [`dead_letter`], [задача ушла в DLQ после исчерпания retry], [`failed`], [— (требует ручного разбора)],
  [`cancelled`], [задача отменена пользователем/системой], [`pending`, `queued`], [— (финальный)],
)


=== 6.2 Статус задания печати (NST → API, отдельное поле `print_jobs.status`)

#table(
  columns: 3,
  table.header(
    [Статус], [Источник], [Описание],
  ),
  [`received`], [NST], [задание принято Print Gateway],
  [`queued`], [NST], [задание в очереди Windows Spooler],
  [`printing`], [NST], [идёт печать],
  [`printed`], [NST], [печать завершена успешно],
  [`failed`], [NST], [ошибка печати (принтер офлайн, нет бумаги и т.п.)],
  [`cancelled`], [NST / API], [задание отменено],
)


=== 6.3 Статус принтера (`GET /api/v1/printers`)

#table(
  columns: 2,
  table.header(
    [Статус], [Описание],
  ),
  [`online`], [принтер доступен, принимает задания],
  [`busy`], [принтер печатает текущее задание],
  [`offline`], [принтер недоступен (сеть/выключен)],
  [`error`], [ошибка устройства (бумага, картридж, замятие)],
  [`unknown`], [статус не опрошен / нет данных от NST],
)


=== 6.4 Статус воркера / consumer health (для System Health в Web Task Monitor)

#table(
  columns: 2,
  table.header(
    [Статус], [Описание],
  ),
  [`starting`], [воркер запускается, подключается к RabbitMQ/Redis],
  [`ready`], [воркер подключён, ожидает сообщений],
  [`consuming`], [воркер обрабатывает сообщение],
  [`degraded`], [воркер работает, но есть ошибки подключения (например, NST недоступен)],
  [`stopped`], [воркер остановлен / контейнер завершён],
)


=== 6.5 Коды ошибок задач (`error.code`)

#table(
  columns: 2,
  table.header(
    [Код], [Описание],
  ),
  [`NST_PRINTER_OFFLINE`], [принтер недоступен на момент печати],
  [`NST_TIMEOUT`], [NST не ответил в течение таймаута],
  [`TEMPLATE_NOT_FOUND`], [Typst-шаблон отсутствует в `/app/templates`],
  [`TEMPLATE_RENDER_ERROR`], [ошибка рендеринга шаблона (некорректные данные)],
  [`FTP_CONNECTION_ERROR`], [не удалось подключиться к FTP/SFTP],
  [`FTP_AUTH_ERROR`], [ошибка аутентификации на FTP/SFTP],
  [`STORAGE_WRITE_ERROR`], [ошибка записи в `/app/data` или SMB share],
  [`LOCK_TIMEOUT`], [не удалось получить distributed lock в Redis за отведённое время],
  [`VALIDATION_ERROR`], [некорректное тело запроса при создании задачи],
)


---

== 7. retry-политика по типам задач

#table(
  columns: 4,
  table.header(
    [Тип задачи], [`max_attempts`], [Backoff], [Примечание],
  ),
  [`print`], [3], [30s → 2m → 10m], [после 3-й неудачи → `dead_letter`, алерт оператору (принтер, скорее всего, офлайн)],
  [`pdf.generate`], [2], [5s → 30s], [повтор не помогает при `TEMPLATE_RENDER_ERROR` — сразу `dead_letter` без выжидания],
  [`convert`], [2], [10s → 1m], [],
  [`ftp`], [5], [15s → 1m → 5m → 15m → 30m], [сетевые сбои чаще временные, выше `max_attempts`],
  [`workflow`], [0 (не ретраится целиком)], [—], [повторяется отдельный отказавший шаг, не весь workflow],
)


`TEMPLATE_RENDER_ERROR` и `VALIDATION_ERROR` не ретраятся ни для одного типа — это ошибки данных, а не инфраструктуры, повтор с теми же данными даст тот же результат.

---

== 8. безопасность

- *Аутентификация API*: JWT, выданный на основе учётных данных Business Central (OAuth2 client credentials от NST/BC для серверных вызовов; пользовательский JWT — для Web Client/Mobile App через BC). Для сторонних систем (`External System (3rd party)`) — отдельные API-ключи с ограниченным набором прав (только `POST /tasks/print`, `POST /documents`).
- *Callback от NST* (`/internal/print-callback`) — подписывается `X-Signature` (HMAC), секрет — в `.env` (`NST_CALLBACK_SECRET`), не в git.
- *Сетевая изоляция*: RabbitMQ (5672/15672), Redis (6379), PostgreSQL (5432) не публикуются наружу — доступны только внутри docker-сети `docker-compose.yml`. Наружу смотрят только FastAPI (443 через reverse proxy) и Web Task Monitor.
- *RBAC на уровне API*: минимум две роли — `operator` (Web Task Monitor: просмотр, retry, cancel) и `service` (создание задач от BC/3rd party). Хранится в таблице `users`/`permissions` (PostgreSQL, см. чеклист п.7).
- *Секреты*: `.env` на хосте, права `600`, не коммитится (`.gitignore`); ротация паролей RabbitMQ/Redis/PostgreSQL — вручную по регламенту, отдельным пунктом не автоматизируется на первом этапе.

== 9. эксплуатация

- *Retention документов*: `/app/data/documents/generated` и `/incoming` — автоочистка файлов старше 90 дней через cron на хосте (`ops/backup/` дополняется `ops/retention/cleanup-documents.sh`); `/archive` не чистится (переносится на SMB `archive` вручную/по расписанию).
- *`ops/healthcheck/check-stack.sh`* проверяет: подключение к RabbitMQ (AMQP heartbeat), Redis (`PING`), PostgreSQL (`SELECT 1`), доступность NST (`GET /health` на Print Gateway, если есть). Разделение жёстких/мягких зависимостей: `GET /health/ready` (используется для вывода из балансировки) зависит только от RabbitMQ/Redis/PostgreSQL — недоступность NST не должна ронять весь API из readiness, иначе одновременно остановится и приём задач на конвертацию/генерацию PDF, которые от NST не зависят. Статус NST — отдельное поле `GET /health` (информационное, для System Health в Web Task Monitor), не влияющее на readiness-пробу.
- *Многоворкерная координация*: при масштабировании `Worker Container(s)` на N реплик — `prefetch_count` на consumer ограничивает число параллельно взятых сообщений на инстанс; операции с общим ресурсом (запись в один файл, один и тот же принтер) защищены Redis-локом (`core/locks.py`). Фиксированный TTL без продления опасен в обе стороны: короткий TTL истекает раньше, чем реально завершится операция (второй воркер получает тот же лок, пока первый ещё работает — race, от которой лок должен защищать); длинный TTL надолго блокирует ресурс при падении воркера, держащего лок. Поэтому `locks.py` реализует продление (heartbeat каждые TTL/3 из отдельного потока/таска, пока операция выполняется) вместо однократной установки TTL "с запасом".
- *Реконсиляция зависших print-заданий*: `print_handler.py` полагается на push-callback от NST (раздел 5.2), но сеть между NST и API может оборваться именно в момент отправки callback — задача физически напечатана, но система об этом не узнает и `task.status` останется в `running` навсегда. Отдельный периодический job (`reconciler`, часть `outbox-relay` или отдельный процесс) опрашивает `print_jobs` в статусе `received`/`printing` дольше настраиваемого порога (например, 15 минут) и запрашивает у NST актуальный статус по `nst_job_ref` напрямую, а не ждёт callback бесконечно.

---

== 10. чеклист реализации (порядок работ)

1. `infra/rabbitmq/definitions.json` — описать exchange/queues/DLQ, поднять RabbitMQ Container с импортом топологии при старте.
2. `libs/common/statuses.py` — enum'ы статусов (раздел 6) как единый источник правды для api и worker.
3. Alembic-миграции: таблицы `tasks` (с `payload` JSONB, раздел 4.1), `tasks_outbox`, `workflow_steps`, `print_jobs`, `documents`, `printers`, `users`, `permissions`, `workflow_history` (роли `operator`/`service` — раздел 8).
4. `services/api` — CRUD задач + `cancel`/`retry` (из `tasks.payload`), `POST /documents` (upload), auth (JWT от BC + API-ключи для 3rd party), `mq_publisher.py` + outbox-relay (раздел 4.1), `cache.py` (Redis), health-эндпоинты (жёсткие vs мягкие зависимости, раздел 9).
5. `services/worker` — `dispatcher.py` (с проверкой `cancelled` перед выполнением) + handlers по одному на тип задачи (со своей retry-политикой, раздел 7, и проверкой идемпотентности перед внешним побочным эффектом — раздел 4.1), `locks.py` (Redis locks с продлением/heartbeat, раздел 9) для конкурентных операций.
6. Интеграция NST client (`nst_client.py`) — submit с проверкой идемпотентности по `print_jobs.nst_job_ref` + callback endpoint в API (`/internal/print-callback`) с проверкой HMAC-подписи; адресация через реальный сетевой hostname API, не docker-internal DNS (раздел 5.2); отдельный `reconciler` для зависших `print_jobs` без callback (раздел 9).
7. `services/web-task-monitor` — Dashboard/TaskList/TaskDetails (+ retry/cancel из UI) на базе REST + WS.
8. `ops/healthcheck/check-stack.sh` — проверка RabbitMQ/Redis/PostgreSQL/NST доступности для System Health.
9. Настроить `x-dead-letter-exchange` и алерт на непустую `q.dead_letter` (Observable из Roles Summary).
10. `ops/retention/cleanup-documents.sh` — автоочистка `/app/data/documents` по сроку хранения (раздел 9).

---

== 11. дорожная карта mvp: ftp — первый воркер

Раздел 10 — порядок реализации по архитектурным слоям (сначала вся инфраструктура, потом все типы задач сразу). Здесь — порядок по *срезам*, если первым нужно довести до конца именно FTP: минимальный сквозной путь (API → outbox → RabbitMQ → Worker → внешний эффект → статус → UI) проверяется на самом простом типе задачи, где нет ни NST, ни Business Central, ни Typst — только протокол FTP/SFTP с понятной семантикой успеха/ошибки. Остальные типы (`pdf.generate`, `print`, `workflow`) добавляются позже как handler'ы поверх уже проверенного пайплайна, не раньше.

*M1. Инфраструктурный скелет*
`docker-compose.yml` (раздел 3.1) только с `rabbitmq`, `redis`, `postgres` — без `api`/`worker`. Сетевая изоляция и healthcheck'и сразу (раздел 8), чтобы не переделывать позже. `api`/`worker` подключаются на следующем шаге, когда есть куда публиковать и что слушать.

*M2. Топология RabbitMQ — только FTP*
Из раздела 4 поднимается `tasks.direct`/`task.ftp`/`q.ftp` и `tasks.dlx`/`q.dead_letter`. Остальные routing key (`task.print`, `task.pdf.generate`, `task.convert`, `task.workflow`) не создаются заранее вхолостую — добавляются вместе со своим handler'ом на будущих срезах.

*M3. Минимальная схема PostgreSQL*
`tasks` (с `payload` JSONB — раздел 4.1), `tasks_outbox`, единый `libs/common/statuses.py`. Auth на этом этапе — один статический API-ключ в `.env`, не полноценный JWT/BC (раздел 8) — интеграция с Business Central не нужна, пока нет ни одной BC-зависимой задачи (печать, где BC/NST реально участвуют).

*M4. Outbox-relay — сразу, не отложенным довеском*
Раздел 4.1 — реализуется на первом же типе задачи, а не после того, как "всё уже написано напрямую через `mq_publisher.py`". Смысл именно в том, чтобы паттерн надёжной публикации (`tasks_outbox` → `SELECT … FOR UPDATE SKIP LOCKED` → publish → mark published) был проверен на простом случае и затем переиспользован для `print`/`pdf.generate`/`workflow` без повторной работы.

*M5. FastAPI: только FTP-эндпоинты*
`POST /api/v1/tasks/ftp` (профиль из `ftp.yaml`, `action: upload/download`), `GET /tasks/{id}`, `GET /tasks`, `POST /tasks/{id}/cancel`, `POST /tasks/{id}/retry`. `GET /health/ready` проверяет RabbitMQ/Redis/PostgreSQL — NST в проверку пока не входит, потому что ещё не участвует ни в одной задаче.

*M6. Worker: `dispatcher.py` + `ftp_handler.py`*
Consume `q.ftp`, подключение по `ftp.yaml`-профилям, `upload`/`download`. Сразу с тем, что было выделено как обязательное в разборе (не откладывать на потом):
- проверка `cancelled` перед выполнением (раздел 5.1);
- идемпотентность — проверка, не выполнялась ли уже эта `task_id`, перед повторной загрузкой файла (раздел 4.1);
- retry-политика `ftp`: 5 попыток, 15s → 1m → 5m → 15m → 30m (раздел 7).

*M7. WS + Web Task Monitor — минимальный UI*
`notifier.py` (Redis Pub/Sub) и `/ws/tasks?task_id=`. Web Task Monitor — только `TaskList`/`TaskDetails`, без `WorkflowView`/`PrinterStatus` (бессмысленны до появления `workflow` и `print`).

*M8. Сквозная проверка отказоустойчивости на FTP*
Искусственно сломать FTP-профиль (неверный хост/креды) → убедиться, что retry идёт с ожидаемым backoff → `dead_letter` после 5-й попытки → ручной `POST /tasks/{id}/retry` поднимает задачу заново из `tasks.payload`. Это тот же сценарий, который затем должен воспроизводиться для `print`/`pdf.generate` — на FTP он дешевле всего проверяется (не нужен реальный принтер или NST-стенд).

*M9. Опер-минимум*
`ops/healthcheck/check-stack.sh`, `ops/backup/backup-postgres.sh`, `logrotate.d/cloudready` — то, что нужно, чтобы первый воркер можно было оставить в проде без ручного присмотра.

*Дальше — по одному типу задачи за раз, поверх готового пайплайна:*
1. `pdf.generate` (Typst) — следующий по сложности: внешней сети/авторизации не требует, только бинарник Typst и файловую систему; хорошая проверка паттерна на "чистой" (без сети) задаче.
2. `print` (NST) — самый сложный срез: реальная сетевая адресация (раздел 5.2), HMAC-подпись callback'а, идемпотентность по `nst_job_ref`, `reconciler` для зависших заданий (раздел 9). Делается последним из "простых" типов, когда паттерн retry/DLQ/идемпотентности уже обкатан на FTP и PDF.
3. `workflow` — имеет смысл только когда есть *минимум два* готовых типа задачи, которые можно связать в цепочку (например, `pdf.generate → print → ftp.upload`, раздел 5.1); строить раньше — оркестрировать нечего.