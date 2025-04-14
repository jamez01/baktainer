# frozen_string_literal: true

# MySQL backup command generator
class Baktainer::BackupCommand
    def mysql(login:, password:, database:)
      {
        env: [],
        cmd: ['mysqldump', '-u', login, "-p#{password}", database]
      }
    end
end
