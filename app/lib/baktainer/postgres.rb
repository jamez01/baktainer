# frozen_string_literal: true

# Postgres backup command generator
class Baktainer::BackupCommand
  def postgres(login: 'postgres', password: nil, database: nil, all: false)
    {
      env: [
        "PGPASSWORD=#{password}",
        "PGUSER=#{login}",
        "PGDATABASE=#{database}",
        'PGAPPNAME=Baktainer'
      ],
      cmd: [all ? 'pg_dumpall' : 'pg_dump']
    }
  end

  def postgres_all(login: 'postgres', password: nil, database: nil)
    posgres(login: login, password: password, database: database, all: true)
  end

  def postgresql(*args)
    postgres(*args)
  end

  def postgresql_all(*args)
    postgres_all(*args)
  end
end
