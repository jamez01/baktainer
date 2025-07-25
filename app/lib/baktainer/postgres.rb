# frozen_string_literal: true

# Postgres backup command generator
class Baktainer::BackupCommand
  def postgres(login: 'postgres', password: nil, database: nil, all: false)
    if all
      {
        env: ["PGPASSWORD=#{password}"],
        cmd: ['pg_dumpall', '-U', login]
      }
    else
      {
        env: ["PGPASSWORD=#{password}"],
        cmd: ['pg_dump', '-U', login, '-d', database]
      }
    end
  end

  def postgres_all(login: 'postgres', password: nil, database: nil)
    postgres(login: login, password: password, database: database, all: true)
  end

  def postgresql(**kwargs)
    postgres(**kwargs)
  end

  def postgresql_all(**kwargs)
    postgres_all(**kwargs)
  end
end
