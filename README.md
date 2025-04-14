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
      - baktainer.backup: "true"
      - baktainer.db.name: "my-db"
      - baktainer.db.password: "StrongPassword"
      - baktainer.db.engine: "postgres"
      - baktainer.name: "MyApp"
```
