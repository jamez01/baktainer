# frozen_string_literal: true

# sqlite backup command generator
class Baktainer::BackupCommand
  class << self
    def sqlite(database:, _login: nil, _password: nil)
      {
        env: [],
        cmd: ['sqlite3', database, '.dump']
      }
    end
  end
end
