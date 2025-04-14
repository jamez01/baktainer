# frozen_string_literal: true

# mariadb backup command generator
class Baktainer::BackupCommand
    def mariadb(login:, password:, database:)
      {
        env: [],
        cmd: ['mariadb-dump', "-u#{login}", "-p#{password}", '--databases', database]
      }
    end
end
