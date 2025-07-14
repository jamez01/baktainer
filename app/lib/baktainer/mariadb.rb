# frozen_string_literal: true

# mariadb backup command generator
class Baktainer::BackupCommand
    def mariadb(login:, password:, database:)
      {
        env: [],
        cmd: ['mysqldump', '-u', login, "-p#{password}", database]
      }
    end
end
