# baktainer
Easily backup databases running in docker containers.
## Features
- Backup MySQL, PostgreSQL, MongoDB, and SQLite databases
- Run on a schedule using cron expressions
- Backup databases running in docker containers
- Define which databases to backup using docker labels
## Installation
```yaml
services:
  baktainer:
    image: jamez01/baktainer:latest
    container_name: baktainer
    restart: unless-stopped
    volumes:
      - ./backups:/backups
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - BT_CRON="0 0 * * *" # Backup every day at midnight
      - "BT_DOCKER_URL=unix:///var/run/docker.sock" 
      - BT_THREADS=4
      - BT_BACKUP_DIR=/backups
      - BT_LOG_LEVEL=info
      # Enable if using SSL over tcp
      #- BT_SSL = true
      #- BT_CA
      #- BT_CERT
      #- BT_KEY    
```

## Environment Variables
| Variable | Description | Default |
| -------- | ----------- | ------- |
| BT_CRON | Cron expression for scheduling backups | 0 0 * * * |
| BT_THREADS | Number of threads to use for backups | 4 |
| BT_BACKUP_DIR | Directory to store backups | /backups |
| BT_LOG_LEVEL | Log level (debug, info, warn, error) | info |
| BT_SSL | Enable SSL for docker connection | false |
| BT_CA | Path to CA certificate | none |
| BT_CERT | Path to client certificate | none |
| BT_KEY | Path to client key | none |
| BT_DOCKER_URL | Docker URL | unix:///var/run/docker.sock |

## Usage
Add labels to your docker containers to specify which databases to backup. 
```yaml
services:
  db:
    image: postgres:17
    container_name: my-db
    restart: unless-stopped
    volumes:
    - db:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: "${DB_BASE:-database}"
      POSTGRES_USER: "${DB_USER:-user}"
      POSTGRES_PASSWORD: "${DB_PASSWORD:-StrongPassword}"
    labels:
      - baktainer.backup=true
      - baktainer.db.engine=postgres
      - baktainer.db.name=my-db
      - baktainer.db.user=user
      - baktainer.db.password=StrongPassword
      - baktainer.name="MyApp"
```

## Possible Values for Labels
| Label | Description |
| ----- | ----------- |
| baktainer.backup | Set to true to enable backup for this container |
| baktainer.db.engine | Database engine (mysql, postgres, mongodb, sqlite) |
| baktainer.db.name | Name of the database to backup |
| baktainer.db.user | Username for the database |
| baktainer.db.password | Password for the database |
| baktainer.name | Name of the application (optional). Determines name of sql dump file. |

## Backup Files
The backup files will be stored in the directory specified by the `BT_BACKUP_DIR` environment variable. The files will be named according to the following format:
```
/backups/<date>/<db_name>_<timestamp>.sql
```
Where `<db_name>` is the name of the database, `<timestamp>` is the unix timestamp of the backup, and `<extension>` is the file extension for the backup format (e.g. .sql for MySQL, .sql.gz for compressed MySQL backups, .dump for PostgreSQL, etc.).

## Roadmap
- [x] Add support for SQLite backups
- [x] Add support for MongoDB backups
- [x] Add support for MySQL backups
- [x] Add support for PostgreSQL backups
- [x] Add support for cron scheduling
- [x] Add support for Docker labels to specify which databases to backup
- [x] Add support for Docker socket
- [x] Add support for Docker API over TCP
- [x] Add support for Docker API over SSL
- [x] Add support for Docker API over HTTP
- [x] Add support for Docker API over HTTPS
- [x] Add support for Docker API over Unix socket
- [ ] Add individual hook for completed backups
- [ ] Add hook for fullly completed backups
- [ ] Optionally limit time for each backup